#!/bin/bash

# ============================================
# SAFARALI GROUP - FULL AUTO BUILD SERVER
# Веб-панель + Автосборка + Мессенджер
# ============================================

set -e

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_header() { echo ""; echo -e "${YELLOW}=========================================${NC}"; echo -e "${GREEN}$1${NC}"; echo -e "${YELLOW}=========================================${NC}"; }

# Конфигурация
DOMAIN="build.safaraligroup.uz"
API_TOKEN="safarali_$(openssl rand -hex 12)"

print_header "🚀 SAFARALI GROUP - ПОЛНЫЙ СЕРВЕР СБОРКИ"
print_info "Домен: $DOMAIN"
print_info "API токен: $API_TOKEN"

# ============================================
# 1. УДАЛЕНИЕ СТАРОГО NODE.JS И ОБНОВЛЕНИЕ
# ============================================
print_header "📦 ШАГ 1/8: ПОДГОТОВКА СИСТЕМЫ"

# Удаление старого Node.js
apt remove --purge -y nodejs npm nodejs-doc libnode-dev libnode72 2>/dev/null || true
apt autoremove -y
rm -rf /usr/lib/node_modules /usr/share/node /usr/include/node /usr/local/lib/node_modules
rm -f /etc/apt/sources.list.d/nodesource.list
apt update
apt --fix-broken install -y

# Установка базовых пакетов
apt install -y curl wget git unzip zip nginx openjdk-17-jdk

# ============================================
# 2. УСТАНОВКА NODE.JS 20
# ============================================
print_header "📦 ШАГ 2/8: УСТАНОВКА NODE.JS 20"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g cordova

# ============================================
# 3. УСТАНОВКА ANDROID SDK
# ============================================
print_header "🤖 ШАГ 3/8: УСТАНОВКА ANDROID SDK"
mkdir -p /root/Android/Sdk/cmdline-tools
cd /root/Android/Sdk/cmdline-tools
wget -q --show-progress https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-11076708_latest.zip
rm commandlinetools-linux-11076708_latest.zip
mv cmdline-tools latest
cd latest
yes | ./bin/sdkmanager --licenses > /dev/null 2>&1
./bin/sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" > /dev/null 2>&1

export ANDROID_HOME=/root/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools
cat >> /root/.bashrc << 'EOF'
export ANDROID_HOME=/root/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools
EOF
source /root/.bashrc

# ============================================
# 4. СОЗДАНИЕ ПРИЛОЖЕНИЯ
# ============================================
print_header "📱 ШАГ 4/8: СОЗДАНИЕ ПРИЛОЖЕНИЯ"
cd /root
rm -rf SafaraliApp
cordova create SafaraliApp uz.safarali.group "Safarali Group"
cd SafaraliApp
cordova platform add android

