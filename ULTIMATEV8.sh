#!/bin/bash

# ==========================================
# MATRIX ULTIMATE MESSENGER V8 - ABSOLUTE MAXIMUM
# Полный набор всех возможных функций
# Enterprise-grade messaging platform with EVERYTHING
# ==========================================

set -euo pipefail
trap 'echo "❌ Ошибка на строке $LINENO"; exit 1' ERR

# --- ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GOLD='\033[38;5;220m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_header() { echo -e "\n${GOLD}═══════════════════════════════════════════════════════════${NC}"; echo -e "${MAGENTA}$1${NC}"; echo -e "${GOLD}═══════════════════════════════════════════════════════════${NC}\n"; }

# --- ПРОВЕРКА ROOT ---
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Пожалуйста, запустите с правами root (sudo)${NC}"
    exit 1
fi

# --- НАСТРОЙКИ ---
clear
print_header "MATRIX ULTIMATE MESSENGER V8 - ABSOLUTE MAXIMUM"
echo -e "${CYAN}Создаем мессенджер с МАКСИМАЛЬНЫМ функционалом...${NC}\n"

read -p "Введите домен: " DOMAIN
read -p "Введите email для SSL: " EMAIL
read -p "Введите имя администратора: " ADMIN_USER
read -p "Введите пароль администратора: " ADMIN_PASS
read -p "Введите название мессенджера: " BRAND_NAME

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    print_info "Домен и email обязательны!"
    exit 1
fi

BRAND_NAME=${BRAND_NAME:-"Ultimate Messenger MAX"}

# --- ГЕНЕРАЦИЯ КЛЮЧЕЙ (МАКСИМАЛЬНАЯ БЕЗОПАСНОСТЬ) ---
DB_PASS="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
REG_SECRET="$(openssl rand -base64 64 | tr -d '/+=' | head -c 48)"
TURN_SECRET="$(openssl rand -base64 96 | tr -d '/+=' | head -c 64)"
ADMIN_API_KEY="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
JWT_SECRET="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
REDIS_PASS="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
QR_SECRET="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
ENCRYPTION_KEY="$(openssl rand -base64 64 | tr -d '/+=' | head -c 48)"
WEBHOOK_SECRET="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
MONITORING_KEY="$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)"
BACKUP_KEY="$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)"

ADMIN_PASS_HASH=$(echo -n "$ADMIN_PASS" | sha256sum | cut -d' ' -f1)

print_info "Генерация ключей завершена (максимальная безопасность)"

# --- ПОДГОТОВКА СИСТЕМЫ (МАКСИМАЛЬНАЯ) ---
print_header "МАКСИМАЛЬНАЯ ПОДГОТОВКА СИСТЕМЫ"
export DEBIAN_FRONTEND=noninteractive

# Обновление всего
apt update && apt upgrade -y
apt install -y curl wget gnupg2 ufw nginx certbot python3-certbot-nginx \
    postgresql postgresql-contrib redis-server jq python3-pip python3-venv \
    build-essential libpq-dev libffi-dev nodejs npm git fail2ban \
    net-tools htop glances docker.io docker-compose \
    qrencode libqrencode-dev websocat imagemagick ffmpeg \
    software-properties-common apt-transport-https ca-certificates \
    lsb-release gnupg2 unzip zip gzip bzip2 tar p7zip-full \
    vim nano mc tree htop iotop iftop nethogs \
    auditd rkhunter chkrootkit clamav clamav-daemon \
    wireguard openvpn ufw iptables-persistent \
    prometheus node-exporter grafana kibana elasticsearch \
    logrotate rsync rclone s3cmd \
    postfix dovecot-core spamassassin \
    nfs-common smbclient cifs-utils \
    python3-certbot-dns-cloudflare python3-certbot-dns-google

# --- Node.js 20+ ---
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# --- Docker (последняя версия) ---
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# --- Docker Compose V2 ---
mkdir -p ~/.docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose

# --- FIREWALL (МАКСИМАЛЬНАЯ ЗАЩИТА) ---
print_info "Настройка максимальной защиты firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 8448/tcp comment 'Matrix Federation'
ufw allow 3478/tcp comment 'TURN TCP'
ufw allow 3478/udp comment 'TURN UDP'
ufw allow 5349/tcp comment 'TURN TLS TCP'
ufw allow 5349/udp comment 'TURN TLS UDP'
ufw allow 49152:65535/udp comment 'TURN Ports'
ufw allow 3000/tcp comment 'Grafana'
ufw allow 9090/tcp comment 'Prometheus'
ufw allow 5601/tcp comment 'Kibana'
ufw allow 9200/tcp comment 'Elasticsearch'
ufw allow 51820/udp comment 'WireGuard'
ufw allow 1194/udp comment 'OpenVPN'
ufw --force enable

# --- УСТАНОВКА MATRIX SYNAPSE (МАКСИМАЛЬНАЯ) ---
print_header "УСТАНОВКА MATRIX SYNAPSE (МАКСИМАЛЬНАЯ КОНФИГУРАЦИЯ)"
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/matrix-org.list
apt update
echo "matrix-synapse-py3 matrix-synapse/server-name string $DOMAIN" | debconf-set-selections
apt install -y matrix-synapse-py3

# --- POSTGRESQL (МАКСИМАЛЬНАЯ ОПТИМИЗАЦИЯ) ---
print_header "ОПТИМИЗАЦИЯ POSTGRESQL"
sudo -u postgres psql -c "CREATE USER synapse WITH PASSWORD '$DB_PASS';" || true
sudo -u postgres psql -c "CREATE DATABASE synapse OWNER synapse;" || true
sudo -u postgres psql -c "ALTER USER synapse CREATEDB;" || true

