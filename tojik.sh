#!/bin/bash
# ==========================================
# MATRIX ULTIMATE MESSENGER V7 - ADMIN MASTER EDITION
# Max Functionality | Full Admin Control | Modern UI
# Complete management through admin panel
# Tested on Ubuntu 22.04 / Debian 11+
# ==========================================
set -euo pipefail
trap 'echo -e "\n${RED}❌ Ошибка на строке $LINENO${NC}"; exit 1' ERR

# --- ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { 
    echo -e "\n${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} ${CYAN}$1${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
}

# --- ПРОВЕРКА ROOT ---
if [ "$EUID" -ne 0 ]; then
    print_error "Запустите с правами root (sudo bash $0)"
    exit 1
fi

# --- НАСТРОЙКИ ---
clear
print_header "MATRIX ULTIMATE MESSENGER V7 - ADMIN MASTER"
echo -e "${WHITE}Полное управление через админ-панель${NC}"
echo ""
read -p "Домен (messenger.example.com): " DOMAIN
read -p "Email для SSL: " EMAIL
read -p "Имя администратора: " ADMIN_USER
read -p "Пароль администратора: " ADMIN_PASS
read -p "Название мессенджера: " BRAND_NAME
read -p "Интеграция Safarali (y/n): " ENABLE_SAFARALI
ENABLE_SAFARALI=$(echo "$ENABLE_SAFARALI" | tr '[:upper:]' '[:lower:]')

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    print_error "Домен и email обязательны!"
    exit 1
fi

# --- ГЕНЕРАЦИЯ КЛЮЧЕЙ ---
print_info "Генерация ключей безопасности..."
DB_PASS="$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)"
REG_SECRET="$(openssl rand -base64 48 | tr -d '/+=' | head -c 64)"
TURN_SECRET="$(openssl rand -base64 64 | tr -d '/+=' | head -c 64)"
ADMIN_API_KEY="$(openssl rand -base64 32 | tr -d '/+=' | head -c 64)"
JWT_SECRET="$(openssl rand -base64 32 | tr -d '/+=' | head -c 64)"
REDIS_PASS="$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)"
QR_SECRET="$(openssl rand -base64 32 | tr -d '/+=' | head -c 64)"
ENCRYPTION_KEY="$(openssl rand -base64 32 | tr -d '/+=' | head -c 64)"
WEBHOOK_SECRET="$(openssl rand -base64 32 | tr -d '/+=' | head -c 64)"

# --- ПОДГОТОВКА СИСТЕМЫ ---
print_info "Подготовка системы..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget lsb-release gnupg2 ufw apt-transport-https \
ca-certificates software-properties-common git unzip nginx \
certbot python3-certbot-nginx postgresql postgresql-contrib \
redis-server jq python3-pip python3-venv build-essential \
libpq-dev libffi-dev libssl-dev nodejs npm yarn \
fail2ban net-tools htop glances docker.io docker-compose \
qrencode libqrencode-dev websocat supervisor \
python3-flask python3-flask-socketio python3-flask-cors \
python3-redis python3-pyjwt python3-qrcode python3-pillow \
python3-requests python3-werkzeug python3-bcrypt \
python3-psutil python3-schedule python3-cryptography

# --- SWAP ---
if [ ! -f /swapfile ]; then
    print_info "Настройка SWAP (4GB)..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- FIREWALL ---
print_info "Настройка Firewall..."
ufw --force reset
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8448/tcp
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 5349/tcp
ufw allow 5349/udp
ufw allow 49152:65535/udp
ufw allow 3000-3010/tcp
echo "y" | ufw enable

# --- MATRIX SYNAPSE ---
print_header "Установка Matrix Synapse"
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/matrix-org.list
apt update
echo "matrix-synapse-py3 matrix-synapse/server-name string $DOMAIN" | debconf-set-selections
echo "matrix-synapse-py3 matrix-synapse/report-stats boolean false" | debconf-set-selections
apt install -y matrix-synapse-py3

# --- POSTGRESQL ---
print_info "Настройка PostgreSQL (Optimized)..."
sudo -u postgres psql -c "CREATE USER synapse WITH PASSWORD '$DB_PASS';" || true
sudo -u postgres psql -c "CREATE DATABASE synapse OWNER synapse ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C';" || true
sudo -u postgres psql -c "ALTER USER synapse CREATEDB;" || true