cat > www/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Safarali Group</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0a0a0f 0%, #1a1a2e 100%);
            color: #fff;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .card {
            background: rgba(255,255,255,0.05);
            backdrop-filter: blur(10px);
            border-radius: 40px;
            padding: 40px;
            text-align: center;
            max-width: 500px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .logo {
            font-size: 2.5rem;
            font-weight: 800;
            background: linear-gradient(135deg, #a855f7, #06b6d4);
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
        }
        .server {
            background: rgba(0,0,0,0.3);
            padding: 12px;
            border-radius: 20px;
            margin: 20px 0;
        }
        .features {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 10px;
            margin: 20px 0;
        }
        .feature {
            background: rgba(255,255,255,0.03);
            padding: 8px;
            border-radius: 12px;
            font-size: 0.8rem;
        }
        .btn {
            display: inline-block;
            background: linear-gradient(135deg, #a855f7, #06b6d4);
            padding: 12px 28px;
            border-radius: 60px;
            color: white;
            text-decoration: none;
            font-weight: bold;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="logo">✨ Safarali Group</div>
        <h1>Безопасный мессенджер</h1>
        <div class="server">🔗 Сервер: <strong>safaraligroup.uz</strong></div>
        <div class="features">
            <div class="feature">🔒 Сквозное шифрование</div>
            <div class="feature">🎥 Видеозвонки HD</div>
            <div class="feature">💬 Голосовые сообщения</div>
            <div class="feature">📁 Обмен файлами</div>
        </div>
        <a href="https://play.google.com/store/apps/details?id=de.spiritcroc.riotx" class="btn">📱 Google Play</a>
        <p style="margin-top: 20px; font-size: 0.7rem;">При регистрации укажите: <strong>safaraligroup.uz</strong></p>
    </div>
</body>
</html>
EOF

# ============================================
# 5. СБОРКА APK
# ============================================
print_header "🔨 ШАГ 5/8: СБОРКА APK"
cordova build android --release -- --packageType=apk

# ============================================
# 6. СОЗДАНИЕ ВЕБ-ПАНЕЛИ
# ============================================
print_header "🌐 ШАГ 6/8: СОЗДАНИЕ ВЕБ-ПАНЕЛИ"

mkdir -p /var/www/$DOMAIN
mkdir -p /var/www/$DOMAIN/api
mkdir -p /var/www/$DOMAIN/downloads
mkdir -p /var/www/$DOMAIN/logs

# Копирование APK
cp platforms/android/app/build/outputs/apk/release/app-release-unsigned.apk /var/www/$DOMAIN/downloads/safarali-app.apk 2>/dev/null || true

# API
cat > /var/www/$DOMAIN/api/index.php << EOF
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

\$token = \$_GET['token'] ?? '';
if (\$token !== '$API_TOKEN') {
    http_response_code(401);
    echo json_encode(['error' => 'Unauthorized']);
    exit;
}

\$action = \$_GET['action'] ?? '';

if (\$action === 'rebuild') {
    \$log = '/var/www/$DOMAIN/logs/rebuild_' . date('Y-m-d_H-i-s') . '.log';
    \$cmd = "cd /root/SafaraliApp && cordova build android --release -- --packageType=apk > \$log 2>&1 && cp platforms/android/app/build/outputs/apk/release/app-release-unsigned.apk /var/www/$DOMAIN/downloads/safarali-app.apk &";
    exec(\$cmd);
    echo json_encode(['success' => true, 'message' => 'Сборка запущена']);

} elseif (\$action === 'status') {
    \$logs = glob('/var/www/$DOMAIN/logs/rebuild_*.log');
    rsort(\$logs);
    \$lastLog = \$logs[0] ?? null;
    \$output = \$lastLog ? file_get_contents(\$lastLog) : '';
    echo json_encode(['output' => substr(\$output, -2000)]);

} elseif (\$action === 'download') {
    \$file = '/var/www/$DOMAIN/downloads/safarali-app.apk';
    if (file_exists(\$file)) {
        header('Content-Type: application/vnd.android.package-archive');
        header('Content-Disposition: attachment; filename="safarali-app.apk"');
        readfile(\$file);
    } else {
        echo json_encode(['error' => 'APK not found']);
    }
} else {
    echo json_encode(['error' => 'Invalid action']);
}
EOF

# Веб-панель
cat > /var/www/$DOMAIN/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Safarali Group - Admin Panel</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0a0a0f 0%, #1a1a2e 100%);
            color: #fff;
            min-height: 100vh;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        .header {
            text-align: center;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .logo { font-size: 1.8rem; font-weight: 800; background: linear-gradient(135deg, #a855f7, #06b6d4); -webkit-background-clip: text; background-clip: text; color: transparent; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 2rem; }
        .card {
            background: rgba(255,255,255,0.05);
            border-radius: 24px;
            padding: 1.5rem;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .card h2 { margin-bottom: 1rem; color: #a855f7; }
        .btn {
            background: linear-gradient(135deg, #a855f7, #06b6d4);
            border: none;
            padding: 10px 20px;
            border-radius: 50px;
            color: white;
            font-weight: 600;
            cursor: pointer;
            margin-right: 1rem;
            margin-top: 1rem;
        }
        .btn-success { background: linear-gradient(135deg, #22c55e, #16a34a); }
        .log-output {
            background: #0a0a0f;
            border-radius: 16px;
            padding: 1rem;
            font-family: monospace;
            font-size: 0.8rem;
            max-height: 300px;
            overflow-y: auto;
            color: #4ade80;
            margin-top: 1rem;
        }
        .info-box {
            background: rgba(0,0,0,0.3);
            border-radius: 16px;
            padding: 1rem;
            margin-top: 1rem;
        }
        .download-link {
            background: rgba(168,85,247,0.2);
            padding: 1rem;
            border-radius: 16px;
            text-align: center;
            margin-top: 1rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">🎛️ Safarali Group Admin Panel</div>
            <p>Управление сборкой мобильного приложения</p>
        </div>
        <div class="grid">
            <div class="card">
                <h2>📱 Управление сборкой</h2>
                <button class="btn" onclick="rebuildApp()">🔨 Пересобрать APK</button>
                <button class="btn btn-success" onclick="downloadAPK()">📥 Скачать APK</button>
                <div class="info-box">
                    <div>📦 Размер APK: <span id="apkSize">-</span></div>
                    <div>📅 Последняя сборка: <span id="lastBuild">-</span></div>
                </div>
                <div id="buildLog" class="log-output">Ожидание...</div>
            </div>
            <div class="card">
                <h2>⚙️ Настройки приложения</h2>
                <div class="info-box">
                    <p><strong>Matrix сервер:</strong> safaraligroup.uz</p>
                    <p><strong>Версия приложения:</strong> 1.0</p>
                </div>
                <div class="download-link">
                    <p>🔗 Ссылка для пользователей:</p>
                    <code id="downloadUrl">https://build.safaraligroup.uz/downloads/safarali-app.apk</code>
                    <button class="btn" onclick="copyUrl()">📋 Копировать</button>
                </div>
            </div>
        </div>
        <div class="card" style="margin-top: 2rem;">
            <h2>📊 Инструкция для пользователей</h2>
            <ol style="margin-left: 1.5rem; color: rgba(255,255,255,0.8);">
                <li>Скачайте APK по ссылке выше</li>
                <li>Установите приложение на телефон</li>
                <li>При регистрации укажите сервер: <code>https://safaraligroup.uz</code></li>
            </ol>
        </div>
    </div>
    <script>
        const API_TOKEN = prompt('🔑 Введите API токен (в /root/api_token.txt)');
        async function apiCall(action) {
            const res = await fetch(`/api/index.php?action=${action}&token=${API_TOKEN}`);
            return res.json();
        }
        async function rebuildApp() {
            document.getElementById('buildLog').innerHTML = '🔄 Сборка запущена...';
            const result = await apiCall('rebuild');
            if(result.success) alert('Сборка запущена! Ожидайте 5-10 минут.');
            checkStatus();
        }
        async function downloadAPK() {
            window.location.href = `/api/index.php?action=download&token=${API_TOKEN}`;
        }
        async function checkStatus() {
            const result = await apiCall('status');
            document.getElementById('buildLog').textContent = result.output || 'Нет данных';
            const sizeRes = await fetch('/downloads/safarali-app.apk', { method: 'HEAD' });
            const size = sizeRes.headers.get('Content-Length');
            if(size) {
                document.getElementById('apkSize').innerHTML = (size / 1024 / 1024).toFixed(2) + ' MB';
                document.getElementById('lastBuild').innerHTML = new Date().toLocaleString();
            }
        }
        function copyUrl() {
            navigator.clipboard.writeText(document.getElementById('downloadUrl').innerText);
            alert('✅ Ссылка скопирована!');
        }
        setInterval(checkStatus, 10000);
        checkStatus();
    </script>
</body>
</html>
EOF

# ============================================
# 7. НАСТРОЙКА PHP И NGINX
# ============================================
print_header "🔧 ШАГ 7/8: НАСТРОЙКА PHP И NGINX"

# Установка PHP
apt install -y php8.1-fpm php8.1-cli 2>/dev/null || apt install -y php8.3-fpm php8.3-cli

# Конфигурация Nginx
cat > /etc/nginx/sites-available/$DOMAIN << EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/$DOMAIN;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api/ {
        try_files \$uri \$uri/ /api/index.php;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
    }
    
    location /downloads/ {
        alias /var/www/$DOMAIN/downloads/;
        expires 30d;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# ============================================
# 8. АВТОМАТИЧЕСКАЯ ПЕРЕСБОРКА
# ============================================
print_header "🤖 ШАГ 8/8: АВТОМАТИЧЕСКАЯ ПЕРЕСБОРКА"

cat > /usr/local/bin/auto-rebuild.sh << 'EOF'
#!/bin/bash
cd /root/SafaraliApp
cordova build android --release -- --packageType=apk
cp platforms/android/app/build/outputs/apk/release/app-release-unsigned.apk /var/www/build.safaraligroup.uz/downloads/safarali-app.apk
echo "$(date): Автосборка завершена" >> /var/www/build.safaraligroup.uz/logs/auto.log
EOF

chmod +x /usr/local/bin/auto-rebuild.sh
echo "0 3 * * * /usr/local/bin/auto-rebuild.sh" | crontab -

# ============================================
# ФИНАЛЬНАЯ ИНФОРМАЦИЯ
# ============================================
cat > /root/api_token.txt << EOF
=========================================
SAFARALI GROUP - ADMIN PANEL
=========================================

🌐 Админ-панель: http://$DOMAIN
🔑 API Токен: $API_TOKEN
📱 APK: http://$DOMAIN/downloads/safarali-app.apk

Функции:
- Пересборка APK одной кнопкой
- Просмотр логов сборки
- Скачивание готового APK
- Автосборка ежедневно в 3:00

=========================================
EOF

print_header "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo ""
echo "========================================="
echo -e "${GREEN}СЕРВЕР СБОРКИ SAFARALI GROUP УСТАНОВЛЕН!${NC}"
echo "========================================="
echo ""
echo "🌐 АДМИН-ПАНЕЛЬ: http://$DOMAIN"
echo "🔑 API ТОКЕН: $API_TOKEN"
echo "   Сохранен в: /root/api_token.txt"
echo ""
echo "📱 ССЫЛКА ДЛЯ ПОЛЬЗОВАТЕЛЕЙ:"
echo "   http://$DOMAIN/downloads/safarali-app.apk"
echo ""
echo "🤖 АВТОМАТИЧЕСКАЯ ПЕРЕСБОРКА: ежедневно в 3:00"
echo ""
echo "========================================="
echo -e "${GREEN}🚀 ГОТОВО! ОТКРОЙТЕ АДМИН-ПАНЕЛЬ!${NC}"