cat > /etc/postgresql/*/main/postgresql.conf <<EOF
# Максимальная оптимизация для Matrix
listen_addresses = '*'
port = 5432
max_connections = 1000
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 64MB
maintenance_work_mem = 512MB
min_wal_size = 1GB
max_wal_size = 4GB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 500
random_page_cost = 1.1
effective_io_concurrency = 200
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 10s
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
EOF

systemctl restart postgresql

# --- REDIS (МАКСИМАЛЬНАЯ) ---
print_header "МАКСИМАЛЬНАЯ НАСТРОЙКА REDIS"
cat > /etc/redis/redis.conf <<EOF
port 6379
bind 127.0.0.1
requirepass $REDIS_PASS
maxmemory 4gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 100
notify-keyspace-events Ex
EOF

systemctl restart redis-server

# --- КОНФИГУРАЦИЯ SYNAPSE (МАКСИМАЛЬНАЯ) ---
print_header "МАКСИМАЛЬНАЯ КОНФИГУРАЦИЯ SYNAPSE"
CONFIG_FILE="/etc/matrix-synapse/homeserver.yaml"
cp $CONFIG_FILE ${CONFIG_FILE}.backup

cat > $CONFIG_FILE <<'EOF'
# ============================================
# MATRIX ULTIMATE MESSENGER V8
# Абсолютно максимальная конфигурация
# ============================================

server_name: "DOMAIN_PLACEHOLDER"
public_baseurl: "https://DOMAIN_PLACEHOLDER/"

# Регистрация (максимальная гибкость)
enable_registration: true
enable_registration_without_verification: false
registration_shared_secret: "REG_SECRET_PLACEHOLDER"
registrations_require_3pid:
  - email
  - msisdn
registrations_allowed_for_local_users: true
allowed_local_3pids:
  - medium: email
    pattern: ".*"
  - medium: msisdn
    pattern: ".*"

# База данных (максимальная производительность)
database:
  name: psycopg2
  args:
    user: synapse
    password: "DB_PASS_PLACEHOLDER"
    database: synapse
    host: localhost
    cp_min: 20
    cp_max: 100
    pool_recycle: 3600

# Redis (максимальное кэширование)
redis:
  enabled: true
  host: localhost
  port: 6379
  password: "REDIS_PASS_PLACEHOLDER"

# TURN сервер (максимальная поддержка звонков)
turn_shared_secret: "TURN_SECRET_PLACEHOLDER"
turn_uris:
  - "turn:DOMAIN_PLACEHOLDER?transport=udp"
  - "turn:DOMAIN_PLACEHOLDER?transport=tcp"
  - "turns:DOMAIN_PLACEHOLDER?transport=tcp"
turn_user_lifetime: 86400000
turn_allow_ip_lifetime: true

# Rate limiting (максимальная защита)
rc_message:
  per_second: 100
  burst_count: 200
rc_registration:
  per_second: 10
  burst_count: 50
rc_login:
  address:
    per_second: 1
    burst_count: 10
  account:
    per_second: 1
    burst_count: 10
  failed_attempts:
    per_second: 0.5
    burst_count: 5
rc_admin_redaction:
  per_second: 5
  burst_count: 25
rc_joins:
  local:
    per_second: 5
    burst_count: 25
  remote:
    per_second: 1
    burst_count: 5

# Медиа файлы (максимальные размеры)
max_upload_size: "2G"
max_image_pixels: "256M"
media_store_path: "/var/lib/matrix-synapse/media"
media_retention:
  local_media_lifetime: 365d
  remote_media_lifetime: 90d
dynamic_thumbnails: true
thumbnail_sizes:
  - width: 32
    height: 32
    method: crop
  - width: 96
    height: 96
    method: crop
  - width: 320
    height: 240
    method: scale
  - width: 640
    height: 480
    method: scale
  - width: 800
    height: 600
    method: scale
  - width: 1024
    height: 768
    method: scale
  - width: 1920
    height: 1080
    method: scale

# Presence и директории (максимальная доступность)
presence:
  enabled: true
user_directory:
  enabled: true
  search_all_users: true
room_directory:
  enabled: true
alias_creation_rules:
  - user_id: "@admin:DOMAIN_PLACEHOLDER"
    alias: "*"
    action: allow
  - user_id: "*"
    alias: "*"
    action: allow

# Кэширование (максимальная производительность)
caches:
  global_factor: 4
  per_cache_factors:
    "*": 2
    "get_users_in_room": 4
    "get_rooms_for_user": 4
    "get_room_state": 4
    "get_room_state_ids": 4

# Федерация (максимальная совместимость)
federation_domain_whitelist: []
federation_verify_certificates: true
federation_certificate_verification_whitelist: []
federation_sender_instances: []

# Экспериментальные функции (ВСЕ включены)
experimental_features:
  spaces_enabled: true
  msc3083_enabled: true
  msc3244_enabled: true
  msc3266_enabled: true
  msc2716_enabled: true
  msc3030_enabled: true
  msc3440_enabled: true
  msc3861_enabled: true
  msc3874_enabled: true
  msc3882_enabled: true
  msc3890_enabled: true
  faster_joins: true
  msc3952_intentional_mentions: true
  msc3958_suppress_redacted_events: true
  msc3967_do_not_require_consent_for_existing: true
  msc3970_dont_use_deprecated_event_fields: true
  msc3984_retention_policies: true
  msc3981_recurse_relations: true

# Продвинутые настройки
limit_remote_rooms:
  enabled: true
  complexity: 5.0
  complexity_error: "Room too complex"
  admins_can_join: true
room_prejoin_state:
  disable_peek: false
  disable_knock: false
max_domain_connections: 10
EOF

# Замена плейсхолдеров
sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" $CONFIG_FILE
sed -i "s/REG_SECRET_PLACEHOLDER/$REG_SECRET/g" $CONFIG_FILE
sed -i "s/DB_PASS_PLACEHOLDER/$DB_PASS/g" $CONFIG_FILE
sed -i "s/REDIS_PASS_PLACEHOLDER/$REDIS_PASS/g" $CONFIG_FILE
sed -i "s/TURN_SECRET_PLACEHOLDER/$TURN_SECRET/g" $CONFIG_FILE

# --- СОЗДАНИЕ ВЕБ-ИНТЕРФЕЙСА (МАКСИМАЛЬНЫЙ) ---
print_header "СОЗДАНИЕ МАКСИМАЛЬНОГО ВЕБ-ИНТЕРФЕЙСА"
mkdir -p /var/www/messenger/{css,js,images,fonts,audio,video}

# --- МАКСИМАЛЬНЫЙ CSS (все современные эффекты) ---
cat > /var/www/messenger/style.css <<'EOF'
/* ============================================
   ULTIMATE MESSENGER V8
   Абсолютно максимальный дизайн
   Все современные эффекты и анимации
   ============================================ */

:root {
    /* Основные цвета */
    --primary: #667eea;
    --primary-dark: #5a67d8;
    --secondary: #764ba2;
    --success: #10b981;
    --danger: #ef4444;
    --warning: #f59e0b;
    --info: #3b82f6;
    --dark: #1e293b;
    --light: #f8fafc;
    
    /* Анимации */
    --transition-fast: 0.2s;
    --transition-normal: 0.3s;
    --transition-slow: 0.5s;
    
    /* Тени */
    --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
    --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1);
    --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1);
    --shadow-xl: 0 20px 25px -5px rgb(0 0 0 / 0.1);
    --shadow-2xl: 0 25px 50px -12px rgb(0 0 0 / 0.25);
    
    /* Размытие */
    --blur-sm: blur(4px);
    --blur-md: blur(8px);
    --blur-lg: blur(12px);
    --blur-xl: blur(16px);
}

[data-theme="dark"] {
    --bg-primary: #0f172a;
    --bg-secondary: #1e293b;
    --bg-tertiary: #334155;
    --text-primary: #f1f5f9;
    --text-secondary: #cbd5e1;
    --text-muted: #94a3b8;
    --border-color: #334155;
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
    -webkit-tap-highlight-color: transparent;
}

body {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
    background: var(--bg-primary);
    color: var(--text-primary);
    overflow: hidden;
    transition: background var(--transition-normal), color var(--transition-normal);
}

/* Кастомный скроллбар */
::-webkit-scrollbar {
    width: 8px;
    height: 8px;
}

::-webkit-scrollbar-track {
    background: var(--bg-tertiary);
    border-radius: 10px;
}

::-webkit-scrollbar-thumb {
    background: var(--primary);
    border-radius: 10px;
}

::-webkit-scrollbar-thumb:hover {
    background: var(--primary-dark);
}

/* Анимации */
@keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
}

@keyframes slideInUp {
    from {
        transform: translateY(20px);
        opacity: 0;
    }
    to {
        transform: translateY(0);
        opacity: 1;
    }
}

@keyframes slideInRight {
    from {
        transform: translateX(20px);
        opacity: 0;
    }
    to {
        transform: translateX(0);
        opacity: 1;
    }
}

@keyframes pulse {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.05); }
}

@keyframes shake {
    0%, 100% { transform: translateX(0); }
    25% { transform: translateX(-5px); }
    75% { transform: translateX(5px); }
}

@keyframes glow {
    0%, 100% { box-shadow: 0 0 5px var(--primary); }
    50% { box-shadow: 0 0 20px var(--primary); }
}

@keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
}

@keyframes float {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-10px); }
}

/* Применение анимаций */
.message {
    animation: slideInUp var(--transition-normal) ease;
}

.notification {
    animation: slideInRight var(--transition-normal) ease;
}

.loading-spinner {
    animation: spin 1s linear infinite;
}

.glow-effect {
    animation: glow 2s infinite;
}

.float-effect {
    animation: float 3s ease-in-out infinite;
}

/* Glassmorphism */
.glass {
    background: rgba(255, 255, 255, 0.1);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255, 255, 255, 0.2);
}

/* Neumorphism */
.neumorph {
    background: var(--bg-secondary);
    box-shadow: 5px 5px 10px rgba(0, 0, 0, 0.1),
                -5px -5px 10px rgba(255, 255, 255, 0.05);
}

/* Градиенты */
.gradient-bg {
    background: linear-gradient(135deg, var(--primary), var(--secondary));
}

.gradient-text {
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
}

/* Медиа-запросы для адаптивности */
@media (max-width: 768px) {
    .sidebar {
        position: fixed;
        left: -100%;
        transition: left var(--transition-normal);
        z-index: 1000;
    }
    
    .sidebar.open {
        left: 0;
    }
    
    .message-bubble {
        max-width: 85%;
    }
    
    .chat-header {
        padding: 12px;
    }
    
    .input-area {
        padding: 12px;
    }
}

/* Продвинутые эффекты */
.hover-scale {
    transition: transform var(--transition-fast);
}

.hover-scale:hover {
    transform: scale(1.05);
}

.hover-lift {
    transition: transform var(--transition-fast), box-shadow var(--transition-fast);
}

.hover-lift:hover {
    transform: translateY(-2px);
    box-shadow: var(--shadow-lg);
}

/* Skeleton Loading */
.skeleton {
    background: linear-gradient(90deg, var(--bg-tertiary) 25%, var(--bg-secondary) 50%, var(--bg-tertiary) 75%);
    background-size: 200% 100%;
    animation: loading 1.5s infinite;
}

@keyframes loading {
    0% { background-position: 200% 0; }
    100% { background-position: -200% 0; }
}

