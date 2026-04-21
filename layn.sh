#!/bin/bash

# ============================================
# VISION TV - АВТОМАТИЧЕСКАЯ УСТАНОВКА НА VDS
# ============================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Функция для красивого вывода
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║     ██╗   ██╗██╗███████╗██╗ ██████╗ ███╗   ██╗               ║"
    echo "║     ██║   ██║██║██╔════╝██║██╔═══██╗████╗  ██║               ║"
    echo "║     ██║   ██║██║███████╗██║██║   ██║██╔██╗ ██║               ║"
    echo "║     ╚██╗ ██╔╝██║╚════██║██║██║   ██║██║╚██╗██║               ║"
    echo "║      ╚████╔╝ ██║███████║██║╚██████╔╝██║ ╚████║               ║"
    echo "║       ╚═══╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝               ║"
    echo "║                                                              ║"
    echo "║                  АВТОМАТИЧЕСКАЯ УСТАНОВКА                    ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BLUE}[ШАГ $1]${NC} ${WHITE}$2${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Запустите скрипт от root (sudo ./install.sh)"
        exit 1
    fi
}

# Сбор информации от пользователя
collect_info() {
    print_header
    
    echo -e "${YELLOW}📋 НАСТРОЙКА САЙТА${NC}\n"
    
    # Название сайта
    echo -e "${WHITE}Введите название сайта:${NC}"
    echo -e "${CYAN}(например: VISION TV, Мой Телеканал, Super Stream)${NC}"
    read -p "Название: " SITE_NAME
    
    if [ -z "$SITE_NAME" ]; then
        SITE_NAME="VISION TV"
        print_warning "Название не указано, используется: $SITE_NAME"
    fi
    
    echo ""
    
    # Домен
    echo -e "${WHITE}Введите домен сайта:${NC}"
    echo -e "${CYAN}(например: example.com, tv.mysite.ru)${NC}"
    read -p "Домен: " DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        print_error "Домен обязателен!"
        exit 1
    fi
    
    echo ""
    
    # Email для SSL
    echo -e "${WHITE}Введите email для SSL сертификата:${NC}"
    echo -e "${CYAN}(для уведомлений об истечении сертификата)${NC}"
    read -p "Email: " SSL_EMAIL
    
    if [ -z "$SSL_EMAIL" ]; then
        SSL_EMAIL="admin@$DOMAIN"
        print_warning "Email не указан, используется: $SSL_EMAIL"
    fi
    
    echo ""
    
    # Порт
    echo -e "${WHITE}Введите порт для сайта (по умолчанию 80/443):${NC}"
    read -p "Порт [80]: " CUSTOM_PORT
    
    if [ -z "$CUSTOM_PORT" ]; then
        CUSTOM_PORT="80"
    fi
    
    echo ""
    
    # Установка SSL
    echo -e "${WHITE}Установить SSL сертификат (Let's Encrypt)?${NC}"
    echo -e "${CYAN}1) Да, установить HTTPS${NC}"
    echo -e "${CYAN}2) Нет, только HTTP${NC}"
    read -p "Выбор [1]: " SSL_CHOICE
    
    case $SSL_CHOICE in
        2) INSTALL_SSL=false ;;
        *) INSTALL_SSL=true ;;
    esac
    
    echo ""
    
    # Подтверждение
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}Проверьте введенные данные:${NC}"
    echo -e "  📺 Название сайта: ${GREEN}$SITE_NAME${NC}"
    echo -e "  🌐 Домен:         ${GREEN}$DOMAIN${NC}"
    echo -e "  📧 Email SSL:      ${GREEN}$SSL_EMAIL${NC}"
    echo -e "  🔌 Порт:           ${GREEN}$CUSTOM_PORT${NC}"
    echo -e "  🔒 Установка SSL:  ${GREEN}$([ "$INSTALL_SSL" = true ] && echo "Да" || echo "Нет")${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    
    echo ""
    read -p "Всё верно? Продолжить установку? (y/n) [y]: " CONFIRM
    
    if [[ "$CONFIRM" =~ ^[Nn] ]]; then
        print_error "Установка отменена"
        exit 0
    fi
}

# Установка зависимостей
install_dependencies() {
    print_step "1/7" "Установка системных зависимостей"
    
    apt update -qq
    apt upgrade -y -qq
    
    print_info "Установка Nginx, PHP и дополнительных пакетов..."
    apt install -y -qq \
        nginx \
        php8.1-fpm \
        php8.1-cli \
        php8.1-curl \
        php8.1-mbstring \
        php8.1-xml \
        php8.1-zip \
        php8.1-gd \
        git \
        unzip \
        curl \
        wget \
        certbot \
        python3-certbot-nginx \
        ufw \
        fail2ban \
        htop \
        2>/dev/null
    
    # Определяем версию PHP
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    
    print_success "Зависимости установлены (PHP $PHP_VERSION)"
}

