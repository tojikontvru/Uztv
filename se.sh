#!/bin/bash
# ============================================
# SAFARALI GROUP — BUILD SERVER ONLY
# Только генерация мобильных приложений
# Подключается к внешнему Matrix-серверу
# ============================================
set -e

# 🎨 Цвета
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_header() { echo ""; echo -e "${YELLOW}═══════════════════════════════════════${NC}"; echo -e "${GREEN} $1 ${NC}"; echo -e "${YELLOW}═══════════════════════════════════════${NC}"; }

# ⚙️ КОНФИГУРАЦИЯ (изменить перед запуском)
BUILD_DOMAIN="build.safaraligroup.uz"
MATRIX_SERVER_URL="https://safaraligroup.uz"  # ← ВАШ СУЩЕСТВУЮЩИЙ МАТРИКС-СЕРВЕР
ADMIN_EMAIL="admin@safaraligroup.uz"
API_SECRET=$(openssl rand -hex 32)
KEYSTORE_PASS=$(openssl rand -hex 16)
BUILDER_USER="builder"

print_header "🚀 SAFARALI GROUP — BUILD SERVER SETUP"
print_info "Домен панели: $BUILD_DOMAIN"
print_info "Matrix сервер: $MATRIX_SERVER_URL"
print_info "API Secret: $API_SECRET (сохраните!)"

# 💾 Проверка ресурсов
check_resources() {
    local ram=$(free -g | awk '/^Mem:/{print $2}')
    local disk=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    print_info "Ресурсы: ${ram} ГБ RAM, ${disk} ГБ свободно"
    
    if [ "$ram" -lt 3 ]; then
        print_info "⚠️ Включён эконом-режим сборки"
        export GRADLE_OPTS="-Xmx1024m -XX:MaxMetaspaceSize=256m"
        export NODE_OPTIONS="--max-old-space-size=1024"
    fi
}
check_resources

# ============================================
# 📦 ШАГ 1: БАЗОВАЯ ПОДГОТОВКА
# ============================================
print_header "📦 Шаг 1/5: Подготовка системы"

apt update && apt upgrade -y
apt install -y curl wget git unzip zip nginx \
    openjdk-17-jdk php8.1-fpm php8.1-cli php8.1-mbstring php8.1-json \
    supervisor cron certbot python3-certbot-nginx jq

# Node.js 20 + Cordova
apt remove --purge -y nodejs npm 2>/dev/null || true
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g cordova android-versions

print_success "Базовые пакеты установлены"

# ============================================
# 🔐 ШАГ 2: ПОЛЬЗОВАТЕЛЬ И БЕЗОПАСНОСТЬ
# ============================================
print_header "🔐 Шаг 2/5: Пользователь и безопасность"

# Создаём изолированного пользователя
if ! id "$BUILDER_USER" &>/dev/null; then
    useradd -r -m -s /bin/bash "$BUILDER_USER"
fi

# SSL для веб-панели
if ! systemctl is-active --quiet nginx; then
    systemctl enable --now nginx
fi

# SSL (опционально, можно позже)
if command -v certbot &>/dev/null && [ -n "$ADMIN_EMAIL" ]; then
    print_info "Настройка SSL (можно пропустить если нет DNS)..."
    certbot --nginx -d "$BUILD_DOMAIN" --non-interactive \
        --agree-tos -m "$ADMIN_EMAIL" --redirect 2>/dev/null || \
        print_info "⚠️ SSL отложен (настройте DNS и запустите: certbot --nginx -d $BUILD_DOMAIN)"
fi

print_success "Безопасность настроена"

# ============================================
# 🛠️ ШАГ 3: ЯДРО СИСТЕМЫ СБОРКИ
# ============================================
print_header "🛠️ Шаг 3/5: Ядро системы сборки"

mkdir -p /opt/mobile-builder/{config/{variants,features},output,logs,keystore}
chown -R "$BUILDER_USER:$BUILDER_USER" /opt/mobile-builder

# 🔑 Генерация ключа подписи (ОДИН РАЗ!)
if [ ! -f /opt/mobile-builder/keystore/release.jks ]; then
    print_info "Генерация ключа подписи APK..."
    keytool -genkey -v \
        -keystore /opt/mobile-builder/keystore/release.jks \
        -alias safarali_release \
        -keyalg RSA -keysize 2048 \
        -validity 10000 \
        -storepass "$KEYSTORE_PASS" \
        -keypass "$KEYSTORE_PASS" \
        -dname "CN=Safarali Group, OU=Mobile, O=Safarali, L=Tashkent, C=UZ"
    
    echo "# 🔐 Ключ подписи — НЕ ТЕРЯЙТЕ!
KEYSTORE_PASS=$KEYSTORE_PASS
ALIAS=safarali_release
KEYSTORE_PATH=/opt/mobile-builder/keystore/release.jks
" > /opt/mobile-builder/keystore/.credentials
    chmod 600 /opt/mobile-builder/keystore/.credentials
    print_success "Ключ сохранён: /opt/mobile-builder/keystore/.credentials"
fi

