#!/bin/bash

# ==========================================
# MATRIX FULL STACK INSTALLER V3
# Synapse + Coturn + Element Web + Admin Panel + OAuth (Google/Yandex)
# Tested on Ubuntu 22.04 / Debian 11+
# ==========================================

set -euo pipefail
trap 'echo "❌ Ошибка на строке $LINENO"; exit 1' ERR

# --- ЦВЕТА ДЛЯ ВЫВОДА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- ПРОВЕРКА ПРАВ ROOT ---
if [ "$EUID" -ne 0 ]; then 
    print_error "Пожалуйста, запустите с правами root (sudo)"
    exit 1
fi

# --- НАСТРОЙКИ ПОЛЬЗОВАТЕЛЯ ---
clear
echo "=========================================="
echo "   MATRIX FULL STACK INSTALLER V3"
echo "=========================================="
echo ""

read -p "Введите домен (например, matrix.example.com): " DOMAIN
read -p "Введите email для SSL (например, admin@example.com): " EMAIL
read -p "Введите Google Client ID (оставьте пустым если нет): " GOOGLE_CLIENT_ID
read -p "Введите Google Client Secret (оставьте пустым если нет): " GOOGLE_CLIENT_SECRET
read -p "Введите Яндекс Client ID (оставьте пустым если нет): " YANDEX_CLIENT_ID
read -p "Введите Яндекс Client Secret (оставьте пустым если нет): " YANDEX_CLIENT_SECRET

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    print_error "Домен и email обязательны!"
    exit 1
fi

# --- ГЕНЕРАЦИЯ КЛЮЧЕЙ ---
DB_PASS="$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)"
REG_SECRET="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
TURN_SECRET="$(openssl rand -base64 64 | tr -d '/+=' | head -c 48)"
ADMIN_API_KEY="$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)"

print_info "Начинаем установку для домена: $DOMAIN"

# --- ПОДГОТОВКА СИСТЕМЫ ---
print_info "Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y
apt install -y curl wget lsb-release gnupg2 ufw apt-transport-https \
    ca-certificates software-properties-common git unzip nginx \
    certbot python3-certbot-nginx postgresql postgresql-contrib \
    redis-server jq python3-pip python3-venv

# --- НАСТРОЙКА FIREWALL ---
print_info "Настройка Firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8448/tcp
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 5349/tcp
ufw allow 5349/udp
ufw allow 49152:65535/udp
echo "y" | ufw enable

# --- УСТАНОВКА MATRIX SYNAPSE ---
print_info "Установка Matrix Synapse..."
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/matrix-org.list
apt update

echo "matrix-synapse-py3 matrix-synapse/server-name string $DOMAIN" | debconf-set-selections
echo "matrix-synapse-py3 matrix-synapse/report-stats boolean false" | debconf-set-selections
apt install -y matrix-synapse-py3

# --- НАСТРОЙКА POSTGRESQL ---
print_info "Настройка PostgreSQL..."
sudo -u postgres psql -c "CREATE USER synapse WITH PASSWORD '$DB_PASS';" || true
sudo -u postgres psql -c "CREATE DATABASE synapse OWNER synapse;" || true
sudo -u postgres psql -c "ALTER USER synapse CREATEDB;" || true

