#!/bin/bash

# ============================================
# SAFARALI GROUP - CLEAN BUILD SERVER
# Чистая установка, только рабочие компоненты
# ============================================

set -e

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Конфигурация
DOMAIN="build.safaraligroup.uz"
API_TOKEN="safarali_$(openssl rand -hex 12)"

print_info "Начинаем чистую установку сервера сборки..."
print_info "Домен: $DOMAIN"
print_info "API токен: $API_TOKEN"

# ============================================
# 1. ОБНОВЛЕНИЕ СИСТЕМЫ
# ============================================
apt update && apt upgrade -y
apt install -y curl wget git unzip zip nginx build-essential

# ============================================
# 2. УСТАНОВКА NODE.JS 20
# ============================================
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g cordova

# ============================================
# 3. УСТАНОВКА PHP
# ============================================
apt install -y php8.1-fpm php8.1-cli
systemctl enable php8.1-fpm
systemctl start php8.1-fpm

# ============================================
# 4. СОЗДАНИЕ ВЕБ-ПАНЕЛИ
# ============================================
mkdir -p /var/www/$DOMAIN
mkdir -p /var/www/$DOMAIN/downloads

cat > /var/www/$DOMAIN/index.html << 'EOF'
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
        }
        .card {
            background: rgba(255,255,255,0.05);
            border-radius: 32px;
            padding: 40px;
            text-align: center;
            max-width: 500px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .logo {
            font-size: 2rem;
            font-weight: 800;
            background: linear-gradient(135deg, #a855f7, #06b6d4);
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
            margin-bottom: 20px;
        }
        .server {
            background: rgba(0,0,0,0.3);
            padding: 12px;
            border-radius: 20px;
            margin: 20px 0;
        }
        .btn {
            display: inline-block;
            background: linear-gradient(135deg, #a855f7, #06b6d4);
            padding: 14px 28px;
            border-radius: 60px;
            color: white;
            text-decoration: none;
            font-weight: bold;
            margin-top: 20px;
        }
        .status {
            color: #22c55e;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="logo">✨ Safarali Group</div>
        <h1>Безопасный мессенджер</h1>
        <div class="server">
            🔗 Сервер: <strong>safaraligroup.uz</strong>
        </div>
        <p>Скачайте приложение и начните общение</p>
        <div id="downloadLink">
            <a href="#" class="btn" id="apkBtn">📱 Загрузка...</a>
        </div>
        <p class="status" id="statusMsg">⚡ Проверка...</p>
    </div>
    <script>
        async function checkAPK() {
            const response = await fetch('/downloads/safarali-app.apk', { method: 'HEAD' });
            const btn = document.getElementById('apkBtn');
            const status = document.getElementById('statusMsg');
            if (response.ok) {
                btn.href = '/downloads/safarali-app.apk';
                btn.innerHTML = '📥 Скачать APK';
                status.innerHTML = '✅ Приложение готово к скачиванию';
                status.style.color = '#22c55e';
            } else {
                btn.innerHTML = '⏳ Приложение собирается...';
                status.innerHTML = '🔄 Подождите 5-10 минут, приложение собирается';
                status.style.color = '#f59e0b';
                setTimeout(checkAPK, 10000);
            }
        }
        checkAPK();
    </script>
</body>
</html>
EOF

# ============================================
# 5. СОЗДАНИЕ ПРОСТОГО APK
# ============================================
cd /root
cordova create SafaraliApp uz.safarali.group "Safarali Group"
cd SafaraliApp
cordova platform add android

cat > www/index.html << 'EOF'
<!DOCTYPE html>
<html>
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
        }
        .card {
            background: rgba(255,255,255,0.05);
            border-radius: 32px;
            padding: 40px;
            text-align: center;
            max-width: 500px;
        }
        .logo { font-size: 2rem; font-weight: 800; background: linear-gradient(135deg, #a855f7, #06b6d4); -webkit-background-clip: text; background-clip: text; color: transparent; }
        .server { background: rgba(0,0,0,0.3); padding: 12px; border-radius: 20px; margin: 20px 0; }
        .btn { display: inline-block; background: linear-gradient(135deg, #a855f7, #06b6d4); padding: 14px 28px; border-radius: 60px; color: white; text-decoration: none; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <div class="logo">✨ Safarali Group</div>
        <h1>Безопасный мессенджер</h1>
        <div class="server">🔗 Сервер: <strong>safaraligroup.uz</strong></div>
        <p>При регистрации укажите сервер: <strong>safaraligroup.uz</strong></p>
        <a href="https://play.google.com/store/apps/details?id=de.spiritcroc.riotx" class="btn">📱 Google Play</a>
    </div>
</body>
</html>
EOF

cordova build android --release

# Копирование APK
cp platforms/android/app/build/outputs/apk/release/app-release.apk /var/www/$DOMAIN/downloads/safarali-app.apk

# ============================================
# 6. НАСТРОЙКА NGINX
# ============================================
cat > /etc/nginx/sites-available/$DOMAIN << EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/$DOMAIN;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
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
# 7. АВТОМАТИЧЕСКАЯ ПЕРЕСБОРКА
# ============================================
cat > /usr/local/bin/rebuild-app.sh << 'EOF'
#!/bin/bash
cd /root/SafaraliApp
cordova build android --release
cp platforms/android/app/build/outputs/apk/release/app-release.apk /var/www/build.safaraligroup.uz/downloads/safarali-app.apk
echo "$(date): Пересборка завершена" >> /var/www/build.safaraligroup.uz/logs/rebuild.log
EOF

chmod +x /usr/local/bin/rebuild-app.sh
mkdir -p /var/www/$DOMAIN/logs
echo "0 3 * * * /usr/local/bin/rebuild-app.sh" | crontab -

# ============================================
# ФИНАЛЬНАЯ ИНФОРМАЦИЯ
# ============================================
print_success "Установка завершена!"
echo ""
echo "========================================="
echo "СЕРВЕР СБОРКИ ГОТОВ"
echo "========================================="
echo ""
echo "🌐 Веб-панель: http://$DOMAIN"
echo "📱 APK: http://$DOMAIN/downloads/safarali-app.apk"
echo ""
echo "🔑 API токен (для справки): $API_TOKEN"
echo ""
echo "Приложение автоматически подключается к safaraligroup.uz"
echo "========================================="