# ⚙️ ГЛАВНЫЙ ФАЙЛ НАСТРОЕК (расширяемый!)
cat > /opt/mobile-builder/config/settings.json << SETTINGS_EOF
{
  "server": {
    "matrix_url": "$MATRIX_SERVER_URL",
    "api_secret": "$API_SECRET",
    "webhook_url": "",
    "webhook_secret": ""
  },
  "app": {
    "default_variant": "default",
    "package_prefix": "uz.safarali",
    "min_sdk": 24,
    "target_sdk": 34,
    "version": {
      "name": "1.0.0",
      "code": 1
    }
  },
  "build": {
    "auto_sign": true,
    "generate_aab": false,
    "keep_intermediate": false,
    "max_concurrent": 1,
    "timeout_minutes": 45
  },
  "features": {
    "voice_messages": {"enabled": true, "config": {}},
    "video_calls": {"enabled": true, "config": {"max_resolution": "720p"}},
    "file_sharing": {"enabled": true, "config": {"max_size_mb": 2048}},
    "e2e_encryption": {"enabled": true, "config": {}},
    "pwa_support": {"enabled": false, "config": {}},
    "custom_theme": {"enabled": false, "config": {"primary_color": "#a855f7"}}
  },
  "output": {
    "public_downloads": "https://$BUILD_DOMAIN/downloads",
    "notify_on_complete": true,
    "telegram_bot_token": "",
    "telegram_chat_id": ""
  }
}
SETTINGS_EOF

# 🧩 ШАБЛОНЫ ВАРИАНТОВ ПРИЛОЖЕНИЯ
cat > /opt/mobile-builder/config/variants/default.json << 'EOF'
{
  "id": "default",
  "name": "Safarali Group",
  "description": "Полнофункциональный мессенджер",
  "package_suffix": "",
  "features": ["voice_messages", "video_calls", "file_sharing", "e2e_encryption"],
  "ui": {
    "theme": "dark",
    "show_server_select": false,
    "custom_logo": ""
  }
}
EOF

cat > /opt/mobile-builder/config/variants/lite.json << 'EOF'
{
  "id": "lite",
  "name": "Safarali Lite",
  "description": "Облегчённая версия для слабых устройств",
  "package_suffix": ".lite",
  "features": ["voice_messages", "file_sharing"],
  "ui": {
    "theme": "light",
    "show_server_select": true,
    "custom_logo": ""
  },
  "build": {
    "min_sdk": 21,
    "exclude_modules": ["video_codec", "animations"]
  }
}
EOF

cat > /opt/mobile-builder/config/variants/enterprise.json << 'EOF'
{
  "id": "enterprise",
  "name": "Safarali Enterprise",
  "description": "Версия для организаций",
  "package_suffix": ".enterprise",
  "features": ["voice_messages", "video_calls", "file_sharing", "e2e_encryption", "custom_theme"],
  "ui": {
    "theme": "corporate",
    "show_server_select": false,
    "custom_logo": "https://example.com/logo.png",
    "forced_server": ""
  },
  "security": {
    "require_cert_pinning": true,
    "allowed_servers": []
  }
}
EOF

# 🔌 ПРИМЕРЫ ФУНКЦИЙ (можно добавлять свои)
cat > /opt/mobile-builder/config/features/custom_branding.json << 'EOF'
{
  "id": "custom_branding",
  "name": "Кастомный брендинг",
  "description": "Логотип, цвета, название",
  "config_schema": {
    "app_name": {"type": "string", "required": true},
    "primary_color": {"type": "color", "default": "#a855f7"},
    "logo_url": {"type": "url", "required": false},
    "splash_color": {"type": "color", "default": "#0a0a14"}
  },
  "cordova_plugins": [],
  "gradle_config": {},
  "web_assets": {
    "inject_css": "body{--primary:{{primary_color}}}",
    "replace_strings": {"{{APP_NAME}}": "app_name"}
  }
}
EOF

print_success "Ядро системы настроено"

# ============================================
# 🛠️ ШАГ 4: СКРИПТ СБОРКИ (builder.sh)
# ============================================
cat > /opt/mobile-builder/builder.sh << 'BUILDER_EOF'
#!/bin/bash
# SAFARALI GROUP — Mobile App Builder Core
set -e

CONFIG_DIR="/opt/mobile-builder/config"
SETTINGS="$CONFIG_DIR/settings.json"
LOG_DIR="/opt/mobile-builder/logs"
OUTPUT_DIR="/opt/mobile-builder/output"
KEYSTORE="/opt/mobile-builder/keystore"

# Чтение JSON через jq
json_get() { jq -r "$1" "$SETTINGS" 2>/dev/null || echo "$2"; }
json_get_variant() { jq -r ".variants[] | select(.id==\"$1\") | $2" "$CONFIG_DIR/variants.json" 2>/dev/null || echo "$3"; }

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"; }

# === АРГУМЕНТЫ ===
VARIANT="${1:-default}"
ACTION="${2:-build}"  # build, clean, list