# Создание структуры проекта
create_project_structure() {
    print_step "2/7" "Создание структуры проекта"
    
    PROJECT_DIR="/var/www/vision"
    
    mkdir -p "$PROJECT_DIR"/{api,cache,logs,css,js,images,nginx}
    
    print_success "Директория проекта создана: $PROJECT_DIR"
}

# Генерация файлов сайта
generate_files() {
    print_step "3/7" "Генерация файлов сайта"
    
    PROJECT_DIR="/var/www/vision"
    
    # Главная страница
    cat > "$PROJECT_DIR/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta name="description" content="SITE_DESCRIPTION">
    <title>SITE_NAME — Премиум телевидение</title>
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Crect width='100' height='100' rx='20' fill='%23ff5e3a'/%3E%3Ctext x='50' y='70' font-size='50' text-anchor='middle' fill='white' font-family='Arial'%3E📺%3C/text%3E%3C/svg%3E">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link href="https://cdn.plyr.io/3.7.8/plyr.css" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        :root {
            --primary: #ff5e3a;
            --primary-dark: #d9381e;
            --bg-dark: #0a0e17;
            --bg-card: rgba(12, 19, 30, 0.8);
            --border-color: rgba(255, 255, 255, 0.06);
            --text-primary: #e8edf5;
            --text-secondary: #b9c7d9;
            --sidebar-width: 280px;
        }
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg-dark);
            color: var(--text-primary);
            line-height: 1.5;
            overflow-x: hidden;
            min-height: 100vh;
        }
        .app { display: flex; min-height: 100vh; }
        .sidebar {
            width: var(--sidebar-width);
            background: rgba(8, 13, 22, 0.95);
            backdrop-filter: blur(24px);
            border-right: 1px solid var(--border-color);
            position: fixed;
            height: 100vh;
            z-index: 100;
            overflow-y: auto;
        }
        .sidebar-header {
            padding: 28px 24px;
            border-bottom: 1px solid var(--border-color);
        }
        .logo {
            display: flex;
            align-items: center;
            gap: 14px;
        }
        .logo-icon {
            width: 48px;
            height: 48px;
            background: linear-gradient(145deg, var(--primary), var(--primary-dark));
            border-radius: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 24px;
            color: white;
        }
        .logo-text {
            font-size: 24px;
            font-weight: 800;
            background: linear-gradient(120deg, #fff, #ffb347);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .main {
            flex: 1;
            margin-left: var(--sidebar-width);
            padding: 24px 32px 40px;
        }
        .top-bar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 28px;
            background: rgba(10, 16, 26, 0.6);
            backdrop-filter: blur(16px);
            padding: 14px 24px;
            border-radius: 60px;
            border: 1px solid var(--border-color);
        }
        .site-title {
            font-size: 28px;
            font-weight: 700;
            background: linear-gradient(120deg, #fff, #ffb347);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .player-card {
            background: linear-gradient(135deg, #0c1320 0%, #050a12 100%);
            border-radius: 32px;
            overflow: hidden;
            margin-bottom: 32px;
            border: 1px solid var(--border-color);
        }
        .player-header {
            padding: 20px 28px;
            background: rgba(0, 0, 0, 0.3);
            backdrop-filter: blur(16px);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .video-wrapper {
            position: relative;
            width: 100%;
            background: #000;
        }
        #player {
            width: 100%;
            aspect-ratio: 16 / 9;
        }
        .channels-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 20px;
        }
        .channel-card {
            background: var(--bg-card);
            backdrop-filter: blur(12px);
            border: 1px solid var(--border-color);
            border-radius: 26px;
            padding: 20px;
            cursor: pointer;
            transition: all 0.2s;
        }
        .channel-card:hover {
            transform: translateY(-4px);
            border-color: rgba(255, 94, 58, 0.3);
        }
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 30px;
            font-size: 12px;
            font-weight: 600;
            background: rgba(16, 185, 129, 0.15);
            color: #10b981;
            margin-bottom: 12px;
        }
        .channel-name {
            font-size: 18px;
            font-weight: 700;
            margin-bottom: 8px;
        }
        .channel-meta {
            font-size: 12px;
            color: var(--text-secondary);
        }
        .toast {
            position: fixed;
            bottom: 24px;
            right: 24px;
            background: #1a2538;
            padding: 14px 24px;
            border-radius: 50px;
            border-left: 4px solid var(--primary);
            animation: slideIn 0.3s ease;
            z-index: 1000;
        }
        @keyframes slideIn {
            from { opacity: 0; transform: translateX(50px); }
            to { opacity: 1; transform: translateX(0); }
        }
        @media (max-width: 768px) {
            :root { --sidebar-width: 0px; }
            .sidebar { transform: translateX(-100%); }
            .main { margin-left: 0; padding: 16px; }
        }
    </style>
