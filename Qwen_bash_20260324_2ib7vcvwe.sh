#!/bin/bash
# ============================================
# SAFARALI MULTI-APP BUILDER — COMPLETE INSTALLER
# Всё в одном скрипте: Сайт + Панель + API + Сборка
# ============================================

set -e

# 🎨 Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_header() { 
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD} $1 ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
    echo ""
}

# Проверка root
if [ "$EUID" -ne 0 ]; then 
    print_error "Запустите от root: sudo bash install.sh"
    exit 1
fi

# ============================================
# 📋 КОНФИГУРАЦИЯ
# ============================================
print_header "🚀 SAFARALI MULTI-APP BUILDER"

echo "📋 НАСТРОЙКА СЕРВЕРА"
echo "═══════════════════════════════════════"
echo ""

# Домен
while true; do
    read -p "🌐 Домен (например: builder.safaraligroup.uz): " BUILD_DOMAIN
    if [[ -z "$BUILD_DOMAIN" ]]; then
        print_error "Домен не может быть пустым!"
        continue
    fi
    if [[ ! "$BUILD_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
        print_error "Неверный формат домена!"
        continue
    fi
    print_success "Домен: $BUILD_DOMAIN"
    break
done

# Email
while true; do
    read -p "📧 Email для SSL: " ADMIN_EMAIL
    if [[ -z "$ADMIN_EMAIL" ]]; then
        print_error "Email не может быть пустым!"
        continue
    fi
    if [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$ ]]; then
        print_error "Неверный формат email!"
        continue
    fi
    print_success "Email: $ADMIN_EMAIL"
    break
done

# Генерация секретов
API_SECRET=$(openssl rand -hex 32)
KEYSTORE_PASS=$(openssl rand -hex 16)
BUILDER_USER="builder"
INSTALL_DIR="/opt/safarali-multi-app-builder"
WEB_DIR="/var/www/$BUILD_DOMAIN"

echo ""
print_info "Конфигурация:"
echo "   Домен: $BUILD_DOMAIN"
echo "   Email: $ADMIN_EMAIL"
echo "   API Secret: $API_SECRET"
echo "   Установка: $INSTALL_DIR"
echo ""

read -p "▶️  Начать установку? [y/N]: " -i "y" CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_error "Отменено"
    exit 1
fi

# ============================================
# 💾 ПРОВЕРКА РЕСУРСОВ
# ============================================
print_header "💾 Проверка ресурсов"

RAM=$(free -g | awk '/^Mem:/{print $2}')
DISK=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')

print_info "RAM: ${RAM} GB | Disk: ${DISK} GB"

if [ "$RAM" -lt 2 ]; then
    print_error "Минимум 2 GB RAM!"
    exit 1
fi

if [ "$DISK" -lt 10 ]; then
    print_error "Минимум 10 GB диска!"
    exit 1
fi

print_success "Ресурсы OK"

# ============================================
# 📦 ШАГ 1: СИСТЕМНЫЕ ПАКЕТЫ
# ============================================
print_header "📦 Шаг 1/8: Системные пакеты"

apt update -y
apt upgrade -y
apt install -y software-properties-common curl wget git unzip zip jq nginx \
    php8.1-fpm php8.1-cli php8.1-mbstring php8.1-xml php8.1-curl php8.1-zip php8.1-gd \
    openjdk-17-jdk certbot python3-certbot-nginx

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g cordova

print_success "Пакеты установлены"

# ============================================
# 🔐 ШАГ 2: ПОЛЬЗОВАТЕЛЬ
# ============================================
print_header "🔐 Шаг 2/8: Пользователь"

if ! id "$BUILDER_USER" &>/dev/null; then
    useradd -r -m -s /bin/bash "$BUILDER_USER"
    echo "$BUILDER_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$BUILDER_USER
    chmod 0440 /etc/sudoers.d/$BUILDER_USER
fi

print_success "Пользователь создан"

# ============================================
# 📁 ШАГ 3: СТРУКТУРА
# ============================================
print_header "📁 Шаг 3/8: Структура директорий"

mkdir -p $INSTALL_DIR/{
    website/assets,
    dashboard/api,
    templates/{online-tv,music,video,messenger,ecommerce,news,education}/{www,config},
    builder,
    config/apps,
    output,
    logs,
    keystore,
    work
}

mkdir -p $WEB_DIR/{api,downloads,logs}

chown -R root:$BUILDER_USER $INSTALL_DIR
chmod -R 755 $INSTALL_DIR
chown -R www-www-data $WEB_DIR

print_success "Структура создана"

# ============================================
# 🔑 ШАГ 4: КЛЮЧИ И КОНФИГ
# ============================================
print_header "🔑 Шаг 4/8: Ключи и конфигурация"

# Keystore
if [ ! -f "$INSTALL_DIR/keystore/release.jks" ]; then
    keytool -genkey -v \
        -keystore "$INSTALL_DIR/keystore/release.jks" \
        -alias safarali_release \
        -keyalg RSA -keysize 2048 \
        -validity 10000 \
        -storepass "$KEYSTORE_PASS" \
        -keypass "$KEYSTORE_PASS" \
        -dname "CN=Safarali Group, OU=Mobile, O=Safarali, C=UZ" 2>/dev/null
    
    cat > "$INSTALL_DIR/keystore/.credentials" << EOF
KEYSTORE_PASS=$KEYSTORE_PASS
ALIAS=safarali_release
KEYSTORE_PATH=$INSTALL_DIR/keystore/release.jks
EOF
    chmod 600 "$INSTALL_DIR/keystore/.credentials"
fi

# Settings
cat > "$INSTALL_DIR/config/settings.json" << EOF
{
  "api_secret": "$API_SECRET",
  "domain": "$BUILD_DOMAIN",
  "email": "$ADMIN_EMAIL",
  "build": {"max_concurrent": 2, "timeout_minutes": 60, "auto_sign": true},
  "app_types": {
    "online-tv": {"enabled": true, "name": "Онлайн ТВ", "icon": "📺"},
    "music": {"enabled": true, "name": "Музыка", "icon": "🎵"},
    "video": {"enabled": true, "name": "Видео", "icon": "🎬"},
    "messenger": {"enabled": true, "name": "Мессенджер", "icon": "💬"},
    "ecommerce": {"enabled": true, "name": "Магазин", "icon": "🛒"},
    "news": {"enabled": true, "name": "Новости", "icon": "📰"},
    "education": {"enabled": true, "name": "Образование", "icon": "📚"}
  }
}
EOF

print_success "Конфигурация создана"

# ============================================
# 🌐 ШАГ 5: NGINX И SSL
# ============================================
print_header "🌐 Шаг 5/8: Nginx и SSL"

cat > /etc/nginx/sites-available/$BUILD_DOMAIN << EOF
server {
    listen 80;
    server_name $BUILD_DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$server_name\$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name $BUILD_DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$BUILD_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$BUILD_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root $WEB_DIR;
    index index.html;
    client_max_body_size 100M;
    location / { try_files \$uri \$uri/ /index.html; }
    location /api/ {
        try_files \$uri \$uri/ /api/index.php?\$query_string;
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        }
    }
    location /downloads/ { alias $WEB_DIR/downloads/; autoindex on; }
    location ~ /\. { deny all; }
}
EOF