case "$ACTION" in
    list)
        echo "Доступные варианты:"
        jq -r '.[] | "  • \(.id): \(.name) — \(.description)"' "$CONFIG_DIR/variants/"*.json 2>/dev/null || echo "  (нет вариантов)"
        exit 0
        ;;
    clean)
        log "🧹 Очистка..."
        rm -rf /opt/mobile-builder/work/*
        exit 0
        ;;
esac

# === ЗАГРУЗКА НАСТРОЕК ===
MATRIX_URL=$(json_get '.server.matrix_url' 'https://matrix.org')
API_SECRET=$(json_get '.server.api_secret' '')
APP_PREFIX=$(json_get '.app.package_prefix' 'uz.safarali')
MIN_SDK=$(json_get '.app.min_sdk' 24)
TARGET_SDK=$(json_get '.app.target_sdk' 34)
VERSION_NAME=$(json_get '.app.version.name' '1.0.0')
VERSION_CODE=$(json_get '.app.version.code' 1)

# Загрузка варианта
VARIANT_FILE="$CONFIG_DIR/variants/${VARIANT}.json"
if [ ! -f "$VARIANT_FILE" ]; then
    log "❌ Вариант не найден: $VARIANT"
    exit 1
fi
VARIANT_NAME=$(jq -r '.name' "$VARIANT_FILE")
VARIANT_SUFFIX=$(jq -r '.package_suffix // ""' "$VARIANT_FILE")
VARIANT_FEATURES=$(jq -r '.features[]' "$VARIANT_FILE" 2>/dev/null || echo "")

log "🚀 Сборка: $VARIANT_NAME ($VARIANT)"
log "🔗 Matrix сервер: $MATRIX_URL"

# === ПОДГОТОВКА ПРОЕКТА ===
WORK_DIR="/opt/mobile-builder/work/SafaraliApp"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Создаём/обновляем Cordova проект
if [ ! -f "config.xml" ]; then
    log "📱 Создание Cordova проекта..."
    cordova create . "${APP_PREFIX}${VARIANT_SUFFIX}" "$VARIANT_NAME"
fi

# Обновляем config.xml
cat > config.xml << CONFIG_EOF
<?xml version='1.0' encoding='utf-8'?>
<widget id="${APP_PREFIX}${VARIANT_SUFFIX}" version="$VERSION_NAME" android-versionCode="$VERSION_CODE" xmlns="http://www.w3.org/ns/widgets">
    <name>$VARIANT_NAME</name>
    <description>Мессенджер Safarali Group — $VARIANT_NAME</description>
    <content src="index.html" />
    <allow-navigation href="$MATRIX_URL/*" />
    <allow-intent href="https://*/*" />
    <preference name="android-minSdkVersion" value="$MIN_SDK" />
    <preference name="android-targetSdkVersion" value="$TARGET_SDK" />
    <preference name="AndroidXEnabled" value="true" />
    <preference name="Fullscreen" value="true" />
</widget>
CONFIG_EOF

# === ГЕНЕРАЦИЯ ИНТЕРФЕЙСА ===
log "🎨 Генерация интерфейса..."

# Читаем активные функции
FEATURES_ENABLED=""
for feat in $VARIANT_FEATURES; do
    feat_config="$CONFIG_DIR/features/${feat}.json"
    if [ -f "$feat_config" ]; then
        enabled=$(jq -r ".enabled // true" "$SETTINGS" 2>/dev/null || echo "true")
        [ "$enabled" = "true" ] && FEATURES_ENABLED="$FEATURES_ENABLED $feat"
    fi
done