</head>
<body>
    <div id="toastContainer"></div>
    
    <div class="app">
        <aside class="sidebar">
            <div class="sidebar-header">
                <div class="logo">
                    <div class="logo-icon">📺</div>
                    <div class="logo-text">SITE_NAME_SHORT</div>
                </div>
            </div>
        </aside>

        <main class="main">
            <div class="top-bar">
                <div class="site-title">SITE_NAME</div>
                <span id="channelCount" style="color: var(--primary);">Загрузка...</span>
            </div>

            <div class="player-card">
                <div class="player-header">
                    <span id="currentChannel">Выберите канал</span>
                    <span id="channelInfo"></span>
                </div>
                <div class="video-wrapper">
                    <video id="player" controls playsinline></video>
                </div>
            </div>

            <div class="channels-grid" id="channelsGrid">
                <div style="grid-column:1/-1; text-align:center; padding:40px;">
                    <i class="fas fa-spinner fa-spin"></i> Загрузка каналов...
                </div>
            </div>
        </main>
    </div>

    <script src="https://cdn.plyr.io/3.7.8/plyr.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js"></script>
    <script>
        const CONFIG = {
            API_URL: '/api/proxy.php',
            SITE_NAME: 'SITE_NAME'
        };

        let channels = [];
        let plyr = null;
        let hls = null;
        
        const player = document.getElementById('player');
        const channelsGrid = document.getElementById('channelsGrid');
        const channelCount = document.getElementById('channelCount');
        const currentChannelEl = document.getElementById('currentChannel');
        const channelInfo = document.getElementById('channelInfo');
        const toastContainer = document.getElementById('toastContainer');

        function showToast(msg) {
            const toast = document.createElement('div');
            toast.className = 'toast';
            toast.textContent = msg;
            toastContainer.appendChild(toast);
            setTimeout(() => toast.remove(), 3000);
        }

        function formatName(url) {
            try {
                const match = url.match(/\/([^\/]+?)\/playlist\.m3u8/i);
                if (match?.[1]) {
                    return decodeURIComponent(match[1]).replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
                }
            } catch {}
            return 'Канал';
        }

        async function loadChannels() {
            try {
                const response = await fetch(CONFIG.API_URL);
                const data = await response.json();
                
                if (data.channels) {
                    channels = data.channels;
                    renderChannels();
                    channelCount.textContent = channels.length + ' каналов';
                    showToast('Загружено ' + channels.length + ' каналов');
                }
            } catch (error) {
                console.error('Ошибка:', error);
                channelsGrid.innerHTML = '<div style="grid-column:1/-1; text-align:center;">❌ Ошибка загрузки</div>';
            }
        }

        function renderChannels() {
            if (!channels.length) {
                channelsGrid.innerHTML = '<div style="grid-column:1/-1; text-align:center;">📡 Каналы не найдены</div>';
                return;
            }

            channelsGrid.innerHTML = channels.map(ch => `
                <div class="channel-card" data-id="${ch.id}" data-url="${ch.url}" data-name="${ch.name}">
                    <div class="status-badge">
                        <i class="fas fa-circle" style="font-size: 8px;"></i> ONLINE
                    </div>
                    <div class="channel-name">${ch.name}</div>
                    <div class="channel-meta">ID: ${ch.id} • ${ch.type === 'tv' ? 'ТВ' : 'Радио'}</div>
                </div>
            `).join('');

            document.querySelectorAll('.channel-card').forEach(card => {
                card.addEventListener('click', () => {
                    playChannel(card.dataset.url, card.dataset.name, card.dataset.id);
                });
            });
        }

        function playChannel(url, name, id) {
            currentChannelEl.textContent = name;
            channelInfo.textContent = 'ID: ' + id;
            
            if (hls) {
                hls.destroy();
                hls = null;
            }

            if (Hls.isSupported()) {
                hls = new Hls();
                hls.loadSource(url);
                hls.attachMedia(player);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    player.play().catch(() => {});
                });
            } else if (player.canPlayType('application/vnd.apple.mpegurl')) {
                player.src = url;
                player.play().catch(() => {});
            }

            if (!plyr) {
                plyr = new Plyr(player);
            }
            
            showToast('Сейчас играет: ' + name);
        }

        loadChannels();
    </script>