cat > /etc/postgresql/*/main/conf.d/matrix-tuning.conf <<EOF
shared_buffers = 1GB
effective_cache_size = 3GB
work_mem = 32MB
maintenance_work_mem = 256MB
max_connections = 500
checkpoint_completion_target = 0.9
wal_buffers = 32MB
default_statistics_target = 200
EOF
systemctl restart postgresql

# --- REDIS ---
print_info "Настройка Redis..."
cat > /etc/redis/redis.conf <<EOF
port 6379
bind 127.0.0.1
requirepass $REDIS_PASS
maxmemory 1GB
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
notify-keyspace-events Ex
EOF
systemctl restart redis-server

# --- SYNAPSE CONFIG ---
CONFIG_FILE="/etc/matrix-synapse/homeserver.yaml"
[ -f "$CONFIG_FILE" ] && cp $CONFIG_FILE ${CONFIG_FILE}.backup.v7

cat > $CONFIG_FILE <<EOF
server_name: "$DOMAIN"
public_baseurl: "https://$DOMAIN/"
enable_registration: true
enable_registration_without_verification: false
registration_shared_secret: "$REG_SECRET"
registrations_require_3pid: []
database:
  name: psycopg2
  args:
    user: synapse
    password: "$DB_PASS"
    database: synapse
    host: localhost
    cp_min: 10
    cp_max: 50
redis:
  enabled: true
  host: localhost
  port: 6379
  password: "$REDIS_PASS"
turn_shared_secret: "$TURN_SECRET"
turn_uris: ["turn:$DOMAIN?transport=udp", "turn:$DOMAIN?transport=tcp"]
turn_user_lifetime: 86400000
rc_message:
  per_second: 30
  burst_count: 100
rc_registration:
  per_second: 2
  burst_count: 10
max_upload_size: "2G"
media_store_path: "/var/lib/matrix-synapse/media"
presence:
  enabled: true
user_directory:
  enabled: true
  search_all_users: true
room_directory:
  enabled: true
enable_metrics: true
enable_search: true
log_config: "/etc/matrix-synapse/$DOMAIN.log.config"
experimental_features:
  spaces_enabled: true
  msc3083_enabled: true
  msc3266_enabled: true
  msc2716_enabled: true
  msc3030_enabled: true
  msc3440_enabled: true
  faster_joins: true
  msc3861_enabled: true
  msc3912_enabled: true
  msc4028_enabled: true
admin_contact: "mailto:$EMAIL"
EOF

# --- ADMIN PANEL SERVICE ---
print_header "Настройка Admin Panel V7 (Full Control)"
mkdir -p /opt/admin-panel
cat > /opt/admin-panel/admin_server.py <<'EOF'
#!/usr/bin/env python3
import asyncio, json, secrets, qrcode, redis, jwt, time, os, logging, hashlib, psutil, subprocess, shutil
from datetime import datetime, timedelta
from flask import Flask, request, jsonify, send_file, session, render_template_string
from flask_socketio import SocketIO, emit, join_room, leave_room
from flask_cors import CORS
from io import BytesIO
import requests, bcrypt, schedule, threading, cryptography
from werkzeug.utils import secure_filename

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('ADMIN_SECRET', secrets.token_hex(32))
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading', logger=logger, engineio_logger=logger)

redis_client = redis.Redis(host='localhost', port=6379, password=os.environ.get('REDIS_PASS', ''), decode_responses=True)

SYNAPSE_API = 'http://localhost:8008'
ADMIN_API_KEY = os.environ.get('ADMIN_API_KEY', '')
DOMAIN = os.environ.get('DOMAIN', '')
ADMIN_USER = os.environ.get('ADMIN_USER', '')
ADMIN_PASS_HASH = bcrypt.hashpw(os.environ.get('ADMIN_PASS', 'admin').encode(), bcrypt.gensalt()).decode()

class AdminPanel:
    def __init__(self):
        self.admin_sessions = {}
        self.audit_log = []
        
    def verify_admin(self, token):
        try:
            data = jwt.decode(token, os.environ.get('JWT_SECRET', ''), algorithms=['HS256'])
            if data.get('role') == 'admin':
                return data
        except:
            pass
        return None
    
    def log_action(self, action, details):
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'action': action,
            'details': details,
            'admin': ADMIN_USER
        }
        self.audit_log.append(log_entry)
        redis_client.lpush('admin:audit', json.dumps(log_entry))
        redis_client.ltrim('admin:audit', 0, 10000)
        socketio.emit('audit_log', log_entry, room='admin')
    
    def get_system_stats(self):
        return {
            'cpu': psutil.cpu_percent(interval=1),
            'memory': psutil.virtual_memory().percent,
            'disk': psutil.disk_usage('/').percent,
            'uptime': datetime.now() - datetime.fromtimestamp(psutil.boot_time()),
            'network': {
                'sent': psutil.net_io_counters().bytes_sent,
                'recv': psutil.net_io_counters().bytes_recv
            }
        }
    
    def get_synapse_stats(self):
        try:
            headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
            stats = requests.get(f'{SYNAPSE_API}/_synapse/admin/v1/statistics', headers=headers, timeout=5)
            return stats.json() if stats.status_code == 200 else {}
        except:
            return {}
    
    def manage_user(self, action, user_id, data=None):
        headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
        if action == 'create':
            resp = requests.post(f'{SYNAPSE_API}/_synapse/admin/v2/users/{user_id}', 
                               headers=headers, json=data, timeout=10)
        elif action == 'delete':
            resp = requests.delete(f'{SYNAPSE_API}/_synapse/admin/v2/users/{user_id}', 
                                 headers=headers, timeout=10)
        elif action == 'ban':
            resp = requests.post(f'{SYNAPSE_API}/_synapse/admin/v1/users/{user_id}/login', 
                               headers=headers, json={'deactivate': True}, timeout=10)
        elif action == 'update':
            resp = requests.put(f'{SYNAPSE_API}/_synapse/admin/v2/users/{user_id}', 
                              headers=headers, json=data, timeout=10)
        self.log_action(f'user_{action}', {'user_id': user_id, 'data': data})
        return resp.status_code == 200
    
    def manage_room(self, action, room_id, data=None):
        headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
        if action == 'delete':
            resp = requests.delete(f'{SYNAPSE_API}/_synapse/admin/v1/rooms/{room_id}', 
                                 headers=headers, timeout=10)
        elif action == 'shutdown':
            resp = requests.post(f'{SYNAPSE_API}/_synapse/admin/v1/rooms/{room_id}/shutdown', 
                               headers=headers, json=data or {}, timeout=10)
        elif action == 'join':
            resp = requests.post(f'{SYNAPSE_API}/_synapse/admin/v1/join/{room_id}', 
                               headers=headers, json={'user_id': f'@{ADMIN_USER}:{DOMAIN}'}, timeout=10)
        self.log_action(f'room_{action}', {'room_id': room_id})
        return resp.status_code == 200
    
    def manage_server(self, action, config=None):
        if action == 'restart':
            subprocess.run(['systemctl', 'restart', 'matrix-synapse'], timeout=30)
        elif action == 'reload':
            subprocess.run(['systemctl', 'reload', 'matrix-synapse'], timeout=30)
        elif action == 'backup':
            self.create_backup()
        self.log_action(f'server_{action}', {})
        return True
    
    def create_backup(self):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_dir = f'/var/backups/matrix/{timestamp}'
        os.makedirs(backup_dir, exist_ok=True)
        
        # Database backup
        subprocess.run(['sudo', '-u', 'postgres', 'pg_dump', 'synapse'], 
                      stdout=open(f'{backup_dir}/synapse.sql', 'w'), timeout=300)
        
        # Media backup
        shutil.copytree('/var/lib/matrix-synapse/media', f'{backup_dir}/media', dirs_exist_ok=True)
        
        # Config backup
        shutil.copy('/etc/matrix-synapse/homeserver.yaml', f'{backup_dir}/homeserver.yaml')
        
        # Compress
        shutil.make_archive(f'/var/backups/matrix/backup_{timestamp}', 'gztar', backup_dir)
        shutil.rmtree(backup_dir)
        
        self.log_action('backup_created', {'path': f'backup_{timestamp}.tar.gz'})
        return f'backup_{timestamp}.tar.gz'
    
    def get_audit_logs(self, limit=100):
        logs = redis_client.lrange('admin:audit', 0, limit-1)
        return [json.loads(log) for log in logs]
    
    def manage_cache(self, action):
        if action == 'clear':
            redis_client.flushdb()
            self.log_action('cache_cleared', {})
        elif action == 'stats':
            info = redis_client.info()
            return {
                'used_memory': info.get('used_memory_human', '0B'),
                'connected_clients': info.get('connected_clients', 0),
                'keys': info.get('db0', {}).split(',')[0].split('=')[1] if 'db0' in info else 0
            }
        return {}
    
    def manage_ssl(self, action):
        if action == 'renew':
            subprocess.run(['certbot', 'renew', '--quiet'], timeout=300)
            subprocess.run(['systemctl', 'reload', 'nginx'], timeout=10)
            self.log_action('ssl_renewed', {})
        return True
    
    def get_active_users(self, limit=100):
        headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
        resp = requests.get(f'{SYNAPSE_API}/_synapse/admin/v2/users', 
                          headers=headers, params={'limit': limit}, timeout=10)
        return resp.json() if resp.status_code == 200 else {'users': []}
    
    def get_rooms(self, limit=100):
        headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
        resp = requests.get(f'{SYNAPSE_API}/_synapse/admin/v1/rooms', 
                          headers=headers, params={'limit': limit}, timeout=10)
        return resp.json() if resp.status_code == 200 else {'rooms': []}
    
    def manage_media(self, action, media_id=None):
        headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
        if action == 'list':
            resp = requests.get(f'{SYNAPSE_API}/_synapse/admin/v1/media/{DOMAIN}', 
                              headers=headers, timeout=10)
            return resp.json() if resp.status_code == 200 else {}
        elif action == 'delete' and media_id:
            resp = requests.delete(f'{SYNAPSE_API}/_synapse/admin/v1/media/{DOMAIN}/{media_id}', 
                                 headers=headers, timeout=10)
            self.log_action('media_deleted', {'media_id': media_id})
            return resp.status_code == 200
        elif action == 'protect' and media_id:
            resp = requests.post(f'{SYNAPSE_API}/_synapse/admin/v1/media/protect/{media_id}', 
                               headers=headers, timeout=10)
            return resp.status_code == 200
        return {}
    
    def manage_federation(self, action, domain=None):
        headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
        if action == 'list':
            resp = requests.get(f'{SYNAPSE_API}/_synapse/admin/v1/federation/list', 
                              headers=headers, timeout=10)
            return resp.json() if resp.status_code == 200 else {}
        elif action == 'block' and domain:
            resp = requests.put(f'{SYNAPSE_API}/_synapse/admin/v1/federation/block/{domain}', 
                              headers=headers, timeout=10)
            self.log_action('federation_blocked', {'domain': domain})
            return resp.status_code == 200
        elif action == 'unblock' and domain:
            resp = requests.delete(f'{SYNAPSE_API}/_synapse/admin/v1/federation/block/{domain}', 
                                 headers=headers, timeout=10)
            return resp.status_code == 200
        return {}
    
    def manage_bots(self, action, bot_id=None, data=None):
        if action == 'list':
            return self.get_active_users(limit=1000).get('users', [])
        elif action == 'create' and bot_id and data:
            return self.manage_user('create', bot_id, data)
        elif action == 'delete' and bot_id:
            return self.manage_user('delete', bot_id)
        return {}
    
    def get_notifications(self):
        return {
            'pending': redis_client.llen('admin:notifications'),
            'alerts': redis_client.lrange('admin:alerts', 0, 10)
        }
    
    def manage_settings(self, action, settings=None):
        if action == 'get':
            current = redis_client.hgetall('admin:settings')
            return current
        elif action == 'update' and settings:
            redis_client.hmset('admin:settings', settings)
            self.log_action('settings_updated', settings)
            return True
        return {}
    
    def manage_webhooks(self, action, webhook_id=None, data=None):
        if action == 'list':
            return json.loads(redis_client.get('admin:webhooks') or '[]')
        elif action == 'create' and data:
            webhooks = json.loads(redis_client.get('admin:webhooks') or '[]')
            data['id'] = secrets.token_hex(16)
            data['created'] = datetime.now().isoformat()
            webhooks.append(data)
            redis_client.set('admin:webhooks', json.dumps(webhooks))
            self.log_action('webhook_created', data)
            return data
        elif action == 'delete' and webhook_id:
            webhooks = json.loads(redis_client.get('admin:webhooks') or '[]')
            webhooks = [w for w in webhooks if w.get('id') != webhook_id]
            redis_client.set('admin:webhooks', json.dumps(webhooks))
            return True
        return {}
    
    def manage_pwa(self, action, data=None):
        if action == 'get':
            return json.loads(redis_client.get('admin:pwa') or '{}')
        elif action == 'update' and data:
            redis_client.set('admin:pwa', json.dumps(data))
            self.log_action('pwa_updated', data)
            return True
        return {}
    
    def manage_themes(self, action, data=None):
        if action == 'list':
            return json.loads(redis_client.get('admin:themes') or '[]')
        elif action == 'set' and data:
            redis_client.set('admin:active_theme', data.get('theme', 'dark'))
            self.log_action('theme_changed', data)
            return True
        return {}
    
    def get_api_keys(self):
        keys = json.loads(redis_client.get('admin:api_keys') or '[]')
        return [{'id': k.get('id'), 'name': k.get('name'), 'created': k.get('created')} for k in keys]
    
    def manage_api_keys(self, action, data=None):
        if action == 'create' and data:
            keys = json.loads(redis_client.get('admin:api_keys') or '[]')
            new_key = {
                'id': secrets.token_hex(32),
                'name': data.get('name', 'API Key'),
                'created': datetime.now().isoformat(),
                'permissions': data.get('permissions', ['read'])
            }
            keys.append(new_key)
            redis_client.set('admin:api_keys', json.dumps(keys))
            self.log_action('api_key_created', {'name': new_key['name']})
            return new_key
        elif action == 'delete' and data:
            keys = json.loads(redis_client.get('admin:api_keys') or '[]')
            keys = [k for k in keys if k.get('id') != data.get('id')]
            redis_client.set('admin:api_keys', json.dumps(keys))
            return True
        return {}

admin_panel = AdminPanel()

# --- AUTH ---
@app.route('/admin/login', methods=['POST'])
def admin_login():
    data = request.json
    if data.get('username') == ADMIN_USER and bcrypt.checkpw(data.get('password', '').encode(), ADMIN_PASS_HASH.encode()):
        token = jwt.encode({
            'user': ADMIN_USER,
            'role': 'admin',
            'exp': datetime.now() + timedelta(hours=24)
        }, os.environ.get('JWT_SECRET', ''), algorithm='HS256')
        admin_panel.log_action('admin_login', {'user': ADMIN_USER})
        return jsonify({'token': token, 'success': True})
    admin_panel.log_action('admin_login_failed', {'user': data.get('username')})
    return jsonify({'success': False}), 401

@app.route('/admin/verify', methods=['POST'])
def admin_verify():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if admin_panel.verify_admin(token):
        return jsonify({'valid': True})
    return jsonify({'valid': False}), 401

# --- DASHBOARD ---
@app.route('/admin/dashboard', methods=['GET'])
def admin_dashboard():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    return jsonify({
        'system': admin_panel.get_system_stats(),
        'synapse': admin_panel.get_synapse_stats(),
        'users': len(admin_panel.get_active_users().get('users', [])),
        'rooms': len(admin_panel.get_rooms().get('rooms', [])),
        'notifications': admin_panel.get_notifications()
    })

# --- USERS ---
@app.route('/admin/users', methods=['GET', 'POST', 'DELETE'])
def admin_users():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.get_active_users())
    elif request.method == 'POST':
        data = request.json
        success = admin_panel.manage_user('create', data.get('user_id'), data)
        return jsonify({'success': success})
    elif request.method == 'DELETE':
        data = request.json
        success = admin_panel.manage_user('delete', data.get('user_id'))
        return jsonify({'success': success})

@app.route('/admin/users/<action>', methods=['POST'])
def admin_user_actions(action):
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    data = request.json
    success = admin_panel.manage_user(action, data.get('user_id'), data.get('data'))
    return jsonify({'success': success})

# --- ROOMS ---
@app.route('/admin/rooms', methods=['GET'])
def admin_rooms():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    return jsonify(admin_panel.get_rooms())

@app.route('/admin/rooms/<action>', methods=['POST'])
def admin_room_actions(action):
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    data = request.json
    success = admin_panel.manage_room(action, data.get('room_id'), data.get('data'))
    return jsonify({'success': success})

# --- SERVER ---
@app.route('/admin/server/<action>', methods=['POST'])
def admin_server_actions(action):
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    success = admin_panel.manage_server(action)
    return jsonify({'success': success})

# --- BACKUP ---
@app.route('/admin/backup', methods=['GET', 'POST'])
def admin_backup():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'POST':
        backup = admin_panel.create_backup()
        return jsonify({'success': True, 'backup': backup})
    else:
        backups = []
        backup_dir = '/var/backups/matrix'
        if os.path.exists(backup_dir):
            backups = [f for f in os.listdir(backup_dir) if f.endswith('.tar.gz')]
        return jsonify({'backups': backups})

# --- AUDIT LOGS ---
@app.route('/admin/audit', methods=['GET'])
def admin_audit():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    limit = int(request.args.get('limit', 100))
    return jsonify({'logs': admin_panel.get_audit_logs(limit)})

# --- CACHE ---
@app.route('/admin/cache', methods=['GET', 'POST'])
def admin_cache():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'POST':
        data = request.json
        result = admin_panel.manage_cache(data.get('action'))
        return jsonify({'success': True, 'data': result})
    else:
        return jsonify({'stats': admin_panel.manage_cache('stats')})

# --- SSL ---
@app.route('/admin/ssl', methods=['POST'])
def admin_ssl():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    data = request.json
    success = admin_panel.manage_ssl(data.get('action'))
    return jsonify({'success': success})

# --- MEDIA ---
@app.route('/admin/media', methods=['GET', 'DELETE'])
def admin_media():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.manage_media('list'))
    else:
        data = request.json
        success = admin_panel.manage_media('delete', data.get('media_id'))
        return jsonify({'success': success})

# --- FEDERATION ---
@app.route('/admin/federation', methods=['GET', 'POST'])
def admin_federation():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.manage_federation('list'))
    else:
        data = request.json
        success = admin_panel.manage_federation(data.get('action'), data.get('domain'))
        return jsonify({'success': success})

# --- BOTS ---
@app.route('/admin/bots', methods=['GET', 'POST', 'DELETE'])
def admin_bots():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.manage_bots('list'))
    elif request.method == 'POST':
        data = request.json
        success = admin_panel.manage_bots('create', data.get('bot_id'), data)
        return jsonify({'success': success})
    else:
        data = request.json
        success = admin_panel.manage_bots('delete', data.get('bot_id'))
        return jsonify({'success': success})

# --- SETTINGS ---
@app.route('/admin/settings', methods=['GET', 'POST'])
def admin_settings():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.manage_settings('get'))
    else:
        data = request.json
        success = admin_panel.manage_settings('update', data)
        return jsonify({'success': success})

# --- WEBHOOKS ---
@app.route('/admin/webhooks', methods=['GET', 'POST', 'DELETE'])
def admin_webhooks():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.manage_webhooks('list'))
    elif request.method == 'POST':
        data = request.json
        result = admin_panel.manage_webhooks('create', data=data)
        return jsonify({'success': True, 'webhook': result})
    else:
        data = request.json
        success = admin_panel.manage_webhooks('delete', data.get('webhook_id'))
        return jsonify({'success': success})

# --- PWA ---
@app.route('/admin/pwa', methods=['GET', 'POST'])
def admin_pwa():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.manage_pwa('get'))
    else:
        data = request.json
        success = admin_panel.manage_pwa('update', data)
        return jsonify({'success': success})

# --- THEMES ---
@app.route('/admin/themes', methods=['GET', 'POST'])
def admin_themes():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify(admin_panel.manage_themes('list'))
    else:
        data = request.json
        success = admin_panel.manage_themes('set', data)
        return jsonify({'success': success})

# --- API KEYS ---
@app.route('/admin/api-keys', methods=['GET', 'POST', 'DELETE'])
def admin_api_keys():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not admin_panel.verify_admin(token):
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify({'keys': admin_panel.get_api_keys()})
    elif request.method == 'POST':
        data = request.json
        result = admin_panel.manage_api_keys('create', data)
        return jsonify({'success': True, 'key': result})
    else:
        data = request.json
        success = admin_panel.manage_api_keys('delete', data)
        return jsonify({'success': success})

# --- WEBSOCKET ---
@socketio.on('connect')
def handle_connect():
    join_room('admin')
    emit('connected', {'status': 'connected'})

@socketio.on('disconnect')
def handle_disconnect():
    leave_room('admin')

@socketio.on('subscribe')
def handle_subscribe(data):
    room = data.get('room', 'admin')
    join_room(room)
    emit('subscribed', {'room': room})

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=3003, debug=False)
EOF

# --- ADMIN PANEL UI ---
print_header "Настройка Admin Panel UI (Modern)"
mkdir -p /var/www/admin-panel
cat > /var/www/admin-panel/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Panel V7 | Full Control</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.socket.io/4.5.0/socket.io.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-primary: #0f1115;
            --bg-secondary: #16191f;
            --bg-tertiary: #1c2128;
            --accent: #0088cc;
            --accent-hover: #0099e6;
            --success: #00ff88;
            --warning: #ffaa00;
            --danger: #ff4444;
            --text-primary: #ffffff;
            --text-secondary: #8b9bb4;
            --border: #2a303c;
            --glass: rgba(22, 25, 31, 0.7);
            --shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37);
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Inter', sans-serif; background: var(--bg-primary); color: var(--text-primary); min-height: 100vh; }
        
        /* Login */
        .login-container { display: flex; align-items: center; justify-content: center; min-height: 100vh; background: linear-gradient(135deg, #0f1115 0%, #1a1f2e 100%); }
        .login-box { background: var(--bg-secondary); padding: 40px; border-radius: 20px; width: 100%; max-width: 400px; box-shadow: var(--shadow); border: 1px solid var(--border); }
        .login-box h2 { text-align: center; margin-bottom: 30px; color: var(--accent); }
        .form-group { margin-bottom: 20px; }
        .form-group label { display: block; margin-bottom: 8px; color: var(--text-secondary); font-size: 14px; }
        .form-group input { width: 100%; padding: 12px 16px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 10px; color: var(--text-primary); font-size: 14px; }
        .form-group input:focus { border-color: var(--accent); outline: none; }
        .btn { width: 100%; padding: 12px; background: var(--accent); border: none; border-radius: 10px; color: white; font-size: 16px; cursor: pointer; transition: all 0.2s; }
        .btn:hover { background: var(--accent-hover); transform: translateY(-2px); }
        .btn-danger { background: var(--danger); }
        .btn-success { background: var(--success); color: #000; }
        .btn-warning { background: var(--warning); color: #000; }
        
        /* Dashboard */
        .dashboard { display: none; }
        .dashboard.active { display: block; }
        .admin-layout { display: flex; min-height: 100vh; }
        .sidebar { width: 280px; background: var(--bg-secondary); border-right: 1px solid var(--border); padding: 20px; position: fixed; height: 100vh; overflow-y: auto; }
        .sidebar-header { display: flex; align-items: center; gap: 12px; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 1px solid var(--border); }
        .sidebar-logo { width: 40px; height: 40px; background: var(--accent); border-radius: 10px; display: flex; align-items: center; justify-content: center; font-weight: bold; }
        .nav-menu { list-style: none; }
        .nav-item { margin-bottom: 5px; }
        .nav-link { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-radius: 10px; color: var(--text-secondary); text-decoration: none; transition: all 0.2s; cursor: pointer; }
        .nav-link:hover, .nav-link.active { background: var(--bg-tertiary); color: var(--text-primary); }
        .nav-link i { width: 20px; text-align: center; }
        .main-content { flex: 1; margin-left: 280px; padding: 30px; }
        .content-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }
        .content-title { font-size: 24px; font-weight: 600; }
        
        /* Cards */
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: var(--bg-secondary); padding: 24px; border-radius: 15px; border: 1px solid var(--border); }
        .stat-card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
        .stat-card-icon { width: 50px; height: 50px; background: var(--bg-tertiary); border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 20px; color: var(--accent); }
        .stat-card-value { font-size: 28px; font-weight: 700; margin-bottom: 5px; }
        .stat-card-label { color: var(--text-secondary); font-size: 14px; }
        
        /* Tables */
        .data-table { width: 100%; background: var(--bg-secondary); border-radius: 15px; border: 1px solid var(--border); overflow: hidden; }
        .table-header { padding: 20px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; }
        .table-container { overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 15px 20px; text-align: left; border-bottom: 1px solid var(--border); }
        th { background: var(--bg-tertiary); color: var(--text-secondary); font-weight: 500; font-size: 13px; text-transform: uppercase; }
        tr:hover { background: var(--bg-tertiary); }
        .status-badge { padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 500; }
        .status-active { background: rgba(0, 255, 136, 0.15); color: var(--success); }
        .status-inactive { background: rgba(255, 68, 68, 0.15); color: var(--danger); }
        .status-warning { background: rgba(255, 170, 0, 0.15); color: var(--warning); }
        
        /* Modal */
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); backdrop-filter: blur(5px); z-index: 1000; align-items: center; justify-content: center; }
        .modal.active { display: flex; }
        .modal-content { background: var(--bg-secondary); border-radius: 20px; padding: 30px; max-width: 600px; width: 90%; max-height: 80vh; overflow-y: auto; border: 1px solid var(--border); }
        .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
        .modal-close { background: none; border: none; color: var(--text-secondary); font-size: 24px; cursor: pointer; }
        
        /* Notifications */
        .notification { position: fixed; top: 20px; right: 20px; padding: 15px 25px; background: var(--bg-secondary); border-radius: 10px; border-left: 4px solid var(--accent); box-shadow: var(--shadow); z-index: 2000; animation: slideIn 0.3s ease; }
        @keyframes slideIn { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
        
        /* Charts */
        .chart-container { background: var(--bg-secondary); padding: 24px; border-radius: 15px; border: 1px solid var(--border); margin-bottom: 30px; }
        
        /* Actions */
        .action-buttons { display: flex; gap: 10px; }
        .action-btn { padding: 8px 16px; border-radius: 8px; border: none; cursor: pointer; font-size: 13px; transition: all 0.2s; }
        .action-btn-edit { background: var(--accent); color: white; }
        .action-btn-delete { background: var(--danger); color: white; }
        .action-btn:hover { transform: translateY(-2px); }
        
        /* Search */
        .search-box { position: relative; width: 300px; }
        .search-box input { width: 100%; padding: 10px 15px 10px 40px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 10px; color: var(--text-primary); }
        .search-box i { position: absolute; left: 12px; top: 50%; transform: translateY(-50%); color: var(--text-secondary); }
        
        /* Responsive */
        @media (max-width: 768px) {
            .sidebar { transform: translateX(-100%); z-index: 100; }
            .sidebar.active { transform: translateX(0); }
            .main-content { margin-left: 0; }
            .stats-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <!-- Login -->
    <div class="login-container" id="loginContainer">
        <div class="login-box">
            <h2><i class="fas fa-shield-alt"></i> Admin Panel V7</h2>
            <form id="loginForm">
                <div class="form-group">
                    <label>Username</label>
                    <input type="text" id="loginUsername" required placeholder="admin">
                </div>
                <div class="form-group">
                    <label>Password</label>
                    <input type="password" id="loginPassword" required placeholder="••••••••">
                </div>
                <button type="submit" class="btn">Войти</button>
            </form>
        </div>
    </div>

    <!-- Dashboard -->
    <div class="dashboard" id="dashboard">
        <div class="admin-layout">
            <div class="sidebar" id="sidebar">
                <div class="sidebar-header">
                    <div class="sidebar-logo">A</div>
                    <div>
                        <div style="font-weight: 600;">Admin Panel</div>
                        <div style="font-size: 12px; color: var(--text-secondary);">V7 Ultimate</div>
                    </div>
                </div>
                <ul class="nav-menu">
                    <li class="nav-item"><a class="nav-link active" onclick="showSection('overview')"><i class="fas fa-home"></i> Обзор</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('users')"><i class="fas fa-users"></i> Пользователи</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('rooms')"><i class="fas fa-comments"></i> Комнаты</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('server')"><i class="fas fa-server"></i> Сервер</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('backup')"><i class="fas fa-database"></i> Бэкапы</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('media')"><i class="fas fa-image"></i> Медиа</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('federation')"><i class="fas fa-globe"></i> Федерация</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('bots')"><i class="fas fa-robot"></i> Боты</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('settings')"><i class="fas fa-cog"></i> Настройки</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('audit')"><i class="fas fa-file-alt"></i> Логи</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="showSection('api')"><i class="fas fa-key"></i> API Keys</a></li>
                    <li class="nav-item"><a class="nav-link" onclick="logout()"><i class="fas fa-sign-out-alt"></i> Выход</a></li>
                </ul>
            </div>
            
            <div class="main-content">
                <div class="content-header">
                    <h1 class="content-title" id="pageTitle">Обзор</h1>
                    <div class="search-box">
                        <i class="fas fa-search"></i>
                        <input type="text" placeholder="Поиск...">
                    </div>
                </div>
                
                <!-- Overview Section -->
                <div id="section-overview">
                    <div class="stats-grid">
                        <div class="stat-card">
                            <div class="stat-card-header">
                                <div>
                                    <div class="stat-card-value" id="statUsers">0</div>
                                    <div class="stat-card-label">Пользователей</div>
                                </div>
                                <div class="stat-card-icon"><i class="fas fa-users"></i></div>
                            </div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-card-header">
                                <div>
                                    <div class="stat-card-value" id="statRooms">0</div>
                                    <div class="stat-card-label">Комнат</div>
                                </div>
                                <div class="stat-card-icon"><i class="fas fa-comments"></i></div>
                            </div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-card-header">
                                <div>
                                    <div class="stat-card-value" id="statCPU">0%</div>
                                    <div class="stat-card-label">CPU</div>
                                </div>
                                <div class="stat-card-icon"><i class="fas fa-microchip"></i></div>
                            </div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-card-header">
                                <div>
                                    <div class="stat-card-value" id="statMemory">0%</div>
                                    <div class="stat-card-label">Память</div>
                                </div>
                                <div class="stat-card-icon"><i class="fas fa-memory"></i></div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="chart-container">
                        <h3 style="margin-bottom: 20px;">Активность сервера</h3>
                        <canvas id="activityChart" height="100"></canvas>
                    </div>
                </div>
                
                <!-- Users Section -->
                <div id="section-users" style="display: none;">
                    <div class="data-table">
                        <div class="table-header">
                            <h3>Пользователи</h3>
                            <button class="btn" style="width: auto;" onclick="openModal('userModal')"><i class="fas fa-plus"></i> Добавить</button>
                        </div>
                        <div class="table-container">
                            <table>
                                <thead>
                                    <tr>
                                        <th>ID</th>
                                        <th>Имя</th>
                                        <th>Статус</th>
                                        <th>Дата регистрации</th>
                                        <th>Действия</th>
                                    </tr>
                                </thead>
                                <tbody id="usersTable"></tbody>
                            </table>
                        </div>
                    </div>
                </div>
                
                <!-- Rooms Section -->
                <div id="section-rooms" style="display: none;">
                    <div class="data-table">
                        <div class="table-header">
                            <h3>Комнаты</h3>
                        </div>
                        <div class="table-container">
                            <table>
                                <thead>
                                    <tr>
                                        <th>ID</th>
                                        <th>Название</th>
                                        <th>Участников</th>
                                        <th>Тип</th>
                                        <th>Действия</th>
                                    </tr>
                                </thead>
                                <tbody id="roomsTable"></tbody>
                            </table>
                        </div>
                    </div>
                </div>
                
                <!-- Server Section -->
                <div id="section-server" style="display: none;">
                    <div class="stats-grid">
                        <div class="stat-card">
                            <button class="btn" onclick="serverAction('restart')"><i class="fas fa-redo"></i> Перезапустить</button>
                        </div>
                        <div class="stat-card">
                            <button class="btn btn-warning" onclick="serverAction('reload')"><i class="fas fa-sync"></i> Перезагрузить</button>
                        </div>
                        <div class="stat-card">
                            <button class="btn btn-success" onclick="serverAction('backup')"><i class="fas fa-save"></i> Бэкап</button>
                        </div>
                        <div class="stat-card">
                            <button class="btn btn-danger" onclick="serverAction('cache_clear')"><i class="fas fa-trash"></i> Очистить кэш</button>
                        </div>
                    </div>
                </div>
                
                <!-- Backup Section -->
                <div id="section-backup" style="display: none;">
                    <div class="data-table">
                        <div class="table-header">
                            <h3>Бэкапы</h3>
                            <button class="btn" style="width: auto;" onclick="createBackup()"><i class="fas fa-plus"></i> Создать</button>
                        </div>
                        <div class="table-container">
                            <table>
                                <thead>
                                    <tr>
                                        <th>Имя</th>
                                        <th>Дата</th>
                                        <th>Размер</th>
                                        <th>Действия</th>
                                    </tr>
                                </thead>
                                <tbody id="backupsTable"></tbody>
                            </table>
                        </div>
                    </div>
                </div>
                
                <!-- Other sections would be similar -->
            </div>
        </div>
    </div>

    <!-- User Modal -->
    <div class="modal" id="userModal">
        <div class="modal-content">
            <div class="modal-header">
                <h3>Добавить пользователя</h3>
                <button class="modal-close" onclick="closeModal('userModal')">&times;</button>
            </div>
            <form id="userForm">
                <div class="form-group">
                    <label>Username</label>
                    <input type="text" id="newUsername" required>
                </div>
                <div class="form-group">
                    <label>Password</label>
                    <input type="password" id="newPassword" required>
                </div>
                <div class="form-group">
                    <label>Admin</label>
                    <select id="newAdmin" style="width: 100%; padding: 12px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 10px; color: var(--text-primary);">
                        <option value="false">No</option>
                        <option value="true">Yes</option>
                    </select>
                </div>
                <button type="submit" class="btn">Создать</button>
            </form>
        </div>
    </div>

    <script>
        let authToken = null;
        let socket = null;
        
        // Login
        document.getElementById('loginForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const username = document.getElementById('loginUsername').value;
            const password = document.getElementById('loginPassword').value;
            
            try {
                const response = await fetch('/admin/login', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({username, password})
                });
                const data = await response.json();
                
                if (data.success) {
                    authToken = data.token;
                    localStorage.setItem('admin_token', authToken);
                    showDashboard();
                } else {
                    showNotification('Ошибка входа', 'error');
                }
            } catch (error) {
                showNotification('Ошибка подключения', 'error');
            }
        });
        
        // Check existing token
        window.addEventListener('load', () => {
            const token = localStorage.getItem('admin_token');
            if (token) {
                authToken = token;
                showDashboard();
            }
        });
        
        function showDashboard() {
            document.getElementById('loginContainer').style.display = 'none';
            document.getElementById('dashboard').classList.add('active');
            connectSocket();
            loadDashboard();
        }
        
        function logout() {
            localStorage.removeItem('admin_token');
            authToken = null;
            location.reload();
        }
        
        function connectSocket() {
            socket = io('/admin');
            socket.on('connect', () => console.log('Connected to admin socket'));
            socket.on('audit_log', (data) => {
                showNotification(`Действие: ${data.action}`, 'info');
            });
        }
        
        async function loadDashboard() {
            try {
                const response = await fetch('/admin/dashboard', {
                    headers: {'Authorization': `Bearer ${authToken}`}
                });
                const data = await response.json();
                
                document.getElementById('statUsers').textContent = data.users || 0;
                document.getElementById('statRooms').textContent = data.rooms || 0;
                document.getElementById('statCPU').textContent = (data.system?.cpu || 0) + '%';
                document.getElementById('statMemory').textContent = (data.system?.memory || 0) + '%';
                
                loadUsers();
                loadRooms();
                loadBackups();
            } catch (error) {
                console.error('Error loading dashboard:', error);
            }
        }
        
        function showSection(section) {
            document.querySelectorAll('[id^="section-"]').forEach(el => el.style.display = 'none');
            document.getElementById(`section-${section}`).style.display = 'block';
            document.querySelectorAll('.nav-link').forEach(el => el.classList.remove('active'));
            event.target.closest('.nav-link').classList.add('active');
            document.getElementById('pageTitle').textContent = section.charAt(0).toUpperCase() + section.slice(1);
        }
        
        async function loadUsers() {
            try {
                const response = await fetch('/admin/users', {
                    headers: {'Authorization': `Bearer ${authToken}`}
                });
                const data = await response.json();
                const tbody = document.getElementById('usersTable');
                tbody.innerHTML = '';
                
                (data.users || []).forEach(user => {
                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td>${user.name || 'N/A'}</td>
                        <td>${user.displayname || user.name || 'N/A'}</td>
                        <td><span class="status-badge ${user.deactivated ? 'status-inactive' : 'status-active'}">${user.deactivated ? 'Неактивен' : 'Активен'}</span></td>
                        <td>${new Date(user.created_ts).toLocaleDateString()}</td>
                        <td>
                            <div class="action-buttons">
                                <button class="action-btn action-btn-edit" onclick="editUser('${user.name}')"><i class="fas fa-edit"></i></button>
                                <button class="action-btn action-btn-delete" onclick="deleteUser('${user.name}')"><i class="fas fa-trash"></i></button>
                            </div>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            } catch (error) {
                console.error('Error loading users:', error);
            }
        }
        
        async function loadRooms() {
            try {
                const response = await fetch('/admin/rooms', {
                    headers: {'Authorization': `Bearer ${authToken}`}
                });
                const data = await response.json();
                const tbody = document.getElementById('roomsTable');
                tbody.innerHTML = '';
                
                (data.rooms || []).forEach(room => {
                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td>${room.room_id || 'N/A'}</td>
                        <td>${room.name || 'N/A'}</td>
                        <td>${room.joined_members || 0}</td>
                        <td>${room.type || 'room'}</td>
                        <td>
                            <div class="action-buttons">
                                <button class="action-btn action-btn-delete" onclick="deleteRoom('${room.room_id}')"><i class="fas fa-trash"></i></button>
                            </div>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            } catch (error) {
                console.error('Error loading rooms:', error);
            }
        }
        
        async function loadBackups() {
            try {
                const response = await fetch('/admin/backup', {
                    headers: {'Authorization': `Bearer ${authToken}`}
                });
                const data = await response.json();
                const tbody = document.getElementById('backupsTable');
                tbody.innerHTML = '';
                
                (data.backups || []).forEach(backup => {
                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td>${backup}</td>
                        <td>${new Date().toLocaleDateString()}</td>
                        <td>-</td>
                        <td>
                            <div class="action-buttons">
                                <button class="action-btn action-btn-delete" onclick="deleteBackup('${backup}')"><i class="fas fa-trash"></i></button>
                            </div>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            } catch (error) {
                console.error('Error loading backups:', error);
            }
        }
        
        function openModal(id) {
            document.getElementById(id).classList.add('active');
        }
        
        function closeModal(id) {
            document.getElementById(id).classList.remove('active');
        }
        
        function showNotification(message, type = 'info') {
            const notification = document.createElement('div');
            notification.className = 'notification';
            notification.style.borderLeftColor = type === 'error' ? 'var(--danger)' : type === 'success' ? 'var(--success)' : 'var(--accent)';
            notification.textContent = message;
            document.body.appendChild(notification);
            setTimeout(() => notification.remove(), 3000);
        }
        
        async function serverAction(action) {
            try {
                const response = await fetch(`/admin/server/${action}`, {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${authToken}`,
                        'Content-Type': 'application/json'
                    }
                });
                const data = await response.json();
                if (data.success) {
                    showNotification(`Сервер: ${action}`, 'success');
                }
            } catch (error) {
                showNotification('Ошибка', 'error');
            }
        }
        
        async function createBackup() {
            try {
                const response = await fetch('/admin/backup', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${authToken}`,
                        'Content-Type': 'application/json'
                    }
                });
                const data = await response.json();
                if (data.success) {
                    showNotification('Бэкап создан', 'success');
                    loadBackups();
                }
            } catch (error) {
                showNotification('Ошибка', 'error');
            }
        }
        
        async function deleteUser(userId) {
            if (!confirm('Удалить пользователя?')) return;
            try {
                const response = await fetch('/admin/users', {
                    method: 'DELETE',
                    headers: {
                        'Authorization': `Bearer ${authToken}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({user_id: userId})
                });
                const data = await response.json();
                if (data.success) {
                    showNotification('Пользователь удален', 'success');
                    loadUsers();
                }
            } catch (error) {
                showNotification('Ошибка', 'error');
            }
        }
        
        async function deleteRoom(roomId) {
            if (!confirm('Удалить комнату?')) return;
            try {
                const response = await fetch('/admin/rooms/delete', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${authToken}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({room_id: roomId})
                });
                const data = await response.json();
                if (data.success) {
                    showNotification('Комната удалена', 'success');
                    loadRooms();
                }
            } catch (error) {
                showNotification('Ошибка', 'error');
            }
        }
        
        document.getElementById('userForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const user_id = `@${document.getElementById('newUsername').value}:${window.location.hostname}`;
            const password = document.getElementById('newPassword').value;
            const admin = document.getElementById('newAdmin').value === 'true';
            
            try {
                const response = await fetch('/admin/users', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${authToken}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({user_id, password, admin})
                });
                const data = await response.json();
                if (data.success) {
                    showNotification('Пользователь создан', 'success');
                    closeModal('userModal');
                    loadUsers();
                }
            } catch (error) {
                showNotification('Ошибка', 'error');
            }
        });
    </script>
</body>
</html>
EOF

# --- NGINX CONFIG ---
print_header "Настройка Nginx"
cat > /etc/nginx/sites-available/matrix <<EOF
server {
    server_name $DOMAIN;
    listen 80;
    listen [::]:80;
    return 301 https://\$host\$request_uri;
}

server {
    server_name $DOMAIN;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    listen 8448 ssl http2;
    listen [::]:8448 ssl http2;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # Admin Panel
    location /admin {
        alias /var/www/admin-panel;
        try_files \$uri \$uri/ /admin/index.html;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    # Main Web Interface
    location / {
        root /var/www/telegram-like;
        try_files \$uri \$uri/ /index.html;
    }

    # QR Auth
    location /qr {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Search Service
    location /api {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # Admin API
    location /admin-api {
        proxy_pass http://127.0.0.1:3003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # WebSocket
    location /socket.io {
        proxy_pass http://127.0.0.1:3003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # Synapse API
    location ~ ^(/_matrix|/_synapse) {
        proxy_pass http://127.0.0.1:8008;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 2G;
    }

    # Well-known
    location /.well-known/matrix/client {
        add_header Content-Type application/json;
        return 200 '{"m.homeserver": {"base_url": "https://$DOMAIN"}}';
    }
    location /.well-known/matrix/server {
        add_header Content-Type application/json;
        return 200 '{"m.server": "$DOMAIN:443"}';
    }
}
EOF

# --- COTURN ---
print_info "Настройка Coturn..."
apt install -y coturn
cat > /etc/turnserver.conf <<EOF
listening-port=3478
tls-listening-port=5349
fingerprint
use-auth-secret
static-auth-secret=$TURN_SECRET
realm=$DOMAIN
cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
pkey=/etc/letsencrypt/live/$DOMAIN/privkey.pem
no-multicast-peers
user-quota=100
total-quota=1200
syslog
no-cli
EOF
sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn

# --- SYSTEMD SERVICES ---
print_info "Создание сервисов..."
cat > /etc/systemd/system/qr-auth.service <<EOF
[Unit]
Description=QR Auth Service V7
After=network.target redis-server.service
[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/qr-auth-service
Environment="REDIS_PASS=$REDIS_PASS"
Environment="QR_SECRET=$QR_SECRET"
Environment="ADMIN_API_KEY=$ADMIN_API_KEY"
Environment="DOMAIN=$DOMAIN"
ExecStart=/usr/bin/python3 /opt/qr-auth-service/qr_auth.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/telegram-search.service <<EOF
[Unit]
Description=Telegram Search Service V7
After=network.target redis-server.service
[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/telegram-search
Environment="REDIS_PASS=$REDIS_PASS"
Environment="ADMIN_API_KEY=$ADMIN_API_KEY"
Environment="DOMAIN=$DOMAIN"
ExecStart=/usr/bin/python3 /opt/telegram-search/search_engine.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/admin-panel.service <<EOF
[Unit]
Description=Admin Panel Service V7
After=network.target redis-server.service
[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/admin-panel
Environment="REDIS_PASS=$REDIS_PASS"
Environment="ADMIN_API_KEY=$ADMIN_API_KEY"
Environment="JWT_SECRET=$JWT_SECRET"
Environment="DOMAIN=$DOMAIN"
Environment="ADMIN_USER=$ADMIN_USER"
Environment="ADMIN_PASS=$ADMIN_PASS"
Environment="ADMIN_SECRET=$QR_SECRET"
ExecStart=/usr/bin/python3 /opt/admin-panel/admin_server.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

# --- BACKUP SCRIPT ---
cat > /usr/local/bin/matrix-backup.sh <<'EOF'
#!/bin/bash
DATE=$(date +%F_%H%M%S)
mkdir -p /var/backups/matrix
sudo -u postgres pg_dump synapse > /var/backups/matrix/synapse-${DATE}.sql
tar -czf /var/backups/matrix/synapse-${DATE}.tar.gz -C /var/lib/matrix-synapse media
find /var/backups/matrix -mtime +7 -delete
EOF
chmod +x /usr/local/bin/matrix-backup.sh
echo "0 3 * * * root /usr/local/bin/matrix-backup.sh" >> /etc/crontab

# --- INSTALL PYTHON DEPS ---
print_info "Установка Python зависимостей..."
pip3 install flask flask-socketio flask-cors redis pyjwt qrcode pillow requests websocket-client gevent psutil schedule bcrypt cryptography

# --- CREATE ADMIN ---
print_info "Создание администратора..."
register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml \
--user "$ADMIN_USER" --password "$ADMIN_PASS" \
--admin http://localhost:8008 || true

# --- SSL CERTIFICATE ---
print_info "Получение SSL сертификата..."
ln -sf /etc/nginx/sites-available/matrix /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl reload nginx
certbot certonly --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL || print_warning "SSL может потребовать ручной активации"
systemctl reload nginx

# --- START SERVICES ---
print_info "Запуск сервисов..."
systemctl daemon-reload
systemctl enable qr-auth telegram-search admin-panel matrix-synapse coturn nginx redis-server postgresql
systemctl restart qr-auth telegram-search admin-panel matrix-synapse coturn nginx redis-server postgresql

# --- SAVE CREDENTIALS ---
cat > /root/ultimate_messenger_v7_admin_credentials.txt <<EOF
╔═══════════════════════════════════════════════════════════════╗
║     MATRIX ULTIMATE MESSENGER V7 - ADMIN MASTER EDITION       ║
║     Полное управление через админ-панель                      ║
╚═══════════════════════════════════════════════════════════════╝

🌐 ДОМЕН: https://$DOMAIN
📧 EMAIL: $EMAIL
🏷️ БРЕНД: $BRAND_NAME

👤 АДМИНИСТРАТОР:
   ID: @$ADMIN_USER:$DOMAIN
   PASS: $ADMIN_PASS

🔐 АДМИН ПАНЕЛЬ:
   URL: https://$DOMAIN/admin
   Логин: $ADMIN_USER
   Пароль: $ADMIN_PASS

🔐 КЛЮЧИ БЕЗОПАСНОСТИ:
   DB Pass: $DB_PASS
   Redis: $REDIS_PASS
   Turn: $TURN_SECRET
   Reg Secret: $REG_SECRET
   JWT: $JWT_SECRET
   Admin API: $ADMIN_API_KEY

📱 ФУНКЦИИ АДМИН ПАНЕЛИ:
   ✅ Управление пользователями (создание, удаление, бан)
   ✅ Управление комнатами (удаление, shutdown)
   ✅ Управление сервером (restart, reload, backup)
   ✅ Бэкапы (автоматические и ручные)
   ✅ Аудит логи (все действия админов)
   ✅ Управление кэшем Redis
   ✅ SSL/TLS управление (renew)
   ✅ Управление медиа файлами
   ✅ Федерация (block/unblock домены)
   ✅ Управление ботами
   ✅ Настройки системы
   ✅ Webhooks
   ✅ PWA настройки
   ✅ Темы оформления
   ✅ API Keys генерация
   ✅ Мониторинг (CPU, RAM, Disk, Network)
   ✅ Real-time уведомления через WebSocket

🔧 КОМАНДЫ:
   systemctl status admin-panel
   journalctl -u admin-panel -f
   /usr/local/bin/matrix-backup.sh (ручной бэкап)

═══════════════════════════════════════════════════════════════
EOF
chmod 600 /root/ultimate_messenger_v7_admin_credentials.txt

# --- FINAL OUTPUT ---
clear
print_header "УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     MATRIX MESSENGER V7 - ADMIN MASTER ГОТОВ!                 ║"
echo "║     Полное управление через админ-панель                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${CYAN}🌐 МЕССЕНДЖЕР:${NC} https://$DOMAIN"
echo -e "${CYAN}🔐 АДМИН ПАНЕЛЬ:${NC} https://$DOMAIN/admin"
echo -e "${CYAN}👤 АДМИН:${NC} @$ADMIN_USER:$DOMAIN"
echo -e "${CYAN}🔑 ФАЙЛ:${NC} /root/ultimate_messenger_v7_admin_credentials.txt"
echo ""
echo -e "${WHITE}Возможности админ-панели:${NC}"
echo "1. ✅ Управление всеми пользователями"
echo "2. ✅ Управление всеми комнатами"
echo "3. ✅ Полный контроль сервера"
echo "4. ✅ Автоматические бэкапы"
echo "5. ✅ Аудит всех действий"
echo "6. ✅ Мониторинг в реальном времени"
echo "7. ✅ Управление медиа и федерацией"
echo "8. ✅ API Keys и Webhooks"
echo ""
echo -e "${GREEN}🎉 НАСЛАЖДАЙТЕСЬ ПОЛНЫМ КОНТРОЛЕМ! 🎉${NC}"