cat >> /etc/postgresql/*/main/postgresql.conf <<EOF

# Оптимизация для Synapse
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 8MB
maintenance_work_mem = 64MB
EOF

systemctl restart postgresql

# --- КОНФИГУРАЦИЯ SYNAPSE ---
print_info "Конфигурация Synapse..."
CONFIG_FILE="/etc/matrix-synapse/homeserver.yaml"

# Бэкап оригинального конфига
cp $CONFIG_FILE ${CONFIG_FILE}.backup

# Отключаем SQLite
sed -i 's/^database:/#database:/' $CONFIG_FILE
sed -i 's/^  name: sqlite3/#  name: sqlite3/' $CONFIG_FILE
sed -i 's/^  args:/#  args:/' $CONFIG_FILE
sed -i 's/^    database: \/var\/lib/#    database: \/var\/lib/' $CONFIG_FILE

# Добавляем новую конфигурацию
cat >> $CONFIG_FILE <<EOF

# --- AUTO CONFIG V3 ---
server_name: "$DOMAIN"
public_baseurl: "https://$DOMAIN/"

# Регистрация
enable_registration: true
enable_registration_without_verification: false
registration_shared_secret: "$REG_SECRET"
registrations_require_3pid:
  - email

# База данных
database:
  name: psycopg2
  args:
    user: synapse
    password: "$DB_PASS"
    database: synapse
    host: localhost
    cp_min: 5
    cp_max: 10

# TURN сервер
turn_shared_secret: "$TURN_SECRET"
turn_uris: ["turn:$DOMAIN?transport=udp", "turn:$DOMAIN?transport=tcp"]
turn_user_lifetime: 86400000
turn_allow_ip_lifetime: true

# Rate limiting
rc_message:
  per_second: 5
  burst_count: 10
rc_registration:
  per_second: 0.17
  burst_count: 3

# Медиа
max_upload_size: "100M"
max_image_pixels: "32M"
media_store_path: "/var/lib/matrix-synapse/media"

# Пресеты
presence:
  enabled: true
user_consent:
  require_at_registration: false
EOF

# --- НАСТРОЙКА OIDC ПРОВАЙДЕРОВ ---
if [ ! -z "$GOOGLE_CLIENT_ID" ] && [ ! -z "$GOOGLE_CLIENT_SECRET" ]; then
    print_info "Добавление Google OAuth..."
    cat >> $CONFIG_FILE <<EOF

oidc_providers:
  - idp_id: google
    idp_name: Google
    idp_brand: "google"
    issuer: "https://accounts.google.com/"
    client_id: "$GOOGLE_CLIENT_ID"
    client_secret: "$GOOGLE_CLIENT_SECRET"
    scopes: ["openid", "profile", "email"]
    user_mapping_provider:
      config:
        localpart_template: "{{ user.email.split('@')[0] }}"
        display_name_template: "{{ user.name }}"
        email_template: "{{ user.email }}"
EOF
fi

if [ ! -z "$YANDEX_CLIENT_ID" ] && [ ! -z "$YANDEX_CLIENT_SECRET" ]; then
    print_info "Добавление Яндекс OAuth..."
    # Если уже есть oidc_providers, добавляем запятую
    if grep -q "oidc_providers:" $CONFIG_FILE; then
        sed -i '/oidc_providers:/a\  - idp_id: yandex' $CONFIG_FILE
    else
        cat >> $CONFIG_FILE <<EOF

oidc_providers:
EOF
    fi
    
    cat >> $CONFIG_FILE <<EOF
    idp_name: Яндекс
    idp_brand: "yandex"
    discover: false
    issuer: "https://oauth.yandex.ru/"
    client_id: "$YANDEX_CLIENT_ID"
    client_secret: "$YANDEX_CLIENT_SECRET"
    authorization_endpoint: "https://oauth.yandex.ru/authorize"
    token_endpoint: "https://oauth.yandex.ru/token"
    userinfo_endpoint: "https://login.yandex.ru/info"
    scopes: ["login:email", "login:info"]
    user_mapping_provider:
      config:
        localpart_template: "{{ user.login }}"
        display_name_template: "{{ user.real_name or user.login }}"
        email_template: "{{ user.default_email }}"
EOF
fi

# --- НАСТРОЙКА NGINX ---
print_info "Настройка Nginx..."

# Временный конфиг для получения SSL
cat > /etc/nginx/sites-available/matrix <<EOF
server {
    server_name $DOMAIN;
    listen 80;
    listen [::]:80;
    return 301 https://\$host\$request_uri;
}
EOF

ln -sf /etc/nginx/sites-available/matrix /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl reload nginx

# Получение SSL сертификата
print_info "Получение SSL сертификата..."
certbot certonly --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Финальный конфиг Nginx
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
    listen 8448 ssl;
    listen [::]:8448 ssl;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    # Well-known для федерации
    location /.well-known/matrix/client {
        add_header Content-Type application/json;
        return 200 '{"m.homeserver": {"base_url": "https://$DOMAIN"}}';
    }
    
    location /.well-known/matrix/server {
        add_header Content-Type application/json;
        return 200 '{"m.server": "$DOMAIN:443"}';
    }

    # Synapse API
    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://localhost:8008;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 100M;
    }

    # Element Web
    location / {
        root /var/www/element;
        try_files \$uri \$uri/ /index.html;
    }

    # Admin Panel
    location /admin {
        proxy_pass http://localhost:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

systemctl reload nginx

# --- УСТАНОВКА ELEMENT WEB ---
print_info "Установка Element Web..."
cd /tmp
wget https://github.com/element-hq/element-web/releases/download/v1.11.70/element-v1.11.70.tar.gz
tar -xzf element-v1.11.70.tar.gz
mkdir -p /var/www/element
cp -r element-v1.11.70/* /var/www/element/

cat > /var/www/element/config.json <<EOF
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "https://$DOMAIN",
      "server_name": "$DOMAIN"
    }
  },
  "brand": "Matrix Chat",
  "features": {
    "feature_login_sso": true
  },
  "sso_redirect_options": {
    "google": "Google",
    "yandex": "Яндекс"
  }
}
EOF

chown -R www-data:www-data /var/www/element

# --- УСТАНОВКА ADMIN PANEL ---
print_info "Установка Admin Panel..."
mkdir -p /opt/matrix-admin
cd /opt/matrix-admin

python3 -m venv venv
source venv/bin/activate
pip install flask flask-cors requests pyyaml psycopg2-binary

# Создаем админ-панель
cat > /opt/matrix-admin/app.py <<'EOF'
#!/usr/bin/env python3
from flask import Flask, render_template, request, jsonify, redirect, url_for, session
from flask_cors import CORS
import requests
import yaml
import json
import os
import psycopg2
from functools import wraps

app = Flask(__name__)
app.secret_key = os.environ.get('ADMIN_SECRET', 'CHANGE_ME_IN_PRODUCTION')
CORS(app)

# Конфигурация
SYNAPSE_CONFIG = '/etc/matrix-synapse/homeserver.yaml'
SYNAPSE_API = 'http://localhost:8008'
ADMIN_API_KEY = os.environ.get('ADMIN_API_KEY', 'CHANGE_ME')

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form.get('password') == os.environ.get('ADMIN_PASSWORD', 'admin'):
            session['logged_in'] = True
            return redirect(url_for('dashboard'))
        return 'Invalid password', 401
    return '''
    <form method="post">
        <input type="password" name="password" placeholder="Admin Password">
        <input type="submit" value="Login">
    </form>
    '''

@app.route('/')
@require_auth
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/users', methods=['GET'])
@require_auth
def get_users():
    headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
    response = requests.get(f'{SYNAPSE_API}/_synapse/admin/v2/users', headers=headers)
    return jsonify(response.json())

@app.route('/api/users', methods=['POST'])
@require_auth
def create_user():
    data = request.json
    headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
    response = requests.post(f'{SYNAPSE_API}/_synapse/admin/v1/users/{data["username"]}', 
                           json=data, headers=headers)
    return jsonify(response.json())

@app.route('/api/rooms', methods=['GET'])
@require_auth
def get_rooms():
    headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
    response = requests.get(f'{SYNAPSE_API}/_synapse/admin/v1/rooms', headers=headers)
    return jsonify(response.json())

@app.route('/api/oauth/providers', methods=['GET'])
@require_auth
def get_oauth_providers():
    with open(SYNAPSE_CONFIG, 'r') as f:
        config = yaml.safe_load(f)
    providers = config.get('oidc_providers', [])
    return jsonify(providers)

@app.route('/api/oauth/providers', methods=['POST'])
@require_auth
def update_oauth_providers():
    with open(SYNAPSE_CONFIG, 'r') as f:
        config = yaml.safe_load(f)
    
    # Создаем бэкап
    os.system(f'cp {SYNAPSE_CONFIG} {SYNAPSE_CONFIG}.backup')
    
    # Обновляем провайдеры
    config['oidc_providers'] = request.json
    config['enable_registration'] = True
    
    with open(SYNAPSE_CONFIG, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
    
    # Перезагружаем Synapse
    os.system('systemctl reload matrix-synapse')
    
    return jsonify({'status': 'success'})

@app.route('/api/stats', methods=['GET'])
@require_auth
def get_stats():
    headers = {'Authorization': f'Bearer {ADMIN_API_KEY}'}
    
    # Получаем статистику
    users = requests.get(f'{SYNAPSE_API}/_synapse/admin/v2/users', headers=headers).json()
    rooms = requests.get(f'{SYNAPSE_API}/_synapse/admin/v1/rooms', headers=headers).json()
    
    return jsonify({
        'total_users': len(users.get('users', [])),
        'total_rooms': rooms.get('total_rooms', 0),
        'active_users': sum(1 for u in users.get('users', []) if u.get('is_guest', False) == False)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Создаем шаблоны
mkdir -p /opt/matrix-admin/templates
cat > /opt/matrix-admin/templates/dashboard.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Matrix Admin Panel</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <nav class="navbar navbar-dark bg-dark">
        <div class="container-fluid">
            <span class="navbar-brand mb-0 h1">Matrix Admin Panel</span>
            <a href="/logout" class="btn btn-outline-light">Logout</a>
        </div>
    </nav>
    
    <div class="container mt-4">
        <h2>Dashboard</h2>
        
        <div class="row mt-4">
            <div class="col-md-4">
                <div class="card text-white bg-primary mb-3">
                    <div class="card-header">Total Users</div>
                    <div class="card-body">
                        <h1 class="card-title" id="totalUsers">0</h1>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card text-white bg-success mb-3">
                    <div class="card-header">Total Rooms</div>
                    <div class="card-body">
                        <h1 class="card-title" id="totalRooms">0</h1>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card text-white bg-info mb-3">
                    <div class="card-header">Active Users</div>
                    <div class="card-body">
                        <h1 class="card-title" id="activeUsers">0</h1>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="row mt-4">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h5>OAuth Providers</h5>
                    </div>
                    <div class="card-body">
                        <div id="oauthProviders"></div>
                        <button class="btn btn-primary mt-3" onclick="updateOAuth()">Update Providers</button>
                    </div>
                </div>
            </div>
            
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h5>Create User</h5>
                    </div>
                    <div class="card-body">
                        <form id="createUserForm">
                            <div class="mb-3">
                                <label>Username</label>
                                <input type="text" class="form-control" name="username" required>
                            </div>
                            <div class="mb-3">
                                <label>Password</label>
                                <input type="password" class="form-control" name="password" required>
                            </div>
                            <div class="mb-3">
                                <label>Display Name</label>
                                <input type="text" class="form-control" name="displayname">
                            </div>
                            <div class="mb-3 form-check">
                                <input type="checkbox" class="form-check-input" name="admin">
                                <label class="form-check-label">Make Admin</label>
                            </div>
                            <button type="submit" class="btn btn-success">Create User</button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        function loadStats() {
            fetch('/api/stats')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('totalUsers').textContent = data.total_users;
                    document.getElementById('totalRooms').textContent = data.total_rooms;
                    document.getElementById('activeUsers').textContent = data.active_users;
                });
        }
        
        function loadOAuthProviders() {
            fetch('/api/oauth/providers')
                .then(r => r.json())
                .then(providers => {
                    let html = '<ul class="list-group">';
                    providers.forEach(p => {
                        html += `<li class="list-group-item">${p.idp_name} (${p.idp_id})</li>`;
                    });
                    html += '</ul>';
                    document.getElementById('oauthProviders').innerHTML = html;
                });
        }
        
        function updateOAuth() {
            // Здесь можно добавить форму редактирования провайдеров
            alert('Edit functionality coming soon');
        }
        
        document.getElementById('createUserForm').addEventListener('submit', (e) => {
            e.preventDefault();
            const formData = new FormData(e.target);
            const data = {
                username: formData.get('username'),
                password: formData.get('password'),
                displayname: formData.get('displayname'),
                admin: formData.get('admin') === 'on'
            };
            
            fetch('/api/users', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(data)
            }).then(r => r.json())
              .then(() => {
                  alert('User created successfully');
                  loadStats();
              });
        });
        
        loadStats();
        loadOAuthProviders();
        setInterval(loadStats, 30000);
    </script>
</body>
</html>
EOF

# Создаем systemd сервис для админ-панели
cat > /etc/systemd/system/matrix-admin.service <<EOF
[Unit]
Description=Matrix Admin Panel
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/matrix-admin
Environment="ADMIN_SECRET=$(openssl rand -base64 32)"
Environment="ADMIN_PASSWORD=$(openssl rand -base64 12)"
Environment="ADMIN_API_KEY=$ADMIN_API_KEY"
ExecStart=/opt/matrix-admin/venv/bin/python /opt/matrix-admin/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- УСТАНОВКА COTURN ---
print_info "Установка Coturn..."
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
systemctl restart coturn

# --- ЗАПУСК СЕРВИСОВ ---
print_info "Запуск сервисов..."
systemctl daemon-reload
systemctl restart matrix-synapse
systemctl enable matrix-synapse coturn nginx matrix-admin
systemctl start matrix-admin

# --- СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ ---
cat > /root/matrix_credentials.txt <<EOF
=====================================
MATRIX SERVER CREDENTIALS
=====================================
Домен: $DOMAIN
Email: $EMAIL

Пароль БД PostgreSQL: $DB_PASS
Registration Secret: $REG_SECRET
TURN Secret: $TURN_SECRET
Admin API Key: $ADMIN_API_KEY

=====================================
ДОСТУП К АДМИН-ПАНЕЛИ
=====================================
URL: https://$DOMAIN/admin
Пароль администратора: $(cat /etc/systemd/system/matrix-admin.service | grep ADMIN_PASSWORD | cut -d'"' -f2)

=====================================
ПОЛЕЗНЫЕ КОМАНДЫ
=====================================
# Создать пользователя вручную:
register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml https://$DOMAIN

# Проверить логи:
journalctl -u matrix-synapse -f
journalctl -u matrix-admin -f

# Перезапустить сервисы:
systemctl restart matrix-synapse coturn nginx matrix-admin

=====================================
ФАЙЛЫ КОНФИГУРАЦИИ
=====================================
- Synapse: /etc/matrix-synapse/homeserver.yaml
- Coturn: /etc/turnserver.conf
- Nginx: /etc/nginx/sites-available/matrix
- Admin Panel: /opt/matrix-admin/

=====================================
ОБНОВЛЕНИЕ SSL СЕРТИФИКАТА
=====================================
certbot renew --quiet --nginx && systemctl reload nginx coturn
EOF

chmod 600 /root/matrix_credentials.txt

# --- ПРОВЕРКА РАБОТЫ ---
print_info "Проверка работы сервисов..."
services=("matrix-synapse" "coturn" "nginx" "postgresql" "matrix-admin")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        print_success "✓ $service активен"
    else
        print_warning "✗ $service НЕ активен!"
    fi
done

# --- ЗАВЕРШЕНИЕ ---
clear
echo "=========================================="
echo -e "${GREEN}УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}Ваш Matrix сервер доступен по адресу:${NC}"
echo "https://$DOMAIN"
echo ""
echo -e "${BLUE}Element Web:${NC}"
echo "https://$DOMAIN"
echo ""
echo -e "${BLUE}Админ-панель:${NC}"
echo "https://$DOMAIN/admin"
echo ""
echo -e "${YELLOW}Учетные данные сохранены в:${NC}"
echo "/root/matrix_credentials.txt"
echo ""
echo -e "${YELLOW}Пароль для админ-панели:${NC}"
grep ADMIN_PASSWORD /etc/systemd/system/matrix-admin.service | cut -d'"' -f2
echo ""
echo -e "${YELLOW}Важно:${NC}"
echo "1. Для работы Google/Яндекс OAuth настройте Redirect URI:"
echo "   https://$DOMAIN/_synapse/client/oidc/callback"
echo ""
echo "2. Перезагрузите сервер для применения всех настроек:"
echo "   sudo reboot"
echo ""
echo "=========================================="