</body>
</html>
HTMLEOF

    # Замена плейсхолдеров
    SITE_NAME_SHORT=$(echo "$SITE_NAME" | cut -d' ' -f1)
    sed -i "s/SITE_NAME/$SITE_NAME/g" "$PROJECT_DIR/index.html"
    sed -i "s/SITE_NAME_SHORT/$SITE_NAME_SHORT/g" "$PROJECT_DIR/index.html"
    sed -i "s/SITE_DESCRIPTION/$SITE_NAME — премиум телевидение и радио онлайн/g" "$PROJECT_DIR/index.html"
    
    # API прокси
    cat > "$PROJECT_DIR/api/proxy.php" << 'PHPEOF'
<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

define('API_BASE', 'https://api.mediabay.tv/v2/channels/thread/');
define('CACHE_DIR', __DIR__ . '/../cache/');
define('CACHE_TIME', 3600);
define('SCAN_START', 1);
define('SCAN_END', 800);
define('BATCH_SIZE', 10);
define('REQUEST_DELAY', 100000);

if (!is_dir(CACHE_DIR)) {
    mkdir(CACHE_DIR, 0755, true);
}

function formatChannelName($url) {
    if (preg_match('/\/([^\/]+?)\/playlist\.m3u8/i', $url, $matches)) {
        $name = urldecode($matches[1]);
        $name = str_replace('_', ' ', $name);
        $name = ucwords($name);
        return $name ?: 'Канал';
    }
    return 'Канал';
}

function detectType($name, $url) {
    $lower = strtolower($name . ' ' . $url);
    $radioWords = ['radio', 'радио', 'fm', 'music', 'музык', 'audio', 'хит', 'hit'];
    
    foreach ($radioWords as $word) {
        if (strpos($lower, $word) !== false) {
            return 'radio';
        }
    }
    return 'tv';
}

function checkChannel($id) {
    $cacheFile = CACHE_DIR . "channel_{$id}.json";
    
    if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < CACHE_TIME) {
        return json_decode(file_get_contents($cacheFile), true);
    }
    
    $url = API_BASE . $id;
    $context = stream_context_create([
        'http' => [
            'timeout' => 5,
            'header' => "Accept: application/json\r\n"
        ]
    ]);
    
    $response = @file_get_contents($url, false, $context);
    
    if ($response === false) {
        return null;
    }
    
    $data = json_decode($response, true);
    
    if (isset($data['status']) && $data['status'] === 'ok' && isset($data['data'][0]['threadAddress'])) {
        $streamUrl = $data['data'][0]['threadAddress'];
        
        if (strpos($streamUrl, '.m3u8') !== false) {
            $name = formatChannelName($streamUrl);
            $channel = [
                'id' => (string)$id,
                'url' => $streamUrl,
                'name' => $name,
                'type' => detectType($name, $streamUrl)
            ];
            
            file_put_contents($cacheFile, json_encode($channel));
            
            return $channel;
        }
    }
    
    return null;
}

function scanChannels($start, $end) {
    $channels = [];
    $cacheFile = CACHE_DIR . "scan_{$start}_{$end}.json";
    
    if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < CACHE_TIME) {
        return json_decode(file_get_contents($cacheFile), true);
    }
    
    for ($id = $start; $id <= $end; $id++) {
        $channel = checkChannel($id);
        if ($channel) {
            $channels[] = $channel;
        }
        usleep(REQUEST_DELAY);
    }
    
    file_put_contents($cacheFile, json_encode($channels));
    
    return $channels;
}

$start = isset($_GET['start']) ? (int)$_GET['start'] : SCAN_START;
$end = isset($_GET['end']) ? (int)$_GET['end'] : SCAN_END;

$channels = scanChannels($start, min($end, SCAN_END));

echo json_encode([
    'success' => true,
    'channels' => $channels,
    'total' => count($channels)
]);
?>
PHPEOF

    # Создание robots.txt
    cat > "$PROJECT_DIR/robots.txt" << 'ROBOTSEOF'
User-agent: *
Allow: /
Disallow: /cache/
Disallow: /api/
Sitemap: https://DOMAIN_PLACEHOLDER/sitemap.xml
ROBOTSEOF
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "$PROJECT_DIR/robots.txt"
    
    print_success "Файлы сайта сгенерированы"
}