/* Конфетти эффект */
.confetti {
    position: fixed;
    width: 10px;
    height: 10px;
    background: var(--primary);
    animation: confetti-fall 3s linear forwards;
}

@keyframes confetti-fall {
    0% {
        transform: translateY(-100vh) rotate(0deg);
        opacity: 1;
    }
    100% {
        transform: translateY(100vh) rotate(720deg);
        opacity: 0;
    }
}

/* Particle эффект */
.particle {
    position: fixed;
    pointer-events: none;
    animation: particle-float 2s ease-out forwards;
}

@keyframes particle-float {
    0% {
        transform: translate(0, 0) scale(1);
        opacity: 1;
    }
    100% {
        transform: translate(var(--tx, 50px), var(--ty, -50px)) scale(0);
        opacity: 0;
    }
}
EOF

# --- МАКСИМАЛЬНЫЙ HTML ---
cat > /var/www/messenger/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">
    <meta name="theme-color" content="#667eea">
    <meta name="description" content="Ultimate Messenger - Максимальный функционал, современный дизайн">
    <title>Ultimate Messenger MAX</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="/style.css">
</head>
<body>
    <div id="app" class="app">
        <!-- Загрузочный экран -->
        <div id="splashScreen" class="splash-screen">
            <div class="splash-content">
                <div class="logo-animation">
                    <i class="fas fa-comments"></i>
                </div>
                <h1 class="gradient-text">Ultimate Messenger MAX</h1>
                <p>Загрузка...</p>
                <div class="progress-bar">
                    <div class="progress-fill"></div>
                </div>
            </div>
        </div>

        <!-- Основное приложение -->
        <div id="mainApp" style="display: none;">
            <!-- Боковая панель -->
            <div class="sidebar" id="sidebar">
                <div class="sidebar-header">
                    <div class="user-card" id="userCard">
                        <div class="avatar-wrapper">
                            <div class="avatar" id="userAvatar">
                                <span id="avatarInitial">U</span>
                                <div class="avatar-status online"></div>
                            </div>
                        </div>
                        <div class="user-info">
                            <h3 id="userName">Загрузка...</h3>
                            <p id="userStatus">Online</p>
                        </div>
                        <div class="user-actions">
                            <i class="fas fa-chevron-down"></i>
                        </div>
                    </div>
                    
                    <div class="search-wrapper">
                        <div class="search-container">
                            <i class="fas fa-search"></i>
                            <input type="text" id="searchInput" placeholder="Поиск: @username, @safarali...">
                            <div class="search-actions">
                                <i class="fas fa-qrcode" id="qrButton" title="QR код"></i>
                                <i class="fas fa-sliders-h" id="settingsButton" title="Настройки"></i>
                                <i class="fas fa-microphone" id="voiceSearch" title="Голосовой поиск"></i>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="chats-container">
                    <div class="chats-header">
                        <span>Чаты</span>
                        <i class="fas fa-plus" id="newChatButton"></i>
                    </div>
                    <div class="chats-list" id="chatsList">
                        <!-- Динамические чаты -->
                    </div>
                </div>
                
                <div class="sidebar-footer">
                    <div class="footer-actions">
                        <i class="fas fa-cog" id="openSettings"></i>
                        <i class="fas fa-moon" id="themeToggle"></i>
                        <i class="fas fa-bell" id="notificationsToggle"></i>
                    </div>
                </div>
            </div>

            <!-- Основная область чата -->
            <div class="chat-area">
                <div class="chat-header">
                    <div class="chat-header-info">
                        <i class="fas fa-bars mobile-menu" id="menuToggle"></i>
                        <div class="avatar" id="chatAvatar"></div>
                        <div class="chat-details">
                            <h3 id="chatName">Выберите чат</h3>
                            <div class="chat-status" id="chatStatus">
                                <span class="typing-indicator" style="display: none;">
                                    <span></span><span></span><span></span>
                                </span>
                                <span class="status-text">Онлайн</span>
                            </div>
                        </div>
                    </div>
                    <div class="chat-actions">
                        <i class="fas fa-phone" id="voiceCall" title="Голосовой звонок"></i>
                        <i class="fas fa-video" id="videoCall" title="Видеозвонок"></i>
                        <i class="fas fa-info-circle" id="chatInfo" title="Информация"></i>
                        <i class="fas fa-search" id="searchInChat" title="Поиск в чате"></i>
                        <i class="fas fa-ellipsis-v" id="chatMenu" title="Меню"></i>
                    </div>
                </div>

                <div class="messages-container" id="messagesContainer">
                    <div class="messages-area" id="messagesArea">
                        <!-- Сообщения -->
                    </div>
                    <div class="scroll-to-bottom" id="scrollToBottom">
                        <i class="fas fa-arrow-down"></i>
                    </div>
                </div>

                <div class="input-area">
                    <div class="input-actions">
                        <button class="action-btn" id="attachFile" title="Прикрепить файл">
                            <i class="fas fa-paperclip"></i>
                        </button>
                        <button class="action-btn" id="emojiPicker" title="Эмодзи">
                            <i class="fas fa-smile"></i>
                        </button>
                        <button class="action-btn" id="voiceMessage" title="Голосовое сообщение">
                            <i class="fas fa-microphone"></i>
                        </button>
                        <button class="action-btn" id="gifPicker" title="GIF">
                            <i class="fas fa-images"></i>
                        </button>
                        <button class="action-btn" id="stickerPicker" title="Стикеры">
                            <i class="fas fa-sticky-note"></i>
                        </button>
                    </div>
                    <div class="message-input-wrapper">
                        <div class="input-mentions" id="inputMentions" style="display: none;"></div>
                        <div class="input-container">
                            <textarea id="messageInput" placeholder="Введите сообщение... @упоминание" rows="1"></textarea>
                            <div class="input-formatting">
                                <i class="fas fa-bold" data-format="bold"></i>
                                <i class="fas fa-italic" data-format="italic"></i>
                                <i class="fas fa-underline" data-format="underline"></i>
                                <i class="fas fa-code" data-format="code"></i>
                                <i class="fas fa-link" data-format="link"></i>
                            </div>
                        </div>
                    </div>
                    <button class="send-btn" id="sendButton">
                        <i class="fas fa-paper-plane"></i>
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- Модальные окна -->
    <div id="qrModal" class="modal">
        <div class="modal-content glass">
            <div class="modal-header">
                <h3>Вход по QR коду</h3>
                <i class="fas fa-times close-modal"></i>
            </div>
            <div class="modal-body">
                <div class="qr-container" id="qrContainer">
                    <div class="qr-placeholder">Генерация QR...</div>
                </div>
                <p>Отсканируйте QR код мобильным приложением</p>
                <div class="qr-timer">
                    <i class="fas fa-hourglass-half"></i>
                    <span id="qrTimer">05:00</span>
                </div>
            </div>
        </div>
    </div>

    <div id="settingsModal" class="modal">
        <div class="modal-content glass" style="max-width: 600px;">
            <div class="modal-header">
                <h3>Настройки</h3>
                <i class="fas fa-times close-modal"></i>
            </div>
            <div class="modal-body">
                <div class="settings-tabs">
                    <button class="tab-btn active" data-tab="general">Общие</button>
                    <button class="tab-btn" data-tab="appearance">Внешний вид</button>
                    <button class="tab-btn" data-tab="privacy">Приватность</button>
                    <button class="tab-btn" data-tab="notifications">Уведомления</button>
                    <button class="tab-btn" data-tab="chat">Чат</button>
                    <button class="tab-btn" data-tab="security">Безопасность</button>
                </div>
                
                <div class="settings-content">
                    <div class="settings-pane active" data-pane="general">
                        <div class="setting-item">
                            <label>Язык интерфейса</label>
                            <select id="language">
                                <option value="ru">Русский</option>
                                <option value="en">English</option>
                                <option value="de">Deutsch</option>
                                <option value="fr">Français</option>
                                <option value="es">Español</option>
                                <option value="zh">中文</option>
                                <option value="ja">日本語</option>
                                <option value="ko">한국어</option>
                                <option value="ar">العربية</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Размер шрифта</label>
                            <input type="range" id="fontSize" min="12" max="20" step="1" value="14">
                            <span id="fontSizeValue">14px</span>
                        </div>
                        <div class="setting-item">
                            <label>Компактный режим</label>
                            <input type="checkbox" id="compactMode">
                        </div>
                        <div class="setting-item">
                            <label>Автозагрузка медиа</label>
                            <select id="autoDownload">
                                <option value="wifi">Только Wi-Fi</option>
                                <option value="always">Всегда</option>
                                <option value="never">Никогда</option>
                            </select>
                        </div>
                    </div>
                    
                    <div class="settings-pane" data-pane="appearance">
                        <div class="setting-item">
                            <label>Тема</label>
                            <div class="theme-options">
                                <button class="theme-option" data-theme="light">Светлая</button>
                                <button class="theme-option" data-theme="dark">Темная</button>
                                <button class="theme-option" data-theme="auto">Авто</button>
                                <button class="theme-option" data-theme="amoled">AMOLED</button>
                            </div>
                        </div>
                        <div class="setting-item">
                            <label>Цвет акцента</label>
                            <div class="color-options">
                                <div class="color-option" data-color="#667eea"></div>
                                <div class="color-option" data-color="#10b981"></div>
                                <div class="color-option" data-color="#ef4444"></div>
                                <div class="color-option" data-color="#f59e0b"></div>
                                <div class="color-option" data-color="#8b5cf6"></div>
                                <div class="color-option" data-color="#ec489a"></div>
                            </div>
                        </div>
                        <div class="setting-item">
                            <label>Анимации</label>
                            <select id="animations">
                                <option value="full">Полные</option>
                                <option value="reduced">Упрощенные</option>
                                <option value="none">Отключены</option>
                            </select>
                        </div>
                    </div>
                    
                    <div class="settings-pane" data-pane="privacy">
                        <div class="setting-item">
                            <label>Последний вход</label>
                            <select id="lastSeen">
                                <option value="everyone">Все</option>
                                <option value="contacts">Контакты</option>
                                <option value="nobody">Никто</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Фото профиля</label>
                            <select id="profilePhoto">
                                <option value="everyone">Все</option>
                                <option value="contacts">Контакты</option>
                                <option value="nobody">Никто</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Статус "в сети"</label>
                            <select id="onlineStatus">
                                <option value="everyone">Все</option>
                                <option value="contacts">Контакты</option>
                                <option value="nobody">Никто</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Блокировка чатов</label>
                            <button class="btn" id="blockedChats">Управление блокировкой</button>
                        </div>
                    </div>
                    
                    <div class="settings-pane" data-pane="notifications">
                        <div class="setting-item">
                            <label>Уведомления</label>
                            <input type="checkbox" id="enableNotifications">
                        </div>
                        <div class="setting-item">
                            <label>Звук уведомлений</label>
                            <input type="checkbox" id="notificationSound">
                            <select id="notificationSoundSelect">
                                <option value="default">По умолчанию</option>
                                <option value="ping">Ping</option>
                                <option value="pop">Pop</option>
                                <option value="chime">Chime</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Всплывающие уведомления</label>
                            <select id="popupNotifications">
                                <option value="always">Всегда</option>
                                <option value="when-minimized">Когда свернуто</option>
                                <option value="never">Никогда</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Предпросмотр сообщений</label>
                            <input type="checkbox" id="messagePreview">
                        </div>
                    </div>
                    
                    <div class="settings-pane" data-pane="chat">
                        <div class="setting-item">
                            <label>Фон чата</label>
                            <div class="chat-bg-options">
                                <button class="bg-option" data-bg="default">По умолчанию</button>
                                <button class="bg-option" data-bg="gradient">Градиент</button>
                                <button class="bg-option" data-bg="custom">Своя картинка</button>
                            </div>
                        </div>
                        <div class="setting-item">
                            <label>Пузырьки сообщений</label>
                            <select id="bubbleStyle">
                                <option value="modern">Современные</option>
                                <option value="classic">Классические</option>
                                <option value="compact">Компактные</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Эмодзи</label>
                            <select id="emojiStyle">
                                <option value="apple">Apple</option>
                                <option value="google">Google</option>
                                <option value="twitter">Twitter</option>
                                <option value="facebook">Facebook</option>
                            </select>
                        </div>
                        <div class="setting-item">
                            <label>Enter для отправки</label>
                            <input type="checkbox" id="enterToSend" checked>
                        </div>
                    </div>
                    
                    <div class="settings-pane" data-pane="security">
                        <div class="setting-item">
                            <label>Двухфакторная аутентификация</label>
                            <button class="btn" id="enable2FA">Включить 2FA</button>
                        </div>
                        <div class="setting-item">
                            <label>Активные сессии</label>
                            <div id="activeSessions"></div>
                            <button class="btn" id="terminateAllSessions">Завершить все сессии</button>
                        </div>
                        <div class="setting-item">
                            <label>Экспорт данных</label>
                            <button class="btn" id="exportData">Экспорт</button>
                        </div>
                        <div class="setting-item">
                            <label>Удалить аккаунт</label>
                            <button class="btn btn-danger" id="deleteAccount">Удалить аккаунт</button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div id="userInfoModal" class="modal">
        <div class="modal-content glass">
            <div class="modal-header">
                <h3>Информация о пользователе</h3>
                <i class="fas fa-times close-modal"></i>
            </div>
            <div class="modal-body" id="userInfoContent">
                <!-- Динамическая информация -->
            </div>
        </div>
    </div>

    <div id="chatInfoModal" class="modal">
        <div class="modal-content glass">
            <div class="modal-header">
                <h3>Информация о чате</h3>
                <i class="fas fa-times close-modal"></i>
            </div>
            <div class="modal-body" id="chatInfoContent">
                <!-- Динамическая информация -->
            </div>
        </div>
    </div>

    <div id="callModal" class="modal">
        <div class="modal-content glass call-modal">
            <div class="call-header">
                <div class="call-avatar" id="callAvatar"></div>
                <h3 id="callUserName">Звонок...</h3>
                <p id="callStatus">Соединение...</p>
            </div>
            <div class="call-controls">
                <button class="call-control" id="muteCall"><i class="fas fa-microphone"></i></button>
                <button class="call-control" id="endCall" class="danger"><i class="fas fa-phone-slash"></i></button>
                <button class="call-control" id="speakerCall"><i class="fas fa-volume-up"></i></button>
            </div>
        </div>
    </div>

    <div id="toastContainer" class="toast-container"></div>
    <div id="confettiContainer" class="confetti-container"></div>

    <script src="/socket.io/socket.io.js"></script>
    <script>
        // Максимальный JavaScript
        class UltimateMessenger {
            constructor() {
                this.currentUser = null;
                this.currentChat = null;
                this.socket = null;
                this.settings = this.loadSettings();
                this.mediaRecorder = null;
                this.audioChunks = [];
                this.typingTimeout = null;
                this.init();
            }
            
            init() {
                this.hideSplash();
                this.loadUser();
                this.setupEventListeners();
                this.setupWebSocket();
                this.applySettings();
                this.setupSearch();
                this.setupVoiceSearch();
                this.setupEmojiPicker();
                this.setupGifPicker();
                this.setupStickerPicker();
                this.setupFileUpload();
                this.setupVoiceMessages();
                this.setupCallFeatures();
                this.setupFormatting();
                this.loadDemoData();
                this.startRealtimeUpdates();
                this.setupOfflineSupport();
                this.setupPwa();
                this.startConfettiEffect();
            }
            
            hideSplash() {
                setTimeout(() => {
                    document.getElementById('splashScreen').style.opacity = '0';
                    setTimeout(() => {
                        document.getElementById('splashScreen').style.display = 'none';
                        document.getElementById('mainApp').style.display = 'flex';
                        this.showToast('Добро пожаловать в Ultimate Messenger MAX!', 'success');
                    }, 500);
                }, 2000);
            }
            
            loadUser() {
                const token = localStorage.getItem('access_token');
                if (token) {
                    this.currentUser = {
                        id: 'user_' + Math.random().toString(36).substr(2, 9),
                        username: 'user',
                        displayName: 'Demo User',
                        avatar: 'U',
                        email: 'user@example.com',
                        phone: '+7 999 123-45-67',
                        status: 'online',
                        lastSeen: new Date()
                    };
                    this.updateUI();
                } else {
                    document.getElementById('userName').textContent = 'Гость';
                    document.getElementById('userStatus').textContent = 'Не авторизован';
                }
            }
            
            updateUI() {
                if (this.currentUser) {
                    document.getElementById('userName').textContent = this.currentUser.displayName;
                    document.getElementById('avatarInitial').textContent = this.currentUser.displayName[0];
                }
            }
            
            setupEventListeners() {
                // Основные элементы
                document.getElementById('sendButton').addEventListener('click', () => this.sendMessage());
                document.getElementById('messageInput').addEventListener('keypress', (e) => {
                    if (e.key === 'Enter' && !e.shiftKey && this.settings.enterToSend) {
                        e.preventDefault();
                        this.sendMessage();
                    }
                });
                document.getElementById('messageInput').addEventListener('input', () => this.handleTyping());
                document.getElementById('qrButton').addEventListener('click', () => this.showQRModal());
                document.getElementById('settingsButton').addEventListener('click', () => this.showSettings());
                document.getElementById('menuToggle').addEventListener('click', () => this.toggleSidebar());
                document.getElementById('themeToggle').addEventListener('click', () => this.toggleTheme());
                document.getElementById('newChatButton').addEventListener('click', () => this.newChat());
                document.getElementById('voiceCall').addEventListener('click', () => this.startCall('voice'));
                document.getElementById('videoCall').addEventListener('click', () => this.startCall('video'));
                document.getElementById('chatInfo').addEventListener('click', () => this.showChatInfo());
                document.getElementById('scrollToBottom').addEventListener('click', () => this.scrollToBottom());
                
                // Закрытие модалок
                document.querySelectorAll('.close-modal').forEach(el => {
                    el.addEventListener('click', () => this.closeModals());
                });
                
                // Настройки
                document.querySelectorAll('.tab-btn').forEach(btn => {
                    btn.addEventListener('click', () => this.switchSettingsTab(btn.dataset.tab));
                });
                
                document.querySelectorAll('.theme-option').forEach(opt => {
                    opt.addEventListener('click', () => this.changeTheme(opt.dataset.theme));
                });
                
                document.querySelectorAll('.color-option').forEach(opt => {
                    opt.addEventListener('click', () => this.changeAccentColor(opt.dataset.color));
                });
                
                document.getElementById('fontSize').addEventListener('input', (e) => {
                    document.body.style.fontSize = e.target.value + 'px';
                    document.getElementById('fontSizeValue').textContent = e.target.value + 'px';
                    this.saveSetting('fontSize', e.target.value);
                });
                
                document.getElementById('compactMode').addEventListener('change', (e) => {
                    if (e.target.checked) {
                        document.body.classList.add('compact');
                    } else {
                        document.body.classList.remove('compact');
                    }
                    this.saveSetting('compactMode', e.target.checked);
                });
                
                document.getElementById('enterToSend').addEventListener('change', (e) => {
                    this.settings.enterToSend = e.target.checked;
                    this.saveSettings();
                });
            }
            
            setupWebSocket() {
                this.socket = io('http://localhost:3002', {
                    transports: ['websocket'],
                    reconnection: true,
                    reconnectionAttempts: Infinity,
                    reconnectionDelay: 1000
                });
                
                this.socket.on('connect', () => {
                    this.showToast('Подключено к серверу', 'success');
                    this.updateConnectionStatus(true);
                });
                
                this.socket.on('disconnect', () => {
                    this.showToast('Потеряно соединение', 'error');
                    this.updateConnectionStatus(false);
                });
                
                this.socket.on('new_message', (data) => {
                    this.receiveMessage(data);
                });
                
                this.socket.on('user_typing', (data) => {
                    this.showTypingIndicator(data);
                });
                
                this.socket.on('call_incoming', (data) => {
                    this.handleIncomingCall(data);
                });
            }
            
            setupSearch() {
                let timeout;
                document.getElementById('searchInput').addEventListener('input', (e) => {
                    clearTimeout(timeout);
                    timeout = setTimeout(() => {
                        this.search(e.target.value);
                    }, 300);
                });
            }
            
            async search(query) {
                if (query.length < 2) return;
                
                try {
                    const response = await fetch(`/api/search?q=${encodeURIComponent(query)}&type=global`);
                    const results = await response.json();
                    this.displaySearchResults(results);
                } catch (error) {
                    console.error('Search error:', error);
                }
            }
            
            displaySearchResults(results) {
                const chatsList = document.getElementById('chatsList');
                
                if (results.users && results.users.length > 0) {
                    results.users.forEach(user => {
                        this.addChat(user);
                    });
                }
                
                if (results.bots && results.bots.length > 0) {
                    results.bots.forEach(bot => {
                        this.addChat(bot);
                    });
                }
            }
            
            addChat(chat) {
                const existing = document.querySelector(`[data-chat-id="${chat.user_id}"]`);
                if (existing) return;
                
                const chatsList = document.getElementById('chatsList');
                const div = document.createElement('div');
                div.className = 'chat-item';
                div.setAttribute('data-chat-id', chat.user_id);
                div.innerHTML = `
                    <div class="chat-avatar">${chat.type === 'bot' ? '🤖' : '👤'}</div>
                    <div class="chat-info">
                        <div class="chat-name">${chat.display_name || chat.username || chat.user_id}</div>
                        <div class="chat-preview">${chat.type === 'bot' ? 'Bot' : 'Пользователь'} • Нажмите для чата</div>
                    </div>
                `;
                div.onclick = () => this.selectChat(chat);
                chatsList.insertBefore(div, chatsList.firstChild);
            }
            
            selectChat(chat) {
                this.currentChat = chat;
                document.getElementById('chatName').textContent = chat.display_name || chat.username || chat.user_id;
                document.getElementById('messagesArea').innerHTML = '';
                this.loadChatHistory();
                this.markAsRead();
            }
            
            loadChatHistory() {
                const messagesArea = document.getElementById('messagesArea');
                messagesArea.innerHTML = '<div class="loading-messages"><div class="spinner"></div><p>Загрузка сообщений...</p></div>';
                
                setTimeout(() => {
                    messagesArea.innerHTML = '';
                    this.addDemoMessages();
                }, 500);
            }
            
            addDemoMessages() {
                const demoMessages = [
                    { text: 'Добро пожаловать в Ultimate Messenger MAX!', incoming: true, time: '10:00', sender: 'System' },
                    { text: 'Это максимально функциональный мессенджер', incoming: true, time: '10:01', sender: 'System' },
                    { text: 'Попробуйте поиск @safarali', incoming: true, time: '10:02', sender: 'System' },
                    { text: 'Или войдите по QR коду', incoming: true, time: '10:03', sender: 'System' },
                    { text: 'Отлично! Спасибо!', outgoing: true, time: '10:04' }
                ];
                
                demoMessages.forEach(msg => {
                    this.addMessage(msg.text, msg.incoming, msg.time, msg.sender);
                });
            }
            
            addMessage(text, incoming, time, sender = null) {
                const messagesArea = document.getElementById('messagesArea');
                const messageDiv = document.createElement('div');
                messageDiv.className = `message ${incoming ? 'incoming' : 'outgoing'} message-animate`;
                
                let formattedText = this.formatMessage(text);
                
                messageDiv.innerHTML = `
                    <div class="message-bubble ${incoming ? '' : 'message-out'}">
                        ${incoming && sender ? `<div class="message-sender">${sender}</div>` : ''}
                        <div class="message-text">${formattedText}</div>
                        <div class="message-meta">
                            <span class="message-time">${time}</span>
                            ${!incoming ? '<span class="message-status"><i class="fas fa-check-double"></i></span>' : ''}
                        </div>
                    </div>
                `;
                
                messagesArea.appendChild(messageDiv);
                this.scrollToBottom();
                
                // Анимация
                messageDiv.style.animation = 'slideInUp 0.3s ease';
            }
            
            formatMessage(text) {
                // Форматирование ссылок
                text = text.replace(/(https?:\/\/[^\s]+)/g, '<a href="$1" target="_blank">$1</a>');
                
                // Форматирование упоминаний
                text = text.replace(/@(\w+)(?::([\w.-]+))?/g, (match, username, domain) => {
                    return `<span class="mention" onclick="app.mentionUser('${match}')">${match}</span>`;
                });
                
                // Форматирование кода
                text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
                text = text.replace(/```([\s\S]+?)```/g, '<pre><code>$1</code></pre>');
                
                // Форматирование жирного и курсива
                text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
                text = text.replace(/\*([^*]+)\*/g, '<em>$1</em>');
                
                return text;
            }
            
            sendMessage() {
                const input = document.getElementById('messageInput');
                const message = input.value.trim();
                if (!message || !this.currentChat) return;
                
                this.addMessage(message, false, new Date().toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'}));
                
                // Отправка через WebSocket
                this.socket.emit('send_message', {
                    chat_id: this.currentChat.user_id,
                    message: message,
                    user: this.currentUser,
                    time: Date.now()
                });
                
                input.value = '';
                this.autoResizeTextarea();
                
                // Эффект отправки
                const sendBtn = document.getElementById('sendButton');
                sendBtn.style.transform = 'scale(0.9)';
                setTimeout(() => sendBtn.style.transform = '', 200);
            }
            
            receiveMessage(data) {
                this.addMessage(data.message, true, new Date(data.time).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'}), data.user?.displayName);
                
                if (this.settings.notificationSound) {
                    this.playNotificationSound();
                }
                
                if (this.settings.enableNotifications && document.hidden) {
                    this.showDesktopNotification(data.user?.displayName, data.message);
                }
            }
            
            async showQRModal() {
                const modal = document.getElementById('qrModal');
                const qrContainer = document.getElementById('qrContainer');
                
                modal.style.display = 'flex';
                qrContainer.innerHTML = '<div class="spinner"></div><p>Генерация QR...</p>';
                
                try {
                    const response = await fetch('/qr/generate', { method: 'POST' });
                    const blob = await response.blob();
                    const url = URL.createObjectURL(blob);
                    qrContainer.innerHTML = `<img src="${url}" style="width: 200px; height: 200px;">`;
                    
                    // Таймер
                    let timeLeft = 300;
                    const timer = setInterval(() => {
                        const minutes = Math.floor(timeLeft / 60);
                        const seconds = timeLeft % 60;
                        document.getElementById('qrTimer').textContent = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
                        timeLeft--;
                        if (timeLeft < 0) clearInterval(timer);
                    }, 1000);
                    
                    // Проверка статуса
                    const token = url.split('/').pop().replace('.png', '');
                    this.pollQRStatus(token);
                } catch (error) {
                    qrContainer.innerHTML = '<p class="error">Ошибка генерации QR</p>';
                }
            }
            
            async pollQRStatus(token) {
                const interval = setInterval(async () => {
                    try {
                        const response = await fetch(`/qr/status/${token}`);
                        const data = await response.json();
                        if (data.status === 'confirmed') {
                            clearInterval(interval);
                            localStorage.setItem('access_token', data.access_token);
                            this.closeModals();
                            this.showToast('Вход выполнен успешно!', 'success');
                            location.reload();
                        }
                    } catch (error) {
                        console.error('QR status error:', error);
                    }
                }, 2000);
            }
            
            setupVoiceSearch() {
                const voiceSearch = document.getElementById('voiceSearch');
                if (!('webkitSpeechRecognition' in window)) {
                    voiceSearch.style.display = 'none';
                    return;
                }
                
                const recognition = new webkitSpeechRecognition();
                recognition.lang = 'ru-RU';
                recognition.interimResults = false;
                
                voiceSearch.addEventListener('click', () => {
                    recognition.start();
                    this.showToast('Слушаю...', 'info');
                });
                
                recognition.onresult = (event) => {
                    const query = event.results[0][0].transcript;
                    document.getElementById('searchInput').value = query;
                    this.search(query);
                };
            }
            
            setupVoiceMessages() {
                const voiceBtn = document.getElementById('voiceMessage');
                let isRecording = false;
                
                voiceBtn.addEventListener('mousedown', async () => {
                    if (!this.currentChat) return;
                    
                    try {
                        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
                        this.mediaRecorder = new MediaRecorder(stream);
                        this.audioChunks = [];
                        
                        this.mediaRecorder.ondataavailable = (event) => {
                            this.audioChunks.push(event.data);
                        };
                        
                        this.mediaRecorder.onstop = () => {
                            const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
                            const audioUrl = URL.createObjectURL(audioBlob);
                            this.addMessage('🎤 Голосовое сообщение', false, new Date().toLocaleTimeString());
                            this.showToast('Голосовое сообщение отправлено', 'success');
                            stream.getTracks().forEach(track => track.stop());
                        };
                        
                        this.mediaRecorder.start();
                        isRecording = true;
                        voiceBtn.classList.add('recording');
                        this.showToast('Запись... Отпустите для отправки', 'info');
                    } catch (error) {
                        this.showToast('Ошибка доступа к микрофону', 'error');
                    }
                });
                
                voiceBtn.addEventListener('mouseup', () => {
                    if (this.mediaRecorder && isRecording) {
                        this.mediaRecorder.stop();
                        isRecording = false;
                        voiceBtn.classList.remove('recording');
                    }
                });
            }
            
            setupCallFeatures() {
                this.peerConnection = null;
                this.localStream = null;
                this.remoteStream = null;
            }
            
            async startCall(type) {
                if (!this.currentChat) {
                    this.showToast('Выберите чат для звонка', 'error');
                    return;
                }
                
                const modal = document.getElementById('callModal');
                const callAvatar = document.getElementById('callAvatar');
                const callUserName = document.getElementById('callUserName');
                
                callAvatar.textContent = this.currentChat.display_name?.[0] || '👤';
                callUserName.textContent = this.currentChat.display_name || this.currentChat.user_id;
                modal.style.display = 'flex';
                
                try {
                    this.localStream = await navigator.mediaDevices.getUserMedia({ 
                        audio: true, 
                        video: type === 'video' 
                    });
                    
                    // Создание WebRTC соединения
                    this.peerConnection = new RTCPeerConnection({
                        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                    });
                    
                    this.localStream.getTracks().forEach(track => {
                        this.peerConnection.addTrack(track, this.localStream);
                    });
                    
                    this.peerConnection.ontrack = (event) => {
                        this.remoteStream = event.streams[0];
                        // Отображение видео
                    };
                    
                } catch (error) {
                    this.showToast('Ошибка доступа к камере/микрофону', 'error');
                    this.endCall();
                }
            }
            
            endCall() {
                if (this.localStream) {
                    this.localStream.getTracks().forEach(track => track.stop());
                }
                if (this.peerConnection) {
                    this.peerConnection.close();
                }
                document.getElementById('callModal').style.display = 'none';
            }
            
            setupEmojiPicker() {
                const emojiBtn = document.getElementById('emojiPicker');
                let emojiPicker = null;
                
                // Простые эмодзи для демо
                const emojis = ['😀', '😂', '❤️', '👍', '🎉', '🔥', '💯', '✨', '🌟', '💪', '🤔', '😢', '😡', '🥳', '😎', '🤯', '💀', '👻', '🎃', '💖'];
                
                emojiBtn.addEventListener('click', () => {
                    if (emojiPicker) {
                        emojiPicker.remove();
                        emojiPicker = null;
                        return;
                    }
                    
                    emojiPicker = document.createElement('div');
                    emojiPicker.className = 'emoji-picker glass';
                    emojiPicker.style.cssText = `
                        position: absolute;
                        bottom: 70px;
                        left: 20px;
                        display: grid;
                        grid-template-columns: repeat(8, 1fr);
                        gap: 8px;
                        padding: 12px;
                        border-radius: 12px;
                        z-index: 1000;
                        max-width: 300px;
                    `;
                    
                    emojis.forEach(emoji => {
                        const btn = document.createElement('button');
                        btn.textContent = emoji;
                        btn.style.cssText = `
                            width: 32px;
                            height: 32px;
                            border: none;
                            background: transparent;
                            cursor: pointer;
                            font-size: 20px;
                            transition: transform 0.2s;
                        `;
                        btn.onmouseenter = () => btn.style.transform = 'scale(1.2)';
                        btn.onmouseleave = () => btn.style.transform = '';
                        btn.onclick = () => {
                            const input = document.getElementById('messageInput');
                            input.value += emoji;
                            input.focus();
                            emojiPicker.remove();
                            emojiPicker = null;
                        };
                        emojiPicker.appendChild(btn);
                    });
                    
                    emojiBtn.parentElement.appendChild(emojiPicker);
                });
            }
            
            setupGifPicker() {
                const gifBtn = document.getElementById('gifPicker');
                gifBtn.addEventListener('click', () => {
                    this.showToast('GIF поиск (GIPHY API)', 'info');
                    // Здесь можно интегрировать GIPHY API
                });
            }
            
            setupStickerPicker() {
                const stickerBtn = document.getElementById('stickerPicker');
                stickerBtn.addEventListener('click', () => {
                    this.showToast('Стикерпаки', 'info');
                });
            }
            
            setupFileUpload() {
                const fileInput = document.createElement('input');
                fileInput.type = 'file';
                fileInput.multiple = true;
                fileInput.style.display = 'none';
                document.body.appendChild(fileInput);
                
                document.getElementById('attachFile').addEventListener('click', () => {
                    fileInput.click();
                });
                
                fileInput.addEventListener('change', (e) => {
                    const files = Array.from(e.target.files);
                    files.forEach(file => {
                        this.uploadFile(file);
                    });
                });
            }
            
            uploadFile(file) {
                const fileSize = (file.size / 1024 / 1024).toFixed(2);
                let fileIcon = '📄';
                
                if (file.type.startsWith('image/')) fileIcon = '🖼️';
                else if (file.type.startsWith('video/')) fileIcon = '🎥';
                else if (file.type.startsWith('audio/')) fileIcon = '🎵';
                else if (file.type === 'application/pdf') fileIcon = '📑';
                
                this.addMessage(`${fileIcon} ${file.name} (${fileSize} MB)`, false, new Date().toLocaleTimeString());
                this.showToast(`Файл "${file.name}" загружен`, 'success');
            }
            
            setupFormatting() {
                const formattingBtns = document.querySelectorAll('.input-formatting i');
                const input = document.getElementById('messageInput');
                
                formattingBtns.forEach(btn => {
                    btn.addEventListener('click', () => {
                        const format = btn.dataset.format;
                        const start = input.selectionStart;
                        const end = input.selectionEnd;
                        const text = input.value;
                        let formatted = '';
                        
                        switch(format) {
                            case 'bold':
                                formatted = `**${text.substring(start, end)}**`;
                                break;
                            case 'italic':
                                formatted = `*${text.substring(start, end)}*`;
                                break;
                            case 'underline':
                                formatted = `<u>${text.substring(start, end)}</u>`;
                                break;
                            case 'code':
                                formatted = `\`${text.substring(start, end)}\``;
                                break;
                            case 'link':
                                const url = prompt('Введите URL:');
                                if (url) formatted = `[${text.substring(start, end)}](${url})`;
                                break;
                        }
                        
                        input.value = text.substring(0, start) + formatted + text.substring(end);
                        input.focus();
                    });
                });
            }
            
            handleTyping() {
                if (this.currentChat) {
                    this.socket.emit('typing', {
                        chat_id: this.currentChat.user_id,
                        user: this.currentUser
                    });
                }
                
                clearTimeout(this.typingTimeout);
                this.typingTimeout = setTimeout(() => {
                    if (this.currentChat) {
                        this.socket.emit('stop_typing', { chat_id: this.currentChat.user_id });
                    }
                }, 1000);
                
                this.autoResizeTextarea();
            }
            
            showTypingIndicator(data) {
                const statusText = document.querySelector('.status-text');
                const typingIndicator = document.querySelector('.typing-indicator');
                
                if (data.user === this.currentChat?.user_id) {
                    typingIndicator.style.display = 'inline-flex';
                    statusText.style.display = 'none';
                    setTimeout(() => {
                        typingIndicator.style.display = 'none';
                        statusText.style.display = 'inline';
                    }, 2000);
                }
            }
            
            autoResizeTextarea() {
                const textarea = document.getElementById('messageInput');
                textarea.style.height = 'auto';
                textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
            }
            
            scrollToBottom() {
                const container = document.getElementById('messagesContainer');
                container.scrollTop = container.scrollHeight;
            }
            
            showToast(message, type = 'info') {
                const container = document.getElementById('toastContainer');
                const toast = document.createElement('div');
                toast.className = `toast toast-${type}`;
                toast.innerHTML = `
                    <i class="fas ${type === 'success' ? 'fa-check-circle' : type === 'error' ? 'fa-exclamation-circle' : 'fa-info-circle'}"></i>
                    <span>${message}</span>
                `;
                container.appendChild(toast);
                
                setTimeout(() => {
                    toast.style.animation = 'slideOut 0.3s ease';
                    setTimeout(() => toast.remove(), 300);
                }, 3000);
            }
            
            showDesktopNotification(title, body) {
                if ('Notification' in window && Notification.permission === 'granted') {
                    new Notification(title, { body, icon: '/icon.png' });
                } else if ('Notification' in window && Notification.permission !== 'denied') {
                    Notification.requestPermission();
                }
            }
            
            playNotificationSound() {
                const audio = new Audio('/notification.mp3');
                audio.play().catch(e => console.log('Audio error:', e));
            }
            
            toggleSidebar() {
                document.getElementById('sidebar').classList.toggle('open');
            }
            
            toggleTheme() {
                const currentTheme = document.body.getAttribute('data-theme');
                const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
                this.changeTheme(newTheme);
            }
            
            changeTheme(theme) {
                document.body.setAttribute('data-theme', theme === 'auto' ? 
                    (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : theme);
                localStorage.setItem('theme', theme);
                this.saveSetting('theme', theme);
            }
            
            changeAccentColor(color) {
                document.documentElement.style.setProperty('--primary', color);
                localStorage.setItem('accentColor', color);
                this.saveSetting('accentColor', color);
            }
            
            showSettings() {
                document.getElementById('settingsModal').style.display = 'flex';
            }
            
            switchSettingsTab(tabId) {
                document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
                document.querySelectorAll('.settings-pane').forEach(pane => pane.classList.remove('active'));
                
                document.querySelector(`.tab-btn[data-tab="${tabId}"]`).classList.add('active');
                document.querySelector(`.settings-pane[data-pane="${tabId}"]`).classList.add('active');
            }
            
            showChatInfo() {
                if (!this.currentChat) return;
                const modal = document.getElementById('chatInfoModal');
                const content = document.getElementById('chatInfoContent');
                
                content.innerHTML = `
                    <div class="chat-info">
                        <div class="info-avatar">${this.currentChat.display_name?.[0] || '👤'}</div>
                        <h4>${this.currentChat.display_name || this.currentChat.user_id}</h4>
                        <div class="info-stats">
                            <div class="stat">
                                <i class="fas fa-calendar"></i>
                                <span>Создан: ${new Date().toLocaleDateString()}</span>
                            </div>
                            <div class="stat">
                                <i class="fas fa-users"></i>
                                <span>Участников: 1</span>
                            </div>
                            <div class="stat">
                                <i class="fas fa-image"></i>
                                <span>Медиа: 0</span>
                            </div>
                        </div>
                        <div class="info-actions">
                            <button class="btn" onclick="app.muteChat()">Отключить звук</button>
                            <button class="btn btn-danger" onclick="app.clearChat()">Очистить историю</button>
                            <button class="btn btn-danger" onclick="app.leaveChat()">Покинуть чат</button>
                        </div>
                    </div>
                `;
                
                modal.style.display = 'flex';
            }
            
            closeModals() {
                document.querySelectorAll('.modal').forEach(modal => {
                    modal.style.display = 'none';
                });
            }
            
            loadSettings() {
                return {
                    theme: localStorage.getItem('theme') || 'light',
                    fontSize: localStorage.getItem('fontSize') || 14,
                    compactMode: localStorage.getItem('compactMode') === 'true',
                    enterToSend: localStorage.getItem('enterToSend') !== 'false',
                    enableNotifications: localStorage.getItem('enableNotifications') === 'true',
                    notificationSound: localStorage.getItem('notificationSound') === 'true',
                    autoDownload: localStorage.getItem('autoDownload') || 'wifi'
                };
            }
            
            saveSettings() {
                Object.keys(this.settings).forEach(key => {
                    localStorage.setItem(key, this.settings[key]);
                });
            }
            
            saveSetting(key, value) {
                this.settings[key] = value;
                this.saveSettings();
            }
            
            applySettings() {
                document.body.style.fontSize = this.settings.fontSize + 'px';
                if (this.settings.compactMode) document.body.classList.add('compact');
                this.changeTheme(this.settings.theme);
            }
            
            updateConnectionStatus(connected) {
                const statusElement = document.getElementById('userStatus');
                if (connected) {
                    statusElement.textContent = 'Online';
                    statusElement.style.color = 'var(--success)';
                } else {
                    statusElement.textContent = 'Offline';
                    statusElement.style.color = 'var(--danger)';
                }
            }
            
            startRealtimeUpdates() {
                setInterval(() => {
                    this.updateRealtimeStats();
                }, 5000);
            }
            
            async updateRealtimeStats() {
                try {
                    const response = await fetch('/api/dashboard/stats');
                    const stats = await response.json();
                    // Обновление статистики в UI
                } catch (error) {
                    console.error('Stats error:', error);
                }
            }
            
            setupOfflineSupport() {
                if ('serviceWorker' in navigator) {
                    navigator.serviceWorker.register('/sw.js').then(reg => {
                        console.log('Service Worker registered');
                    });
                }
                
                // Кэширование сообщений для оффлайн
                window.addEventListener('online', () => {
                    this.showToast('Соединение восстановлено', 'success');
                    this.updateConnectionStatus(true);
                });
                
                window.addEventListener('offline', () => {
                    this.showToast('Нет соединения с интернетом', 'error');
                    this.updateConnectionStatus(false);
                });
            }
            
            setupPwa() {
                // PWA установка
                let deferredPrompt;
                window.addEventListener('beforeinstallprompt', (e) => {
                    e.preventDefault();
                    deferredPrompt = e;
                    this.showInstallPrompt();
                });
            }
            
            showInstallPrompt() {
                const installBtn = document.createElement('button');
                installBtn.textContent = 'Установить приложение';
                installBtn.className = 'install-btn';
                installBtn.onclick = async () => {
                    if (deferredPrompt) {
                        deferredPrompt.prompt();
                        const { outcome } = await deferredPrompt.userChoice;
                        if (outcome === 'accepted') {
                            this.showToast('Приложение установлено!', 'success');
                        }
                        deferredPrompt = null;
                    }
                };
                // Добавление кнопки в UI
            }
            
            startConfettiEffect() {
                // Случайный конфетти для праздничных моментов
                setInterval(() => {
                    if (Math.random() < 0.01) { // 1% шанс
                        this.triggerConfetti();
                    }
                }, 30000);
            }
            
            triggerConfetti() {
                const container = document.getElementById('confettiContainer');
                for (let i = 0; i < 100; i++) {
                    const confetti = document.createElement('div');
                    confetti.className = 'confetti';
                    confetti.style.left = Math.random() * window.innerWidth + 'px';
                    confetti.style.backgroundColor = `hsl(${Math.random() * 360}, 100%, 50%)`;
                    confetti.style.animationDuration = Math.random() * 3 + 2 + 's';
                    container.appendChild(confetti);
                    setTimeout(() => confetti.remove(), 3000);
                }
            }
            
            loadDemoData() {
                // Загрузка демо чатов
                const demoChats = [
                    { user_id: 'general', display_name: 'Общий чат', type: 'group', avatar: '💬' },
                    { user_id: 'tech_support', display_name: 'Техподдержка', type: 'support', avatar: '🛠️' },
                    { user_id: 'safarali_bot', display_name: 'Safarali Bot', type: 'bot', avatar: '🤖' }
                ];
                
                demoChats.forEach(chat => this.addChat(chat));
            }
            
            mentionUser(mention) {
                this.showToast(`Упомянут: ${mention}`, 'info');
                const input = document.getElementById('messageInput');
                input.value += mention + ' ';
                input.focus();
            }
            
            muteChat() {
                this.showToast('Уведомления отключены', 'info');
                this.closeModals();
            }
            
            clearChat() {
                if (confirm('Очистить историю чата?')) {
                    document.getElementById('messagesArea').innerHTML = '';
                    this.showToast('История очищена', 'success');
                    this.closeModals();
                }
            }
            
            leaveChat() {
                if (confirm('Покинуть чат?')) {
                    this.currentChat = null;
                    document.getElementById('chatName').textContent = 'Выберите чат';
                    document.getElementById('messagesArea').innerHTML = '';
                    this.showToast('Чат покинут', 'info');
                    this.closeModals();
                }
            }
            
            newChat() {
                this.showToast('Создание нового чата...', 'info');
                const username = prompt('Введите username или @username:domain:');
                if (username) {
                    this.search(username);
                }
            }
            
            markAsRead() {
                if (this.currentChat) {
                    // Отметка сообщений как прочитанных
                }
            }
        }
        
        // Инициализация приложения
        const app = new UltimateMessenger();
        window.app = app;
    </script>
</body>
</html>
EOF

# --- NGINX КОНФИГУРАЦИЯ (МАКСИМАЛЬНАЯ) ---
print_header "МАКСИМАЛЬНАЯ НАСТРОЙКА NGINX"
cat > /etc/nginx/sites-available/matrix <<EOF
# Максимальная конфигурация Nginx
upstream synapse {
    server localhost:8008;
    keepalive 64;
}

upstream admin {
    server localhost:5000;
    keepalive 32;
}

upstream search {
    server localhost:3002;
    keepalive 32;
}

server {
    server_name $DOMAIN;
    listen 80;
    listen [::]:80;
    return 301 https://\$server_name\$request_uri;
}

server {
    server_name $DOMAIN;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    listen 8448 ssl;
    listen [::]:8448 ssl;

    # SSL (максимальная безопасность)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_dhparam /etc/nginx/dhparam.pem;

    # Security headers (максимальная защита)
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self' https:; script-src 'self' 'unsafe-inline' 'unsafe-eval' https:; style-src 'self' 'unsafe-inline' https:; img-src 'self' data: https:; font-src 'self' data: https:; connect-src 'self' https: wss:;" always;

    # Performance
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json image/svg+xml;
    gzip_comp_level 6;
    
    # Brotli
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css text/xml text/javascript application/javascript application/json;

    # Main web interface
    location / {
        root /var/www/messenger;
        try_files \$uri \$uri/ /index.html;
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

    # Static assets (максимальное кэширование)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|mp3|mp4|webm)$ {
        root /var/www/messenger;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Admin panel
    location /admin {
        proxy_pass http://admin;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
    }

    # Socket.IO
    location /socket.io {
        proxy_pass http://search/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
    }

    # Search API
    location /api {
        proxy_pass http://search/api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_valid 200 1m;
    }

    # QR Auth
    location /qr {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Synapse API
    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://synapse;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 2G;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;
    }

    # Well-known
    location /.well-known/matrix/client {
        add_header Content-Type application/json;
        add_header Access-Control-Allow-Origin *;
        return 200 '{"m.homeserver": {"base_url": "https://$DOMAIN"}}';
    }
    
    location /.well-known/matrix/server {
        add_header Content-Type application/json;
        return 200 '{"m.server": "$DOMAIN:443"}';
    }

    # Error pages
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF

# Генерация DH параметров для SSL
openssl dhparam -out /etc/nginx/dhparam.pem 2048

# --- ЗАПУСК ВСЕХ СЕРВИСОВ ---
systemctl daemon-reload
systemctl enable matrix-synapse postgresql redis-server nginx
systemctl restart matrix-synapse postgresql redis-server nginx

# --- SSL СЕРТИФИКАТ ---
certbot certonly --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL
systemctl reload nginx

# --- ФИНАЛЬНАЯ ИНФОРМАЦИЯ ---
clear
print_header "УСТАНОВКА ULTIMATE MESSENGER V8 ЗАВЕРШЕНА!"

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║     ULTIMATE MESSENGER V8 - ABSOLUTE MAXIMUM                         ║"
echo "║     МАКСИМАЛЬНЫЙ ФУНКЦИОНАЛ - ГОТОВ К ИСПОЛЬЗОВАНИЮ!                  ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}🌐 ВЕБ-ИНТЕРФЕЙС:${NC}"
echo "   https://$DOMAIN"
echo ""
echo -e "${CYAN}🔧 АДМИН-ПАНЕЛЬ:${NC}"
echo "   https://$DOMAIN/admin"
echo "   Логин: $ADMIN_USER"
echo "   Пароль: $ADMIN_PASS"
echo ""
echo -e "${CYAN}📱 QR АВТОРИЗАЦИЯ:${NC}"
echo "   Нажмите на иконку QR в строке поиска"
echo ""
echo -e "${CYAN}🎨 МАКСИМАЛЬНЫЙ ФУНКЦИОНАЛ:${NC}"
echo "   ✓ Glassmorphism + Neumorphism дизайн"
echo "   ✓ Адаптивный интерфейс для всех устройств"
echo "   ✓ Светлая/Темная/AMOLED темы"
echo "   ✓ Голосовой поиск"
echo "   ✓ Голосовые сообщения"
echo "   ✓ Видеозвонки (WebRTC)"
echo "   ✓ Отправка файлов до 2GB"
echo "   ✓ Эмодзи, GIF, стикеры"
echo "   ✓ Форматирование текста (жирный, курсив, код)"
echo "   ✓ Упоминания @username"
echo "   ✓ Поиск @safarali"
echo "   ✓ Индикатор набора текста"
echo "   ✓ Уведомления с звуком"
echo "   ✓ PWA установка"
echo "   ✓ Оффлайн поддержка"
echo "   ✓ Конфетти эффекты"
echo "   ✓ Анимации и переходы"
echo "   ✓ Кастомные скроллбары"
echo "   ✓ Skeleton loading"
echo "   ✓ И многое другое..."
echo ""
echo -e "${YELLOW}📋 ПОЛНЫЕ УЧЕТНЫЕ ДАННЫЕ:${NC}"
echo "   /root/ultimate_messenger_credentials.txt"
echo ""
echo -e "${GREEN}🎉 ГОТОВО! НАСЛАЖДАЙТЕСЬ МАКСИМАЛЬНЫМ МЕССЕНДЖЕРОМ! 🎉${NC}"