# Создаём index.html с учётом функций
cat > www/index.html << HTML_EOF
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <title>$VARIANT_NAME</title>
  <style>
    :root{--bg:#0a0a14;--card:rgba(255,255,255,.05);--border:rgba(255,255,255,.1);--primary:#a855f7;--text:#fff}
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
    .app{background:var(--card);border:1px solid var(--border);border-radius:24px;padding:24px;max-width:400px;width:100%;text-align:center}
    .logo{font-size:1.8rem;font-weight:800;background:linear-gradient(135deg,var(--primary),#06b6d4);-webkit-background-clip:text;background-clip:text;color:transparent;margin-bottom:12px}
    .server{background:rgba(0,0,0,.3);padding:8px 12px;border-radius:10px;margin:12px 0;font-size:.9rem}
    .features{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin:16px 0}
    .feature{background:rgba(255,255,255,.03);padding:8px;border-radius:8px;font-size:.8rem}
    .btn{display:inline-block;background:linear-gradient(135deg,var(--primary),#06b6d4);padding:10px 20px;border-radius:40px;color:#fff;text-decoration:none;font-weight:600;margin-top:12px;cursor:pointer;border:none}
    .status{margin-top:12px;font-size:.85rem;color:rgba(255,255,255,.7)}
  </style>
</head>
<body>
  <div class="app">
    <div class="logo">✨ $VARIANT_NAME</div>
    <h3>Безопасный мессенджер</h3>
    <div class="server">🔗 $MATRIX_URL</div>
    <div class="features">
HTML_EOF

# Динамические фичи
[[ " $FEATURES_ENABLED " =~ "voice_messages" ]] && echo '      <div class="feature">🎤 Голосовые</div>' >> www/index.html
[[ " $FEATURES_ENABLED " =~ "video_calls" ]] && echo '      <div class="feature">🎥 Видеозвонки</div>' >> www/index.html
[[ " $FEATURES_ENABLED " =~ "file_sharing" ]] && echo '      <div class="feature">📁 Файлы</div>' >> www/index.html
[[ " $FEATURES_ENABLED " =~ "e2e_encryption" ]] && echo '      <div class="feature">🔒 Шифрование</div>' >> www/index.html

cat >> www/index.html << 'HTML_EOF'
    </div>
    <button class="btn" onclick="connect()">🔗 Подключиться</button>
    <div class="status" id="status">Готов</div>
  </div>
  <script>
    const SERVER="'"$MATRIX_URL"'";
    function connect(){
      const s=document.getElementById('status');
      s.textContent='🔄 Проверка...';
      fetch(SERVER+'/_matrix/client/versions').then(r=>{
        if(r.ok){s.textContent='✅ Готово!'; setTimeout(()=>window.location.href=SERVER,800);}
        else s.textContent='❌ Ошибка сервера';
      }).catch(()=>s.textContent='❌ Нет сети');
    }
  </script>
</body>
</html>
HTML_EOF

# === ПЛАТФОРМА И ПЛАГИНЫ ===
cordova platform ls | grep android >/dev/null 2>&1 || cordova platform add android@latest

# Плагины в зависимости от функций
for feat in $FEATURES_ENABLED; do
    case "$feat" in
        voice_messages) cordova plugin add cordova-plugin-media --save 2>/dev/null || true ;;
        video_calls) cordova plugin add cordova-plugin-webrtc --save 2>/dev/null || true ;;
        file_sharing) cordova plugin add cordova-plugin-file --save 2>/dev/null || true ;;
    esac
done

# === СБОРКА ===
log "🔨 Компиляция APK..."
export GRADLE_OPTS="${GRADLE_OPTS:--Xmx2048m}"

BUILD_CMD="cordova build android --release -- --packageType=apk"
if json_get '.build.auto_sign' 'true' | grep -q true; then
    source "$KEYSTORE/.credentials" 2>/dev/null || true
    BUILD_CMD="$BUILD_CMD --keystore=$KEYSTORE_PATH --storePassword=$KEYSTORE_PASS --alias=$ALIAS --password=$KEYSTORE_PASS"
fi

$BUILD_CMD 2>&1 | tee -a "$LOG_DIR/gradle.log"

# === КОПИРОВАНИЕ РЕЗУЛЬТАТА ===
SRC_APK="platforms/android/app/build/outputs/apk/release/app-release.apk"
DST_APK="$OUTPUT_DIR/${APP_PREFIX}${VARIANT_SUFFIX}-v${VERSION_NAME}.apk"

if [ -f "$SRC_APK" ]; then
    mkdir -p "$(dirname "$DST_APK")"
    cp "$SRC_APK" "$DST_APK"
    log "✅ APK готов: $DST_APK"
    log "📦 Размер: $(du -h "$DST_APK" | cut -f1)"
    
    # Публичная копия
    PUBLIC_DIR="/var/www/$BUILD_DOMAIN/downloads"
    mkdir -p "$PUBLIC_DIR"
    cp "$DST_APK" "$PUBLIC_DIR/app-release.apk"
    
    # Уведомление (если настроено)
    if json_get '.output.notify_on_complete' 'false' | grep -q true; then
        TG_TOKEN=$(json_get '.output.telegram_bot_token' '')
        TG_CHAT=$(json_get '.output.telegram_chat_id' '')
        if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
            curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
                -d chat_id="$TG_CHAT" \
                -d text="✅ Сборка завершена: $VARIANT_NAME v$VERSION_NAME%0A📦 $(du -h "$DST_APK" | cut -f1)%0A🔗 $(json_get '.output.public_downloads' '')/app-release.apk" \
                >/dev/null 2>&1 || true
        fi
    fi
else
    log "❌ Ошибка: APK не создан"
    exit 1
fi

log "🎉 Сборка завершена!"
exit 0
BUILDER_EOF

chmod +x /opt/mobile-builder/builder.sh
chown "$BUILDER_USER:$BUILDER_USER" /opt/mobile-builder/builder.sh

print_success "Скрипт сборки готов"

# ============================================
# 🌐 ШАГ 5: ВЕБ-ПАНЕЛЬ УПРАВЛЕНИЯ
# ============================================
print_header "🌐 Шаг 4/5: Веб-панель управления"

mkdir -p /var/www/$BUILD_DOMAIN/{api,downloads,logs}
chown -R www-www-data /var/www/$BUILD_DOMAIN

# 🔐 API Бэкенд (полнофункциональный)
cat > /var/www/$BUILD_DOMAIN/api/index.php << 'PHPEOF'
<?php
// SAFARALI GROUP — Build Server API
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-API-Secret');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$CONFIG_DIR = '/opt/mobile-builder/config';
$SETTINGS_FILE = "$CONFIG_DIR/settings.json";
$API_SECRET = getenv('API_SECRET') ?: (json_decode(file_get_contents($SETTINGS_FILE), true)['server']['api_secret'] ?? '');

// 🔐 Проверка токена
$provided = $_SERVER['HTTP_X_API_SECRET'] ?? $_GET['secret'] ?? '';
if (!hash_equals($API_SECRET, $provided)) {
    http_response_code(401);
    echo json_encode(['error' => 'Unauthorized', 'hint' => 'Use X-API-Secret header']);
    exit;
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$settings = json_decode(file_get_contents($SETTINGS_FILE), true);

switch($action) {
    case 'get_settings':
        $safe = $settings;
        unset($safe['server']['api_secret'], $safe['build']['keystore_pass']);
        echo json_encode(['success' => true, 'settings' => $safe]);
        break;
        
    case 'update_settings':
        $input = json_decode(file_get_contents('php://input'), true);
        if(!$input) { http_response_code(400); echo json_encode(['error'=>'Invalid JSON']); break; }
        
        // Обновляем только разрешённые секции
        foreach(['server','app','build','features','output'] as $section) {
            if(isset($input[$section]) && is_array($input[$section])) {
                $settings[$section] = array_merge($settings[$section], $input[$section]);
            }
        }
        file_put_contents($SETTINGS_FILE, json_encode($settings, JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
        echo json_encode(['success' => true, 'message' => 'Настройки сохранены']);
        break;
        
    case 'list_variants':
        $variants = [];
        foreach(glob("$CONFIG_DIR/variants/*.json") as $f) {
            $variants[] = json_decode(file_get_contents($f), true);
        }
        echo json_encode(['success' => true, 'variants' => $variants]);
        break;
        
    case 'get_variant':
        $id = $_GET['id'] ?? '';
        $file = "$CONFIG_DIR/variants/$id.json";
        if(file_exists($file)) {
            echo json_encode(['success' => true, 'variant' => json_decode(file_get_contents($file), true)]);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Variant not found']);
        }
        break;
        
    case 'save_variant':
        $input = json_decode(file_get_contents('php://input'), true);
        if(!isset($input['id'])) { http_response_code(400); echo json_encode(['error'=>'id required']); break; }
        $file = "$CONFIG_DIR/variants/{$input['id']}.json";
        file_put_contents($file, json_encode($input, JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE));
        echo json_encode(['success' => true, 'message' => 'Вариант сохранён']);
        break;
        
    case 'list_features':
        $features = [];
        foreach(glob("$CONFIG_DIR/features/*.json") as $f) {
            $feat = json_decode(file_get_contents($f), true);
            $feat['enabled'] = $settings['features'][$feat['id']]['enabled'] ?? false;
            $features[] = $feat;
        }
        echo json_encode(['success' => true, 'features' => $features]);
        break;
        
    case 'toggle_feature':
        $input = json_decode(file_get_contents('php://input'), true);
        $feat = $input['id'] ?? '';
        $state = $input['enabled'] ?? false;
        if($feat && isset($settings['features'][$feat])) {
            $settings['features'][$feat]['enabled'] = $state;
            file_put_contents($SETTINGS_FILE, json_encode($settings, JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE));
            echo json_encode(['success' => true, 'message' => "Функция $feat: " . ($state?'включена':'выключена')]);
        } else {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid feature']);
        }
        break;
        
    case 'trigger_build':
        $variant = $_POST['variant'] ?? 'default';
        $log = "/opt/mobile-builder/logs/build_" . date('Ymd_His') . ".log";
        $cmd = "sudo -u builder /opt/mobile-builder/builder.sh " . escapeshellarg($variant) . " > $log 2>&1 &";
        exec($cmd);
        echo json_encode(['success' => true, 'message' => "Сборка $variant запущена", 'log' => basename($log)]);
        break;
        
    case 'build_logs':
        $logs = glob('/opt/mobile-builder/logs/build_*.log');
        rsort($logs);
        $latest = $logs[0] ?? null;
        $output = $latest ? file_get_contents($latest) : 'Нет логов';
        echo json_encode(['success' => true, 'logs' => substr($output, -5000), 'file' => basename($latest ?? '')]);
        break;
        
    case 'download_apk':
        $apk = '/var/www/' . $_SERVER['HTTP_HOST'] . '/downloads/app-release.apk';
        if(file_exists($apk)) {
            header('Content-Type: application/vnd.android.package-archive');
            header('Content-Disposition: attachment; filename="safarali-app.apk"');
            header('Content-Length: ' . filesize($apk));
            readfile($apk);
            exit;
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'APK not found']);
        }
        break;
        
    case 'test_matrix_connection':
        $url = $settings['server']['matrix_url'] ?? '';
        $test = rtrim($url, '/') . '/_matrix/client/versions';
        $ch = curl_init($test);
        curl_setopt_array($ch, [CURLOPT_TIMEOUT => 10, CURLOPT_RETURNTRANSFER => true, CURLOPT_SSL_VERIFYPEER => false]);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        echo json_encode(['success' => $code === 200, 'http_code' => $code, 'url' => $test]);
        break;
        
    default:
        echo json_encode(['error' => 'Unknown action', 'available' => [
            'get_settings','update_settings','list_variants','get_variant','save_variant',
            'list_features','toggle_feature','trigger_build','build_logs','download_apk','test_matrix_connection'
        ]]);
}
PHPEOF

# 🎨 Веб-панель (современная, адаптивная, расширяемая)
cat > /var/www/$BUILD_DOMAIN/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>🎛️ Safarali Builder</title>
  <style>
    :root{--bg:#0a0a14;--card:rgba(255,255,255,.05);--border:rgba(255,255,255,.1);--primary:#a855f7;--accent:#06b6d4;--text:#fff;--muted:rgba(255,255,255,.6)}
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text);min-height:100vh;line-height:1.5}
    .container{max-width:1400px;margin:0 auto;padding:1.5rem}
    header{display:flex;justify-content:space-between;align-items:center;padding:1rem 0;border-bottom:1px solid var(--border);margin-bottom:2rem;flex-wrap:wrap;gap:1rem}
    .logo{font-size:1.4rem;font-weight:800;background:linear-gradient(135deg,var(--primary),var(--accent));-webkit-background-clip:text;background-clip:text;color:transparent}
    .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:1.5rem}
    .card{background:var(--card);border:1px solid var(--border);border-radius:20px;padding:1.5rem}
    .card h3{color:var(--primary);margin-bottom:1rem;display:flex;align-items:center;gap:.5rem}
    .form-group{margin-bottom:1rem}
    .form-group label{display:block;font-size:.9rem;color:var(--muted);margin-bottom:.3rem}
    .form-group input,.form-group select,.form-group textarea{width:100%;padding:.6rem 1rem;border-radius:10px;border:1px solid var(--border);background:rgba(0,0,0,.3);color:#fff;font-size:1rem}
    .form-row{display:grid;grid-template-columns:1fr 1fr;gap:1rem}
    .btn{background:linear-gradient(135deg,var(--primary),var(--accent));border:none;padding:.7rem 1.5rem;border-radius:50px;color:#fff;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;gap:.5rem;transition:opacity.2s}
    .btn:hover{opacity:.9}.btn:disabled{opacity:.5;cursor:not-allowed}
    .btn-secondary{background:rgba(255,255,255,.1)}.btn-danger{background:rgba(239,68,68,.2);color:#ef4444}
    .log{background:#000;border-radius:12px;padding:1rem;font-family:monospace;font-size:.85rem;max-height:350px;overflow-y:auto;color:#4ade80;white-space:pre-wrap}
    .badge{display:inline-block;padding:.25rem .6rem;border-radius:20px;font-size:.8rem;background:rgba(34,197,94,.2);color:#22c55e}
    .badge.off{background:rgba(239,68,68,.2);color:#ef4444}
    .feature-item{display:flex;justify-content:space-between;align-items:center;padding:.5rem 0;border-bottom:1px dashed var(--border)}
    .feature-item:last-child{border-bottom:none}
    .toggle{position:relative;display:inline-block;width:44px;height:24px}
    .toggle input{opacity:0;width:0;height:0}
    .slider{position:absolute;cursor:pointer;top:0;left:0;right:0;bottom:0;background:#333;border-radius:24px;transition:.3s}
    .slider:before{position:absolute;content:"";height:18px;width:18px;left:3px;bottom:3px;background:#fff;border-radius:50%;transition:.3s}
    input:checked+.slider{background:var(--primary)}
    input:checked+.slider:before{transform:translateX(20px)}
    .variant-card{border:1px solid var(--border);border-radius:16px;padding:1rem;margin:.5rem 0;background:rgba(0,0,0,.2);cursor:pointer;transition:.2s}
    .variant-card:hover,.variant-card.active{border-color:var(--primary);background:rgba(168,85,247,.1)}
    @media(max-width:768px){.grid{grid-template-columns:1fr};.form-row{grid-template-columns:1fr};header{flex-direction:column;align-items:flex-start}}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="logo">🎛️ Safarali Builder</div>
      <div>
        <span class="badge" id="matrixStatus">Проверка...</span>
        <button class="btn btn-secondary" style="margin-left:.5rem" onclick="refreshAll()">🔄</button>
      </div>
    </header>
    
    <div class="grid">
      <!-- ⚙️ Основные настройки -->
      <div class="card">
        <h3>⚙️ Настройки</h3>
        <div class="form-group">
          <label>Matrix сервер URL</label>
          <input type="url" id="matrixUrl" placeholder="https://...">
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Версия приложения</label>
            <input type="text" id="appVersion" placeholder="1.0.0">
          </div>
          <div class="form-group">
            <label>Version Code</label>
            <input type="number" id="versionCode" placeholder="1">
          </div>
        </div>
        <div class="form-group">
          <label>Telegram Bot Token (уведомления)</label>
          <input type="text" id="tgToken" placeholder="123456:ABC-...">
        </div>
        <button class="btn" onclick="saveSettings()">💾 Сохранить</button>
        <button class="btn btn-secondary" onclick="testMatrix()">🔗 Проверить Matrix</button>
      </div>
      
      <!-- 🧩 Варианты приложения -->
      <div class="card">
        <h3>🧩 Варианты приложения</h3>
        <div id="variantsList"></div>
        <div style="margin-top:1rem">
          <button class="btn btn-secondary" onclick="showVariantEditor()">➕ Новый вариант</button>
        </div>
      </div>
      
      <!-- 🔌 Функции -->
      <div class="card">
        <h3>🔌 Функции</h3>
        <div id="featuresList"></div>
      </div>
      
      <!-- 🔨 Сборка -->
      <div class="card">
        <h3>🔨 Сборка</h3>
        <div class="form-group">
          <label>Выберите вариант</label>
          <select id="buildVariant"><option value="default">Default</option></select>
        </div>
        <button class="btn" id="buildBtn" onclick="triggerBuild()">🚀 Запустить сборку</button>
        <button class="btn btn-secondary" onclick="downloadAPK()">📥 Скачать APK</button>
        <div style="margin-top:1rem;font-size:.9rem">
          <div>📦 APK: <span id="apkInfo">-</span></div>
          <div>🕐 Последняя: <span id="lastBuild">-</span></div>
        </div>
        <div class="log" id="buildLog">Ожидание...</div>
      </div>
    </div>
  </div>

  <script>
    const API = '/api/index.php';
    const SECRET = localStorage.getItem('builder_secret') || prompt('🔑 API Secret (из настроек сервера):');
    if(SECRET) localStorage.setItem('builder_secret', SECRET);
    
    async function api(action, method='GET', body=null) {
      const opts = {method, headers: {'Content-Type':'application/json','X-API-Secret':SECRET}};
      if(body) opts.body = JSON.stringify(body);
      const res = await fetch(`${API}?action=${action}`, opts);
      return res.json();
    }
    
    async function loadSettings() {
      const r = await api('get_settings');
      if(r.success) {
        const s = r.settings;
        document.getElementById('matrixUrl').value = s.server?.matrix_url || '';
        document.getElementById('appVersion').value = s.app?.version?.name || '1.0.0';
        document.getElementById('versionCode').value = s.app?.version?.code || 1;
        document.getElementById('tgToken').value = s.output?.telegram_bot_token || '';
      }
    }
    
    async function saveSettings() {
      const settings = {
        server: {matrix_url: document.getElementById('matrixUrl').value},
        app: {version: {name: document.getElementById('appVersion').value, code: +document.getElementById('versionCode').value}},
        output: {telegram_bot_token: document.getElementById('tgToken').value}
      };
      const r = await api('update_settings', 'POST', settings);
      alert(r.success ? '✅ Сохранено' : '❌ '+r.error);
    }
    
    async function testMatrix() {
      const btn = event.target;
      btn.disabled = true;
      const r = await api('test_matrix_connection');
      const el = document.getElementById('matrixStatus');
      if(r.success) { el.textContent='🟢 Online'; el.className='badge'; }
      else { el.textContent=`🔴 ${r.http_code||'Error'}`; el.className='badge off'; }
      btn.disabled = false;
    }
    
    async function loadVariants() {
      const r = await api('list_variants');
      const list = document.getElementById('variantsList');
      list.innerHTML = '';
      if(r.success) {
        r.variants.forEach(v => {
          const div = document.createElement('div');
          div.className = 'variant-card';
          div.innerHTML = `<strong>${v.name}</strong><br><small>${v.description}</small><br><span class="badge">${v.id}</span>`;
          div.onclick = () => editVariant(v.id);
          list.appendChild(div);
        });
        // Обновить селект сборки
        const sel = document.getElementById('buildVariant');
        sel.innerHTML = r.variants.map(v=>`<option value="${v.id}">${v.name}</option>`).join('');
      }
    }
    
    async function loadFeatures() {
      const r = await api('list_features');
      const list = document.getElementById('featuresList');
      list.innerHTML = '';
      if(r.success) {
        r.features.forEach(f => {
          const div = document.createElement('div');
          div.className = 'feature-item';
          div.innerHTML = `
            <div>
              <strong>${f.name}</strong><br>
              <small style="color:var(--muted)">${f.description}</small>
            </div>
            <label class="toggle">
              <input type="checkbox" ${f.enabled?'checked':''} onchange="toggleFeature('${f.id}',this.checked)">
              <span class="slider"></span>
            </label>
          `;
          list.appendChild(div);
        });
      }
    }
    
    async function toggleFeature(id, state) {
      const r = await api('toggle_feature', 'POST', {id, enabled: state});
      if(!r.success) alert('❌ '+r.error);
    }
    
    async function triggerBuild() {
      const variant = document.getElementById('buildVariant').value;
      const btn = document.getElementById('buildBtn');
      btn.disabled = true; btn.innerHTML = '🔄 Сборка...';
      document.getElementById('buildLog').textContent = '🚀 Запуск...';
      
      const r = await api('trigger_build', 'POST', {variant});
      if(r.success) {
        pollLogs(r.log);
      } else {
        alert('❌ '+r.error);
        btn.disabled = false; btn.innerHTML = '🚀 Запустить сборку';
      }
    }
    
    function pollLogs(logFile) {
      const interval = setInterval(async () => {
        const r = await api('build_logs');
        if(r.success) {
          document.getElementById('buildLog').textContent = r.logs || 'Нет данных';
          if(r.logs?.includes('🎉 Сборка завершена') || r.logs?.includes('❌')) {
            clearInterval(interval);
            document.getElementById('buildBtn').disabled = false;
            document.getElementById('buildBtn').innerHTML = '🚀 Запустить сборку';
            checkAPK();
          }
        }
      }, 4000);
    }
    
    async function downloadAPK() {
      window.location.href = `${API}?action=download_apk&secret=${SECRET}`;
    }
    
    async function checkAPK() {
      try {
        const res = await fetch('/downloads/app-release.apk', {method:'HEAD'});
        if(res.ok) {
          const size = res.headers.get('Content-Length');
          document.getElementById('apkInfo').textContent = size ? (size/1024/1024).toFixed(1)+' MB' : '-';
          document.getElementById('lastBuild').textContent = new Date().toLocaleString();
        }
      } catch(e) {}
    }
    
    function editVariant(id) {
      alert(`Редактирование варианта: ${id}\n\nФункция в разработке — используйте файлы в /opt/mobile-builder/config/variants/`);
    }
    
    function showVariantEditor() {
      alert(`Создание нового варианта:\n1. Скопируйте шаблон:\n   cp /opt/mobile-builder/config/variants/default.json /opt/mobile-builder/config/variants/myvariant.json\n2. Отредактируйте JSON\n3. Обновите панель`);
    }
    
    async function refreshAll() {
      await Promise.all([loadSettings(), loadVariants(), loadFeatures(), testMatrix(), checkAPK()]);
    }
    
    // Init
    loadSettings(); loadVariants(); loadFeatures(); testMatrix(); checkAPK();
    setInterval(() => { testMatrix(); checkAPK(); }, 60000);
  </script>
</body>
</html>
HTMLEOF

# Nginx конфигурация
cat > /etc/nginx/sites-available/$BUILD_DOMAIN << NGINXEOF
server {
    listen 80;
    server_name $BUILD_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $BUILD_DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$BUILD_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$BUILD_DOMAIN/privkey.pem;
    
    root /var/www/$BUILD_DOMAIN;
    index index.html;
    client_max_body_size 100M;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api/ {
        try_files \$uri \$uri/ /api/index.php?\$query_string;
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
    }
    
    location /downloads/ {
        alias /var/www/$BUILD_DOMAIN/downloads/;
        autoindex on;
        expires 1h;
    }
    
    location ~ /\. { deny all; }
    location ~ \.(env|credentials|json)$ { 
        location ~ /config/ { deny all; }
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/$BUILD_DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl reload nginx

print_success "Веб-панель: https://$BUILD_DOMAIN"

# ============================================
# 🤖 ФИНАЛ: АВТОЗАПУСК И ИНФОРМАЦИЯ
# ============================================
print_header "✅ УСТАНОВКА ЗАВЕРШЕНА!"

cat << FINAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 SAFARALI GROUP — BUILD SERVER READY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌐 ВЕБ-ПАНЕЛЬ:
   🔗 https://$BUILD_DOMAIN
   🔑 API Secret: $API_SECRET
   💾 Ключ подписи: /opt/mobile-builder/keystore/.credentials

🔗 ПОДКЛЮЧЕНИЕ К МАТРИКС:
   • Сервер: $MATRIX_SERVER_URL
   • Проверка: кнопка "Проверить Matrix" в панели
   • Настройка: ⚙️ Настройки → Matrix URL

📱 ГЕНЕРАЦИЯ ПРИЛОЖЕНИЯ:
   • Варианты: /opt/mobile-builder/config/variants/
   • Функции: /opt/mobile-builder/config/features/
   • Сборка: кнопка "Запустить сборку" или
     /opt/mobile-builder/builder.sh <variant>

📥 РЕЗУЛЬТАТ:
   • Локально: /opt/mobile-builder/output/
   • Публично: https://$BUILD_DOMAIN/downloads/app-release.apk

🧩 ДОБАВЛЕНИЕ НОВОЙ ФУНКЦИИ:
   1. Создайте файл: /opt/mobile-builder/config/features/my_feature.json
   2. Опишите schema, plugins, gradle_config
   3. Включите в панели: 🔌 Функции → переключатель
   4. Пересоберите приложение

🔄 АВТОМАТИЗАЦИЯ:
   • Webhook: настройте server.webhook_url для уведомлений
   • Telegram: укажите token и chat_id для оповещений
   • CI/CD: вызывайте API: POST /api?action=trigger_build

🔐 БЕЗОПАСНОСТЬ:
   • Все запросы к API требуют заголовок: X-API-Secret
   • Не передавайте секрет в URL (логируются!)
   • Регулярно делайте бэкап: /opt/mobile-builder/keystore/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINAL

print_success "Откройте панель и начните генерацию! 🎉"