# Настройка прав
set_permissions() {
    print_step "4/7" "Настройка прав доступа"
    
    PROJECT_DIR="/var/www/vision"
    
    chown -R www-data:www-data "$PROJECT_DIR"
    chmod -R 755 "$PROJECT_DIR"
    chmod 777 "$PROJECT_DIR/cache"
    chmod 777 "$PROJECT_DIR/logs"
    
    print_success "Права установлены"
}

# Настройка Nginx
configure_nginx() {
    print_step "5/7" "Настройка Nginx"
    
    PROJECT_DIR="/var/www/vision"
    
    cat > "/etc/nginx/sites-available/vision.conf" << NGINXEOF
server {
    listen $CUSTOM_PORT;
    listen [::]:$CUSTOM_PORT;
    
    server_name $DOMAIN www.$DOMAIN;
    
    root $PROJECT_DIR;
    index index.html index.php;
    
    access_log /var/log/nginx/vision-access.log;
    error_log /var/log/nginx/vision-error.log;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location /cache/ {
        deny all;
        return 403;
    }
    
    location /api/ {
        allow all;
    }
    
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
}
NGINXEOF

    # Активация сайта
    ln -sf "/etc/nginx/sites-available/vision.conf" "/etc/nginx/sites-enabled/vision.conf"
    rm -f "/etc/nginx/sites-enabled/default"
    
    # Проверка конфигурации
    nginx -t
    if [ $? -ne 0 ]; then
        print_error "Ошибка в конфигурации Nginx!"
        exit 1
    fi
    
    systemctl reload nginx
    systemctl restart php8.1-fpm
    
    print_success "Nginx настроен"
}

# Установка SSL
install_ssl() {
    if [ "$INSTALL_SSL" = true ]; then
        print_step "6/7" "Установка SSL сертификата"
        
        certbot --nginx \
            -d "$DOMAIN" \
            -d "www.$DOMAIN" \
            --non-interactive \
            --agree-tos \
            --email "$SSL_EMAIL" \
            --redirect
        
        if [ $? -eq 0 ]; then
            print_success "SSL сертификат установлен"
        else
            print_warning "Не удалось установить SSL. Сайт будет работать по HTTP"
        fi
    else
        print_step "6/7" "SSL пропущен (по выбору пользователя)"
    fi
}

# Настройка безопасности
configure_security() {
    print_step "7/7" "Настройка безопасности"
    
    # UFW
    ufw allow 22 comment 'SSH'
    ufw allow 80 comment 'HTTP'
    ufw allow 443 comment 'HTTPS'
    echo "y" | ufw enable 2>/dev/null
    
    # Fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    print_success "Безопасность настроена"
}

# Финальная информация
show_final_info() {
    clear
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║                    ✅ УСТАНОВКА ЗАВЕРШЕНА!                    ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "\n${WHITE}📺 ${SITE_NAME} успешно установлен!${NC}\n"
    
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}ИНФОРМАЦИЯ О САЙТЕ:${NC}"
    echo -e "  📁 Директория:     ${GREEN}/var/www/vision/${NC}"
    echo -e "  🌐 URL:             ${GREEN}$([ "$INSTALL_SSL" = true ] && echo "https://$DOMAIN" || echo "http://$DOMAIN")${NC}"
    echo -e "  📧 Email:           ${GREEN}$SSL_EMAIL${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${WHITE}ПОЛЕЗНЫЕ КОМАНДЫ:${NC}"
    echo -e "  📊 Статус Nginx:    ${CYAN}systemctl status nginx${NC}"
    echo -e "  📊 Статус PHP:      ${CYAN}systemctl status php8.1-fpm${NC}"
    echo -e "  📋 Логи Nginx:      ${CYAN}tail -f /var/log/nginx/vision-error.log${NC}"
    echo -e "  🔄 Перезапуск:      ${CYAN}systemctl restart nginx php8.1-fpm${NC}"
    echo -e "  🗑️  Очистка кэша:   ${CYAN}rm -rf /var/www/vision/cache/*${NC}"
    
    echo -e "\n${WHITE}НАСТРОЙКА DNS:${NC}"
    echo -e "  Убедитесь, что для домена ${CYAN}$DOMAIN${NC} добавлены записи:"
    echo -e "  ${CYAN}A     @     $(curl -s ifconfig.me)${NC}"
    echo -e "  ${CYAN}A     www   $(curl -s ifconfig.me)${NC}"
    
    echo -e "\n${GREEN}🎉 Спасибо за установку VISION TV!${NC}\n"
}

# Основная функция
main() {
    check_root
    collect_info
    install_dependencies
    create_project_structure
    generate_files
    set_permissions
    configure_nginx
    install_ssl
    configure_security
    show_final_info
}

# Запуск
main