ln -sf /etc/nginx/sites-available/$BUILD_DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl enable nginx && systemctl restart nginx

mkdir -p /var/www/certbot
certbot certonly --webroot -w /var/www/certbot -d $BUILD_DOMAIN \
    --email $ADMIN_EMAIL --agree-tos --non-interactive || \
    print_info "⚠️ SSL отложен (проверьте DNS)"

systemctl restart nginx

print_success "Nginx и SSL настроены"

# ============================================
# 🛠️ ШАГ 6: API BACKEND
# ============================================
print_header "🛠️ Шаг 6/8: API Backend"

cat > "$WEB_DIR/api/index.php" << 'PHPEOF'
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-API-Secret');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$CONFIG = '/opt/safarali-multi-app-builder/config/settings.json';
$APPS_DIR = '/opt/safarali-multi-app-builder/config/apps';
$OUTPUT_DIR = '/opt/safarali-multi-app-builder/output';
$LOG_DIR = '/opt/safarali-multi-app-builder/logs';

$settings = json_decode(file_get_contents($CONFIG), true);
$api_secret = $settings['api_secret'] ?? '';
$provided = $_SERVER['HTTP_X_API_SECRET'] ?? $_GET['secret'] ?? '';

if (!hash_equals($api_secret, $provided) && $api_secret !== '') {
    http_response_code(401);
    echo json_encode(['error' => 'Unauthorized']);
    exit;
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

switch($action) {
    case 'get_app_types':
        echo json_encode(['success' => true, 'types' => $settings['app_types']]);
        break;
        
    case 'create_app':
        $input = json_decode(file_get_contents('php://input'), true);
        $app_id = 'app_' . uniqid();
        $app_config = [
            'id' => $app_id,
            'name' => $input['name'] ?? 'New App',
            'type' => $input['type'] ?? 'custom',
            'package_id' => $input['package_id'] ?? 'uz.safarali.app' . time(),
            'version' => $input['version'] ?? '1.0.0',
            'created' => date('Y-m-d H:i:s'),
            'status' => 'draft'
        ];
        file_put_contents("$APPS_DIR/{$app_id}.json", json_encode($app_config, JSON_PRETTY_PRINT));
        echo json_encode(['success' => true, 'app' => $app_config]);
        break;
        
    case 'list_apps':
        $apps = [];
        foreach(glob("$APPS_DIR/*.json") as $f) {
            $apps[] = json_decode(file_get_contents($f), true);
        }
        echo json_encode(['success' => true, 'apps' => $apps]);
        break;
        
    case 'get_app':
        $id = $_GET['id'] ?? '';
        $file = "$APPS_DIR/{$id}.json";
        if(file_exists($file)) {
            echo json_encode(['success' => true, 'app' => json_decode(file_get_contents($file), true)]);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Not found']);
        }
        break;
        
    case 'update_app':
        $id = $_GET['id'] ?? '';
        $input = json_decode(file_get_contents('php://input'), true);
        $file = "$APPS_DIR/{$id}.json";
        if(file_exists($file)) {
            $app = json_decode(file_get_contents($file), true);
            $app = array_merge($app, $input);
            file_put_contents($file, json_encode($app, JSON_PRETTY_PRINT));
            echo json_encode(['success' => true]);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Not found']);
        }
        break;
        
    case 'delete_app':
        $id = $_GET['id'] ?? '';
        $file = "$APPS_DIR/{$id}.json";
        if(file_exists($file)) {
            unlink($file);
            $apk = "$OUTPUT_DIR/{$id}.apk";
            if(file_exists($apk)) unlink($apk);
            echo json_encode(['success' => true]);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Not found']);
        }
        break;
        
    case 'build_app':
        $id = $_GET['id'] ?? '';
        $file = "$APPS_DIR/{$id}.json";
        if(file_exists($file)) {
            $app = json_decode(file_get_contents($file), true);
            $log = "$LOG_DIR/build_" . date('Ymd_His') . ".log";
            $cmd = "sudo -u builder /opt/safarali-multi-app-builder/builder/core.sh " . 
                   escapeshellarg($id) . " " . escapeshellarg($app['type']) . " > $log 2>&1 &";
            exec($cmd);
            echo json_encode(['success' => true, 'log' => basename($log)]);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Not found']);
        }
        break;
        
    case 'build_status':
        $logs = glob("$LOG_DIR/build_*.log");
        rsort($logs);
        $latest = $logs[0] ?? null;
        echo json_encode(['success' => true, 'logs' => $latest ? substr(file_get_contents($latest), -5000) : 'Нет логов']);
        break;
        
    case 'download_apk':
        $id = $_GET['id'] ?? '';
        $apk = "$OUTPUT_DIR/{$id}.apk";
        if(file_exists($apk)) {
            header('Content-Type: application/vnd.android.package-archive');
            header('Content-Disposition: attachment; filename="app.apk"');
            readfile($apk);
            exit;
        }
        http_response_code(404);
        echo json_encode(['error' => 'APK not found']);
        break;
        
    case 'get_dashboard':
        $apps = [];
        foreach(glob("$APPS_DIR/*.json") as $f) {
            $apps[] = json_decode(file_get_contents($f), true);
        }
        $stats = ['total_apps' => count($apps), 'total_builds' => 0];
        echo json_encode(['success' => true, 'stats' => $stats, 'apps' => $apps]);
        break;
        
    default:
        echo json_encode(['error' => 'Unknown action']);
}
PHPEOF

print_success "API создан"

# ============================================
# 🔨 ШАГ 7: BUILD SYSTEM
# ============================================
print_header "🔨 Шаг 7/8: Система сборки"

cat > "$INSTALL_DIR/builder/core.sh" << 'BUILDEREOF'
#!/bin/bash
set -e

APP_ID="$1"
APP_TYPE="$2"
INSTALL_DIR="/opt/safarali-multi-app-builder"
CONFIG_DIR="$INSTALL_DIR/config"
TEMPLATES_DIR="$INSTALL_DIR/templates"
OUTPUT_DIR="$INSTALL_DIR/output"
LOG_DIR="$INSTALL_DIR/logs"
WORK_DIR="$INSTALL_DIR/work/$APP_ID"
KEYSTORE="$INSTALL_DIR/keystore"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_DIR/build_${APP_ID}_$(date +%Y%m%d_%H%M%S).log"; }

log "🚀 Сборка: $APP_ID ($APP_TYPE)"

APP_CONFIG="$CONFIG_DIR/apps/${APP_ID}.json"
if [ ! -f "$APP_CONFIG" ]; then
    log "❌ Конфиг не найден"
    exit 1
fi

APP_NAME=$(jq -r '.name' "$APP_CONFIG")
PACKAGE_ID=$(jq -r '.package_id' "$APP_CONFIG")
VERSION=$(jq -r '.version' "$APP_CONFIG")

log "📱 $APP_NAME v$VERSION"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

TEMPLATE_DIR="$TEMPLATES_DIR/$APP_TYPE"
if [ ! -d "$TEMPLATE_DIR" ]; then
    log "❌ Шаблон не найден: $APP_TYPE"
    exit 1
fi

log "📋 Шаблон: $APP_TYPE"
cp -r "$TEMPLATE_DIR"/* . 2>/dev/null || true

cat > config.xml << CONFIGEOF
<?xml version='1.0' encoding='utf-8'?>
<widget id="$PACKAGE_ID" version="$VERSION" xmlns="http://www.w3.org/ns/widgets">
    <name>$APP_NAME</name>
    <description>$APP_NAME</description>
    <content src="index.html" />
    <preference name="android-minSdkVersion" value="24" />
    <preference name="android-targetSdkVersion" value="34" />
    <preference name="AndroidXEnabled" value="true" />
</widget>
CONFIGEOF

cordova platform ls | grep android >/dev/null 2>&1 || cordova platform add android@latest

log "🔨 Компиляция..."
export GRADLE_OPTS="${GRADLE_OPTS:--Xmx2048m}"

source "$KEYSTORE/.credentials" 2>/dev/null || true
cordova build android --release -- --packageType=apk \
    --keystore="$KEYSTORE_PATH" \
    --storePassword="$KEYSTORE_PASS" \
    --alias="$ALIAS" \
    --password="$KEYSTORE_PASS" 2>&1 | tee -a "$LOG_DIR/gradle_$APP_ID.log"

SRC_APK="platforms/android/app/build/outputs/apk/release/app-release.apk"
DST_APK="$OUTPUT_DIR/${APP_ID}.apk"

if [ -f "$SRC_APK" ]; then
    cp "$SRC_APK" "$DST_APK"
    log "✅ APK: $DST_APK"
    log "📦 Размер: $(du -h "$DST_APK" | cut -f1)"
    
    SETTINGS=$(jq -r '.domain' $CONFIG_DIR/settings.json)
    PUBLIC_DIR="/var/www/$SETTINGS/downloads"
    mkdir -p "$PUBLIC_DIR"
    cp "$DST_APK" "$PUBLIC_DIR/${APP_ID}.apk"
    chown -R www-www-data "$PUBLIC_DIR"
    
    log "🎉 Готово!"
else
    log "❌ Ошибка сборки"
    exit 1
fi
BUILDEREOF

chmod +x "$INSTALL_DIR/builder/core.sh"
chown "$BUILDER_USER:$BUILDER_USER" "$INSTALL_DIR/builder/core.sh"

print_success "Система сборки создана"

# ============================================
# 📱 ШАБЛОНЫ ПРИЛОЖЕНИЙ
# ============================================
print_header "📱 Создание шаблонов"

# Онлайн ТВ
cat > "$INSTALL_DIR/templates/online-tv/www/index.html" << 'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Online TV</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;background:linear-gradient(135deg,#0a0a14,#1a1a2e);color:#fff;padding:20px;min-height:100vh}.container{max-width:800px;margin:0 auto}h1{font-size:2rem;margin-bottom:20px;background:linear-gradient(135deg,#a855f7,#06b6d4);-webkit-background-clip:text;background-clip:text;color:transparent}.channel{background:rgba(255,255,255,0.05);padding:20px;margin:15px 0;border-radius:16px;border:1px solid rgba(255,255,255,0.1);display:flex;justify-content:space-between;align-items:center}.channel h3{font-size:1.2rem}.play{background:linear-gradient(135deg,#a855f7,#06b6d4);border:none;padding:12px 24px;border-radius:25px;color:#fff;font-weight:600;cursor:pointer;transition:transform 0.3s}.play:hover{transform:scale(1.05)}</style></head>
<body><div class="container"><h1>📺 Онлайн ТВ</h1><div class="channel"><h3>Канал 1</h3><button class="play">▶ Смотреть</button></div><div class="channel"><h3>Канал 2</h3><button class="play">▶ Смотреть</button></div><div class="channel"><h3>Канал 3</h3><button class="play">▶ Смотреть</button></div></div></body></html>
EOF

# Музыка
cat > "$INSTALL_DIR/templates/music/www/index.html" << 'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Music Player</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;background:linear-gradient(135deg,#0a0a14,#1a1a2e);color:#fff;padding:20px;min-height:100vh}.container{max-width:800px;margin:0 auto}h1{font-size:2rem;margin-bottom:20px;background:linear-gradient(135deg,#a855f7,#06b6d4);-webkit-background-clip:text;background-clip:text;color:transparent}.track{background:rgba(255,255,255,0.05);padding:20px;margin:15px 0;border-radius:16px;border:1px solid rgba(255,255,255,0.1);display:flex;justify-content:space-between;align-items:center}.track-info h3{font-size:1.1rem}.track-info p{color:rgba(255,255,255,0.6);font-size:0.9rem}.play{background:linear-gradient(135deg,#a855f7,#06b6d4);border:none;padding:12px 24px;border-radius:25px;color:#fff;font-weight:600;cursor:pointer}</style></head>
<body><div class="container"><h1>🎵 Музыка</h1><div class="track"><div class="track-info"><h3>Трек 1</h3><p>Исполнитель 1</p></div><button class="play">▶</button></div><div class="track"><div class="track-info"><h3>Трек 2</h3><p>Исполнитель 2</p></div><button class="play">▶</button></div><div class="track"><div class="track-info"><h3>Трек 3</h3><p>Исполнитель 3</p></div><button class="play">▶</button></div></div></body></html>
EOF

# Видео
cat > "$INSTALL_DIR/templates/video/www/index.html" << 'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Video Streaming</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;background:linear-gradient(135deg,#0a0a14,#1a1a2e);color:#fff;padding:20px;min-height:100vh}.container{max-width:800px;margin:0 auto}h1{font-size:2rem;margin-bottom:20px;background:linear-gradient(135deg,#a855f7,#06b6d4);-webkit-background-clip:text;background-clip:text;color:transparent}.video{background:rgba(255,255,255,0.05);padding:20px;margin:15px 0;border-radius:16px;border:1px solid rgba(255,255,255,0.1)}.video h3{font-size:1.2rem;margin-bottom:10px}.play{background:linear-gradient(135deg,#a855f7,#06b6d4);border:none;padding:12px 24px;border-radius:25px;color:#fff;font-weight:600;cursor:pointer}</style></head>
<body><div class="container"><h1>🎬 Видео</h1><div class="video"><h3>Видео 1</h3><p style="color:rgba(255,255,255,0.6);margin-bottom:15px">Описание видео</p><button class="play">▶ Смотреть</button></div><div class="video"><h3>Видео 2</h3><p style="color:rgba(255,255,255,0.6);margin-bottom:15px">Описание видео</p><button class="play">▶ Смотреть</button></div></div></body></html>
EOF

# Мессенджер
cat > "$INSTALL_DIR/templates/messenger/www/index.html" << 'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Messenger</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;background:linear-gradient(135deg,#0a0a14,#1a1a2e);color:#fff;padding:20px;min-height:100vh}.container{max-width:800px;margin:0 auto}h1{font-size:2rem;margin-bottom:20px;background:linear-gradient(135deg,#a855f7,#06b6d4);-webkit-background-clip:text;background-clip:text;color:transparent}.chat{background:rgba(255,255,255,0.05);padding:20px;margin:15px 0;border-radius:16px;border:1px solid rgba(255,255,255,0.1)}.chat h3{font-size:1.1rem;margin-bottom:5px}.chat p{color:rgba(255,255,255,0.6);font-size:0.9rem}.actions{display:flex;gap:10px;margin-top:30px}.btn{background:linear-gradient(135deg,#a855f7,#06b6d4);border:none;padding:15px 30px;border-radius:25px;color:#fff;font-weight:600;cursor:pointer;flex:1}</style></head>
<body><div class="container"><h1>💬 Мессенджер</h1><div class="chat"><h3>Чат 1</h3><p>Последнее сообщение...</p></div><div class="chat"><h3>Чат 2</h3><p>Последнее сообщение...</p></div><div class="actions"><button class="btn">🎤 Аудиозвонок</button><button class="btn">📹 Видеозвонок</button></div></div></body></html>
EOF

# Остальные шаблоны
for type in ecommerce news education; do
    cat > "$INSTALL_DIR/templates/$type/www/index.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>App</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;background:linear-gradient(135deg,#0a0a14,#1a1a2e);color:#fff;padding:20px;min-height:100vh;display:flex;align-items:center;justify-content:center;text-align:center}.container{max-width:600px}h1{font-size:2.5rem;margin-bottom:20px;background:linear-gradient(135deg,#a855f7,#06b6d4);-webkit-background-clip:text;background-clip:text;color:transparent}p{color:rgba(255,255,255,0.7);margin-bottom:30px;font-size:1.2rem}.btn{background:linear-gradient(135deg,#a855f7,#06b6d4);border:none;padding:15px 40px;border-radius:25px;color:#fff;font-weight:600;cursor:pointer;font-size:1.1rem}</style></head>
<body><div class="container"><h1>✨ Приложение готово</h1><p>Тип: $type</p><button class="btn">Начать использование</button></div></body></html>
EOF
done

print_success "Шаблоны созданы"

# ============================================
# 🌐 ШАГ 8: ВЕБ-ПАНЕЛЬ
# ============================================
print_header "🌐 Шаг 8/8: Веб-панель управления"

cat > "$WEB_DIR/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🎛️ Safarali Multi-App Builder</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root{--bg:#0a0a14;--card:rgba(255,255,255,.05);--border:rgba(255,255,255,.1);--primary:#a855f7;--accent:#06b6d4;--text:#fff;--muted:rgba(255,255,255,.6)}
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:'Inter',sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
        .container{max-width:1400px;margin:0 auto;padding:1.5rem}
        header{display:flex;justify-content:space-between;align-items:center;padding:1rem 0;border-bottom:1px solid var(--border);margin-bottom:2rem;flex-wrap:wrap;gap:1rem}
        .logo{font-size:1.5rem;font-weight:800;background:linear-gradient(135deg,var(--primary),var(--accent));-webkit-background-clip:text;background-clip:text;color:transparent}
        .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:1.5rem}
        .card{background:var(--card);border:1px solid var(--border);border-radius:20px;padding:1.5rem}
        .card h3{color:var(--primary);margin-bottom:1rem;font-size:1.3rem}
        .form-group{margin-bottom:1rem}
        .form-group label{display:block;font-size:.9rem;color:var(--muted);margin-bottom:.3rem}
        .form-group input,.form-group select{width:100%;padding:.7rem;border-radius:12px;border:1px solid var(--border);background:rgba(0,0,0,.3);color:#fff;font-size:1rem}
        .btn{background:linear-gradient(135deg,var(--primary),var(--accent));border:none;padding:.8rem 1.5rem;border-radius:50px;color:#fff;font-weight:600;cursor:pointer;margin-right:.5rem;margin-top:.5rem;transition:opacity 0.3s}
        .btn:hover{opacity:0.9}.btn:disabled{opacity:0.5}
        .btn-secondary{background:rgba(255,255,255,.1)}
        .log{background:#000;border-radius:12px;padding:1rem;font-family:monospace;font-size:.85rem;max-height:350px;overflow-y:auto;color:#4ade80;white-space:pre-wrap}
        .app-type-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:1rem;margin:1rem 0}
        .app-type-card{border:1px solid var(--border);border-radius:16px;padding:1.5rem;text-align:center;cursor:pointer;transition:.3s;background:rgba(0,0,0,.2)}
        .app-type-card:hover,.app-type-card.selected{border-color:var(--primary);background:rgba(168,85,247,.1)}
        .app-type-icon{font-size:2.5rem;margin-bottom:.5rem}
        .app-type-name{font-size:.9rem;font-weight:500}
        .app-list{margin-top:1rem}
        .app-item{display:flex;justify-content:space-between;align-items:center;padding:1rem;border:1px solid var(--border);border-radius:12px;margin-bottom:.5rem;background:rgba(0,0,0,.2)}
        .app-item-info strong{display:block;margin-bottom:.25rem}
        .app-item-info small{color:var(--muted)}
        .stats{display:grid;grid-template-columns:repeat(2,1fr);gap:1rem;margin-bottom:1.5rem}
        .stat-card{background:rgba(0,0,0,.3);border-radius:12px;padding:1rem;text-align:center}
        .stat-value{font-size:1.8rem;font-weight:700;color:var(--primary)}
        .stat-label{font-size:.85rem;color:var(--muted)}
        @media(max-width:768px){.grid{grid-template-columns:1fr}}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="logo">🎛️ Safarali Builder</div>
            <div style="color:var(--muted)">$BUILD_DOMAIN</div>
        </header>
        
        <div class="grid">
            <div class="card">
                <h3>📱 Создать приложение</h3>
                <div class="form-group">
                    <label>Название приложения</label>
                    <input type="text" id="appName" placeholder="My App">
                </div>
                <div class="form-group">
                    <label>Тип приложения</label>
                    <div class="app-type-grid" id="appTypes"></div>
                </div>
                <div class="form-group">
                    <label>Package ID</label>
                    <input type="text" id="packageId" placeholder="uz.safarali.myapp">
                </div>
                <div class="form-group">
                    <label>Версия</label>
                    <input type="text" id="appVersion" value="1.0.0">
                </div>
                <button class="btn" onclick="createApp()">➕ Создать приложение</button>
            </div>
            
            <div class="card">
                <h3>📋 Мои приложения</h3>
                <div class="stats">
                    <div class="stat-card">
                        <div class="stat-value" id="totalApps">0</div>
                        <div class="stat-label">Приложений</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value" id="totalBuilds">0</div>
                        <div class="stat-label">Сборок</div>
                    </div>
                </div>
                <div class="app-list" id="appList"></div>
            </div>
            
            <div class="card">
                <h3>🔨 Сборка приложения</h3>
                <div class="form-group">
                    <label>Выберите приложение</label>
                    <select id="buildApp"></select>
                </div>
                <button class="btn" id="buildBtn" onclick="triggerBuild()">🚀 Запустить сборку</button>
                <button class="btn btn-secondary" onclick="downloadAPK()">📥 Скачать APK</button>
                <div class="log" id="buildLog">Ожидание...</div>
            </div>
        </div>
    </div>
    
    <script>
        const API = '/api/index.php';
        const SECRET = localStorage.getItem('api_secret') || prompt('🔑 Введите API Secret:');
        if(SECRET) localStorage.setItem('api_secret', SECRET);
        let selectedType = '';
        
        async function api(action, method='GET', body=null) {
            const opts = {
                method,
                headers: {'Content-Type':'application/json','X-API-Secret':SECRET}
            };
            if(body) opts.body = JSON.stringify(body);
            return (await fetch(\`\${API}?action=\${action}\`, opts)).json();
        }
        
        async function loadAppTypes() {
            const r = await api('get_app_types');
            const container = document.getElementById('appTypes');
            if(r.success) {
                container.innerHTML = Object.entries(r.types).map(([key, val]) => \`
                    <div class="app-type-card" onclick="selectType('\${key}')">
                        <div class="app-type-icon">\${val.icon}</div>
                        <div class="app-type-name">\${val.name}</div>
                    </div>
                \`).join('');
            }
        }
        
        function selectType(type) {
            selectedType = type;
            document.querySelectorAll('.app-type-card').forEach(c => c.classList.remove('selected'));
            event.target.closest('.app-type-card').classList.add('selected');
            document.getElementById('packageId').value = \`uz.safarali.\${type}.\${Date.now()}\`;
        }
        
        async function createApp() {
            if(!selectedType) { alert('⚠️ Выберите тип приложения!'); return; }
            const r = await api('create_app', 'POST', {
                name: document.getElementById('appName').value,
                type: selectedType,
                package_id: document.getElementById('packageId').value,
                version: document.getElementById('appVersion').value
            });
            if(r.success) {
                alert('✅ Приложение создано!');
                document.getElementById('appName').value = '';
                loadApps();
            } else {
                alert('❌ ' + r.error);
            }
        }
        
        async function loadApps() {
            const r = await api('list_apps');
            const list = document.getElementById('appList');
            const select = document.getElementById('buildApp');
            if(r.success) {
                document.getElementById('totalApps').textContent = r.apps.length;
                if(r.apps.length === 0) {
                    list.innerHTML = '<p style="color:var(--muted);text-align:center;padding:2rem">Нет приложений</p>';
                    select.innerHTML = '<option value="">Нет приложений</option>';
                } else {
                    list.innerHTML = r.apps.map(app => \`
                        <div class="app-item">
                            <div class="app-item-info">
                                <strong>\${app.name}</strong>
                                <small>\${app.type} • v\${app.version}</small>
                            </div>
                            <button class="btn btn-secondary" onclick="buildApp('\${app.id}')">🔨</button>
                        </div>
                    \`).join('');
                    select.innerHTML = r.apps.map(app => \`<option value="\${app.id}">\${app.name}</option>\`).join('');
                }
            }
        }
        
        async function buildApp(id) {
            if(!id) { alert('⚠️ Выберите приложение!'); return; }
            const btn = document.getElementById('buildBtn');
            btn.disabled = true;
            const r = await api('build_app', 'POST', {id});
            if(r.success) {
                alert('🚀 Сборка запущена! Ожидайте 5-15 минут...');
                pollLogs();
            } else {
                alert('❌ ' + r.error);
                btn.disabled = false;
            }
        }
        
        async function triggerBuild() {
            await buildApp(document.getElementById('buildApp').value);
        }
        
        function pollLogs() {
            const interval = setInterval(async () => {
                const r = await api('build_status');
                document.getElementById('buildLog').textContent = r.logs;
                if(r.logs.includes('🎉') || r.logs.includes('❌')) {
                    clearInterval(interval);
                    document.getElementById('buildBtn').disabled = false;
                    loadApps();
                }
            }, 3000);
        }
        
        async function downloadAPK() {
            const id = document.getElementById('buildApp').value;
            if(!id) { alert('⚠️ Выберите приложение!'); return; }
            window.location.href = \`\${API}?action=download_apk&id=\${id}&secret=\${SECRET}\`;
        }
        
        // Init
        loadAppTypes();
        loadApps();
        setInterval(loadApps, 30000);
    </script>
</body>
</html>
HTMLEOF

chown -R www-www-data $WEB_DIR

print_success "Веб-панель создана"

# ============================================
# 🎉 ФИНАЛ
# ============================================
print_header "✅ УСТАНОВКА ЗАВЕРШЕНА!"

cat > /root/builder-info.txt << INFOEOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 SAFARALI MULTI-APP BUILDER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌐 ПАНЕЛЬ УПРАВЛЕНИЯ:
   https://$BUILD_DOMAIN

🔑 API SECRET (сохраните!):
   $API_SECRET

🔐 KEYSTORE PASS (сохраните!):
   $KEYSTORE_PASS

📁 ДИРЕКТОРИИ:
   • Установка: $INSTALL_DIR
   • Приложения: $INSTALL_DIR/config/apps/
   • APK файлы: $INSTALL_DIR/output/
   • Логи: $INSTALL_DIR/logs/
   • Ключи: $INSTALL_DIR/keystore/.credentials
   • Веб-панель: $WEB_DIR

📱 ТИПЫ ПРИЛОЖЕНИЙ:
   • 📺 Онлайн ТВ
   • 🎵 Музыка
   • 🎬 Видео
   • 💬 Мессенджер (аудио/видео звонки)
   • 🛒 Магазин
   • 📰 Новости
   • 📚 Образование

🔧 КОМАНДЫ:
   • Статус: systemctl status nginx php8.1-fpm
   • Логи: tail -f $INSTALL_DIR/logs/*.log
   • Бэкап ключей: cp -r $INSTALL_DIR/keystore /backup/
   • Перезапуск: systemctl restart nginx

📌 СЛЕДУЮЩИЕ ШАГИ:
   1. Настройте DNS: $BUILD_DOMAIN → $(hostname -I | awk '{print $1}')
   2. Откройте: https://$BUILD_DOMAIN
   3. Введите API Secret (выше)
   4. Создайте приложение
   5. Запустите сборку

⚠️  ВАЖНО:
   • Сохраните KEYSTORE PASS — без него нельзя обновлять APK!
   • Сохраните API SECRET — нужен для доступа к панели!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INFOEOF

cat /root/builder-info.txt

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${BOLD}🎉 ГОТОВО!${NC}"
echo -e "${NC}IP сервера: $(hostname -I | awk '{print $1}')${NC}"
echo -e "${NC}Настройте DNS: $BUILD_DOMAIN → $(hostname -I | awk '{print $1}')${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""