#!/bin/bash

# ============================================
# VISION TV - АВТОМАТИЧЕСКИЙ УСТАНОВЩИК
# Версия: 3.0
# ============================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Конфигурация по умолчанию
SITE_NAME="VISION TV"
SITE_DOMAIN=""
ADMIN_EMAIL=""
SSL_ENABLED="y"
INSTALL_DIR="/var/www/vision-tv"

# Логотип
show_logo() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║    ██╗   ██╗██╗███████╗██╗ ██████╗ ███╗   ██╗                    ║
║    ██║   ██║██║██╔════╝██║██╔═══██╗████╗  ██║                    ║
║    ██║   ██║██║███████╗██║██║   ██║██╔██╗ ██║                    ║
║    ╚██╗ ██╔╝██║╚════██║██║██║   ██║██║╚██╗██║                    ║
║     ╚████╔╝ ██║███████║██║╚██████╔╝██║ ╚████║                    ║
║      ╚═══╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝                    ║
║                                                                   ║
║                    ПРЕМИУМ ТЕЛЕВИДЕНИЕ                            ║
║                                                                   ║
║              Автоматическая установка на VDS                      ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Проверка root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Ошибка: Установка требует права root!${NC}"
        echo -e "${YELLOW}💡 Запустите: sudo bash install.sh${NC}"
        exit 1
    fi
}

# Определение ОС
detect_os() {
    echo -e "${BLUE}🔍 Определение операционной системы...${NC}"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VER=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+')
    else
        echo -e "${RED}❌ Не удалось определить ОС${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Обнаружена ОС: $OS $VER${NC}"
}

# Интерактивная настройка
interactive_setup() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}            🔧 НАСТРОЙКА УСТАНОВКИ                    ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # Название сайта
    echo -e "${YELLOW}📝 Введите название сайта:${NC}"
    echo -e "${WHITE}   (по умолчанию: VISION TV)${NC}"
    read -p "   Название: " input_site_name
    SITE_NAME=${input_site_name:-"VISION TV"}
    
    # Домен
    echo -e "\n${YELLOW}🌐 Введите домен для сайта:${NC}"
    echo -e "${WHITE}   (например: tv.example.com или оставьте пустым для автоопределения)${NC}"
    read -p "   Домен: " input_domain
    
    if [ -z "$input_domain" ]; then
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "localhost")
        SITE_DOMAIN="${SERVER_IP}.sslip.io"
        echo -e "${BLUE}   ℹ️  Используется: ${SITE_DOMAIN}${NC}"
    else
        SITE_DOMAIN="$input_domain"
    fi
    
    # Email администратора
    echo -e "\n${YELLOW}📧 Введите email администратора:${NC}"
    echo -e "${WHITE}   (для SSL сертификата и восстановления доступа)${NC}"
    read -p "   Email: " input_email
    
    if [ -z "$input_email" ]; then
        ADMIN_EMAIL="admin@${SITE_DOMAIN}"
        echo -e "${BLUE}   ℹ️  Используется: ${ADMIN_EMAIL}${NC}"
    else
        ADMIN_EMAIL="$input_email"
    fi
    
    # SSL
    echo -e "\n${YELLOW}🔒 Использовать HTTPS (Let's Encrypt SSL)?${NC}"
    echo -e "${WHITE}   (y/n, по умолчанию: y)${NC}"
    read -p "   Включить SSL: " input_ssl
    SSL_ENABLED=${input_ssl:-"y"}
    
    # Пароль администратора
    ADMIN_PASSWORD=$(openssl rand -base64 16)
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}                 📋 ПАРАМЕТРЫ УСТАНОВКИ                ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Название сайта:${NC} ${WHITE}$SITE_NAME${NC}"
    echo -e "${GREEN}Домен:${NC}          ${WHITE}$SITE_DOMAIN${NC}"
    echo -e "${GREEN}Email админа:${NC}    ${WHITE}$ADMIN_EMAIL${NC}"
    echo -e "${GREEN}SSL:${NC}            ${WHITE}$([ "$SSL_ENABLED" = "y" ] && echo "Включен" || echo "Отключен")${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${YELLOW}Продолжить установку? (y/n)${NC}"
    read -p "   Ваш выбор: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Установка отменена${NC}"
        exit 0
    fi
}

# Установка зависимостей
install_dependencies() {
    echo -e "\n${BLUE}📦 Установка системных зависимостей...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq curl wget git nginx certbot python3-certbot-nginx \
                                  software-properties-common apt-transport-https \
                                  ca-certificates gnupg lsb-release ufw fail2ban \
                                  htop net-tools 2>/dev/null
            ;;
        centos|rhel|fedora)
            yum update -y -q
            yum install -y -q curl wget git nginx certbot python3-certbot-nginx \
                              yum-utils device-mapper-persistent-data lvm2 \
                              epel-release htop net-tools 2>/dev/null
            ;;
        *)
            echo -e "${YELLOW}⚠️  Неизвестная ОС, пропускаем установку пакетов${NC}"
            ;;
    esac
    
    echo -e "${GREEN}✅ Системные зависимости установлены${NC}"
}

# Установка Docker
install_docker() {
    echo -e "\n${BLUE}🐳 Установка Docker и Docker Compose...${NC}"
    
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✅ Docker уже установлен${NC}"
    else
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}✅ Docker установлен${NC}"
    fi
    
    if command -v docker-compose &> /dev/null; then
        echo -e "${GREEN}✅ Docker Compose уже установлен${NC}"
    else
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}✅ Docker Compose установлен${NC}"
    fi
}

# Создание структуры проекта
create_project_structure() {
    echo -e "\n${BLUE}📁 Создание структуры проекта...${NC}"
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    mkdir -p {nginx,frontend,backend,database,ssl,logs/{nginx,backend},uploads}
    
    echo -e "${GREEN}✅ Структура создана${NC}"
}

# Генерация паролей и конфигурации
generate_config() {
    echo -e "\n${BLUE}⚙️  Генерация конфигурации...${NC}"
    
    DB_PASSWORD=$(openssl rand -base64 32)
    JWT_SECRET=$(openssl rand -base64 48)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    API_KEY=$(openssl rand -hex 32)
    
    cat > .env << EOF
# ============================================
# VISION TV - КОНФИГУРАЦИЯ
# ============================================

# Сайт
SITE_NAME="${SITE_NAME}"
SITE_DOMAIN="${SITE_DOMAIN}"
SITE_URL="http${SSL_ENABLED:+"s"}://${SITE_DOMAIN}"

# SSL
SSL_ENABLED=${SSL_ENABLED}
SSL_EMAIL="${ADMIN_EMAIL}"

# База данных
POSTGRES_DB=vision_tv
POSTGRES_USER=vision_user
POSTGRES_PASSWORD=${DB_PASSWORD}
DATABASE_URL=postgresql://vision_user:${DB_PASSWORD}@postgres:5432/vision_tv

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379

# JWT
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRE=24h
JWT_REFRESH_EXPIRE=7d

# API
API_KEY=${API_KEY}
API_RATE_LIMIT=100

# Администратор
ADMIN_USERNAME=admin
ADMIN_PASSWORD=${ADMIN_PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}

# Порты
NGINX_PORT=80
NGINX_SSL_PORT=443
BACKEND_PORT=3000
POSTGRES_PORT=5432
REDIS_PORT=6379

# Почта (для уведомлений)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=""
SMTP_PASS=""
SMTP_FROM="noreply@${SITE_DOMAIN}"

# Логи
LOG_LEVEL=info
LOG_MAX_SIZE=10m
LOG_MAX_FILES=7
EOF

    echo -e "${GREEN}✅ Конфигурация создана${NC}"
}

# Создание docker-compose.yml
create_docker_compose() {
    echo -e "\n${BLUE}🐳 Создание Docker Compose конфигурации...${NC}"
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    container_name: vision-nginx
    restart: unless-stopped
    ports:
      - "${NGINX_PORT}:80"
      - "${NGINX_SSL_PORT}:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./frontend:/var/www/html:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - backend
    networks:
      - vision-network

  backend:
    build: ./backend
    container_name: vision-backend
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - NODE_ENV=production
    volumes:
      - ./backend:/app
      - ./uploads:/app/uploads
      - /app/node_modules
      - ./logs/backend:/app/logs
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - vision-network

  postgres:
    image: postgres:15-alpine
    container_name: vision-postgres
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - vision-network

  redis:
    image: redis:7-alpine
    container_name: vision-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - vision-network

volumes:
  postgres_data:
  redis_data:

networks:
  vision-network:
    driver: bridge
EOF

    echo -e "${GREEN}✅ Docker Compose создан${NC}"
}

# Создание Nginx конфигурации
create_nginx_config() {
    echo -e "\n${BLUE}🔧 Создание конфигурации Nginx...${NC}"
    
    cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Логи
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;
    
    # Оптимизация
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # Gzip сжатие
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml application/atom+xml image/svg+xml 
               text/x-js text/x-cross-domain-policy application/x-font-ttf 
               application/x-font-opentype application/vnd.ms-fontobject 
               image/x-icon;
    
    # Лимиты
    client_max_body_size 50M;
    client_body_buffer_size 128k;
    
    # Безопасность
    server_tokens off;
    
    # Основной сервер
    server {
        listen 80;
        listen [::]:80;
        server_name _;
        
        # Редирект на HTTPS если включен
        # (будет добавлен позже)
        
        # Основной сайт
        location / {
            root /var/www/html;
            try_files $uri $uri/ /index.html;
            index index.html index.htm;
        }
        
        # API
        location /api/ {
            proxy_pass http://backend:3000/api/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_buffering off;
            proxy_read_timeout 86400;
        }
        
        # Статические файлы с кэшированием
        location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff2?|ttf|eot)$ {
            root /var/www/html;
            expires 1y;
            add_header Cache-Control "public, immutable";
            add_header Vary Accept-Encoding;
        }
        
        # Загрузки
        location /uploads/ {
            alias /app/uploads/;
            expires 30d;
            add_header Cache-Control "public";
        }
        
        # Здоровье сервера
        location /health {
            access_log off;
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

    echo -e "${GREEN}✅ Nginx конфигурация создана${NC}"
}

# Создание базы данных
create_database_schema() {
    echo -e "\n${BLUE}🗄️  Создание схемы базы данных...${NC}"
    
    cat > database/init.sql << 'EOF'
-- ============================================
-- VISION TV - СХЕМА БАЗЫ ДАННЫХ
-- ============================================

-- Пользователи
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    avatar_url TEXT,
    phone VARCHAR(20),
    role VARCHAR(50) DEFAULT 'user',
    subscription_plan VARCHAR(50) DEFAULT 'free',
    subscription_expires TIMESTAMP,
    auto_renew BOOLEAN DEFAULT false,
    language VARCHAR(10) DEFAULT 'ru',
    timezone VARCHAR(50) DEFAULT 'Europe/Moscow',
    email_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    is_banned BOOLEAN DEFAULT false
);

-- Сессии пользователей
CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(500),
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

-- Каналы
CREATE TABLE IF NOT EXISTS channels (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    url TEXT NOT NULL,
    type VARCHAR(20) CHECK (type IN ('tv', 'radio')),
    logo TEXT,
    category VARCHAR(100),
    country VARCHAR(50),
    language VARCHAR(50),
    description TEXT,
    epg_url TEXT,
    stream_quality VARCHAR(20) DEFAULT 'auto',
    viewer_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Избранное
CREATE TABLE IF NOT EXISTS favorites (
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    channel_id INTEGER REFERENCES channels(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, channel_id)
);

-- История просмотров
CREATE TABLE IF NOT EXISTS viewing_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    channel_id INTEGER REFERENCES channels(id) ON DELETE CASCADE,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP,
    duration INTEGER,
    ip_address INET,
    user_agent TEXT,
    device_type VARCHAR(50)
);

-- Достижения
CREATE TABLE IF NOT EXISTS achievements (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    category VARCHAR(50),
    requirement_type VARCHAR(50),
    requirement_value INTEGER,
    icon VARCHAR(50),
    points INTEGER DEFAULT 0,
    is_secret BOOLEAN DEFAULT false
);

-- Достижения пользователей
CREATE TABLE IF NOT EXISTS user_achievements (
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    achievement_id INTEGER REFERENCES achievements(id) ON DELETE CASCADE,
    achieved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    progress INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, achievement_id)
);

-- Настройки пользователей
CREATE TABLE IF NOT EXISTS user_settings (
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    settings JSONB DEFAULT '{}',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Системные настройки
CREATE TABLE IF NOT EXISTS system_settings (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by INTEGER REFERENCES users(id)
);

-- Логи системы
CREATE TABLE IF NOT EXISTS system_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(20),
    category VARCHAR(50),
    message TEXT,
    details JSONB,
    ip_address INET,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Аудит действий
CREATE TABLE IF NOT EXISTS audit_log (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100),
    entity_type VARCHAR(50),
    entity_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Планы подписок
CREATE TABLE IF NOT EXISTS subscription_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    price DECIMAL(10,2),
    currency VARCHAR(3) DEFAULT 'RUB',
    duration_days INTEGER,
    features JSONB,
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0
);

-- Платежи
CREATE TABLE IF NOT EXISTS payments (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    plan_id INTEGER REFERENCES subscription_plans(id),
    amount DECIMAL(10,2),
    currency VARCHAR(3),
    status VARCHAR(20),
    payment_method VARCHAR(50),
    transaction_id VARCHAR(255),
    paid_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- API ключи
CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100),
    key_hash VARCHAR(255) UNIQUE,
    permissions JSONB,
    last_used TIMESTAMP,
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для оптимизации
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_channels_type ON channels(type);
CREATE INDEX IF NOT EXISTS idx_channels_active ON channels(is_active);
CREATE INDEX IF NOT EXISTS idx_channels_category ON channels(category);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON viewing_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_channel ON viewing_sessions(channel_id);
CREATE INDEX IF NOT EXISTS idx_sessions_started ON viewing_sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_favorites_user ON favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);
CREATE INDEX IF NOT EXISTS idx_logs_level ON system_logs(level);
CREATE INDEX IF NOT EXISTS idx_logs_created ON system_logs(created_at);

-- Триггер для обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_channels_updated_at BEFORE UPDATE ON channels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Базовые достижения
INSERT INTO achievements (name, description, category, requirement_type, requirement_value, icon, points) VALUES
('Первые шаги', 'Зарегистрируйтесь на платформе', 'account', 'registration', 1, 'fa-user-plus', 10),
('Первые 10 часов', 'Просмотрите 10 часов контента', 'viewing', 'total_hours', 10, 'fa-clock', 100),
('Коллекционер', 'Добавьте 10 каналов в избранное', 'favorites', 'favorites_count', 10, 'fa-heart', 50),
('Ранняя пташка', 'Заходите на платформу 7 дней подряд', 'streak', 'daily_streak', 7, 'fa-calendar-check', 75),
('Золотой зритель', 'Просмотрите 100 часов контента', 'viewing', 'total_hours', 100, 'fa-crown', 500),
('Марафонец', 'Заходите на платформу 30 дней подряд', 'streak', 'daily_streak', 30, 'fa-trophy', 300),
('Исследователь', 'Посмотрите 50 разных каналов', 'discovery', 'unique_channels', 50, 'fa-compass', 200),
('Ночной дозор', 'Смотрите контент после полуночи', 'special', 'night_views', 10, 'fa-moon', 150)
ON CONFLICT DO NOTHING;

-- Планы подписок
INSERT INTO subscription_plans (name, description, price, duration_days, features, sort_order) VALUES
('Free', 'Бесплатный доступ', 0, 0, 
 '{"ads": true, "quality": "HD", "devices": 1, "recording": false, "downloads": false}'::jsonb, 1),
('Premium', 'Расширенные возможности', 399, 30, 
 '{"ads": false, "quality": "4K", "devices": 5, "recording": true, "downloads": true}'::jsonb, 2),
('Family', 'Для всей семьи', 699, 30, 
 '{"ads": false, "quality": "4K", "devices": 10, "recording": true, "downloads": true}'::jsonb, 3)
ON CONFLICT DO NOTHING;

-- Тестовые каналы
INSERT INTO channels (name, url, type, category, country, language, is_active, is_featured) VALUES
('Первый канал', 'https://example.com/1tv.m3u8', 'tv', 'Общие', 'Россия', 'ru', true, true),
('Россия 1', 'https://example.com/russia1.m3u8', 'tv', 'Общие', 'Россия', 'ru', true, true),
('Матч ТВ', 'https://example.com/matchtv.m3u8', 'tv', 'Спорт', 'Россия', 'ru', true, true),
('Discovery Channel', 'https://example.com/discovery.m3u8', 'tv', 'Познавательные', 'США', 'en', true, false),
('National Geographic', 'https://example.com/natgeo.m3u8', 'tv', 'Познавательные', 'США', 'en', true, false),
('Европа Плюс', 'https://example.com/europaplus.m3u8', 'radio', 'Музыка', 'Россия', 'ru', true, true),
('Русское Радио', 'https://example.com/rusradio.m3u8', 'radio', 'Музыка', 'Россия', 'ru', true, true),
('Радио Шансон', 'https://example.com/shanson.m3u8', 'radio', 'Музыка', 'Россия', 'ru', true, false),
('BBC World Service', 'https://example.com/bbc.m3u8', 'radio', 'Новости', 'Великобритания', 'en', true, false)
ON CONFLICT DO NOTHING;
EOF

    echo -e "${GREEN}✅ Схема базы данных создана${NC}"
}

# Создание Backend
create_backend() {
    echo -e "\n${BLUE}📡 Создание Backend API...${NC}"
    
    # package.json
    cat > backend/package.json << 'EOF'
{
  "name": "vision-tv-backend",
  "version": "3.0.0",
  "description": "VISION TV Premium Backend API",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "redis": "^4.6.7",
    "jsonwebtoken": "^9.0.2",
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "express-rate-limit": "^6.10.0",
    "multer": "^1.4.5-lts.1",
    "dotenv": "^16.3.1",
    "joi": "^17.10.2",
    "winston": "^3.10.0",
    "nodemailer": "^6.9.5",
    "axios": "^1.5.0",
    "compression": "^1.7.4",
    "express-validator": "^7.0.1"
  }
}
EOF

    # server.js
    cat > backend/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const rateLimit = require('express-rate-limit');
const { createClient } = require('redis');
const path = require('path');
const fs = require('fs');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Логирование
const winston = require('winston');
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
        new winston.transports.File({ filename: 'logs/combined.log' }),
        new winston.transports.Console({ format: winston.format.simple() })
    ]
});

// Middleware
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'", "https://cdnjs.cloudflare.com", "https://cdn.plyr.io", "https://cdn.jsdelivr.net"],
            styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com", "https://cdnjs.cloudflare.com", "https://cdn.plyr.io"],
            fontSrc: ["'self'", "https://fonts.gstatic.com", "https://cdnjs.cloudflare.com"],
            imgSrc: ["'self'", "data:", "https:"],
            connectSrc: ["'self'", "https://api.mediabay.tv"],
            mediaSrc: ["'self'", "blob:", "https:"],
        }
    }
}));

app.use(cors());
app.use(compression());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// База данных
const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000
});

// Redis
const redis = createClient({
    url: process.env.REDIS_URL
});
redis.connect().catch(err => logger.error('Redis connection error:', err));

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: process.env.API_RATE_LIMIT || 100,
    message: { error: 'Слишком много запросов, попробуйте позже' }
});
app.use('/api/', limiter);

// Передача зависимостей
app.use((req, res, next) => {
    req.pool = pool;
    req.redis = redis;
    req.logger = logger;
    next();
});

// JWT Middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    
    if (!token) {
        return res.status(401).json({ error: 'Требуется авторизация' });
    }
    
    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: 'Недействительный или истекший токен' });
        }
        req.user = user;
        next();
    });
};

// Создание админа при запуске
async function initializeAdmin() {
    try {
        const adminExists = await pool.query(
            'SELECT id FROM users WHERE username = $1',
            [process.env.ADMIN_USERNAME]
        );
        
        if (adminExists.rows.length === 0) {
            const passwordHash = await bcrypt.hash(process.env.ADMIN_PASSWORD, 10);
            await pool.query(
                `INSERT INTO users (username, email, password_hash, full_name, role, email_verified, is_active) 
                 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
                [process.env.ADMIN_USERNAME, process.env.ADMIN_EMAIL, passwordHash, 
                 'Администратор', 'admin', true, true]
            );
            logger.info('✅ Администратор создан');
        }
    } catch (error) {
        logger.error('Ошибка создания администратора:', error);
    }
}

// Health check
app.get('/api/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        timestamp: new Date().toISOString(),
        site_name: process.env.SITE_NAME,
        version: '3.0.0'
    });
});

// Публичная информация о сайте
app.get('/api/site-info', (req, res) => {
    res.json({
        name: process.env.SITE_NAME,
        domain: process.env.SITE_DOMAIN,
        url: process.env.SITE_URL
    });
});

// Регистрация
app.post('/api/auth/register', async (req, res) => {
    try {
        const { username, email, password, full_name } = req.body;
        
        if (!username || !email || !password) {
            return res.status(400).json({ error: 'Все поля обязательны' });
        }
        
        const existingUser = await pool.query(
            'SELECT id FROM users WHERE username = $1 OR email = $2',
            [username, email]
        );
        
        if (existingUser.rows.length > 0) {
            return res.status(400).json({ error: 'Пользователь уже существует' });
        }
        
        const passwordHash = await bcrypt.hash(password, 10);
        
        const result = await pool.query(
            `INSERT INTO users (username, email, password_hash, full_name) 
             VALUES ($1, $2, $3, $4) RETURNING id, username, email, full_name, role, avatar_url`,
            [username, email, passwordHash, full_name]
        );
        
        const user = result.rows[0];
        const token = jwt.sign(
            { id: user.id, username: user.username, role: user.role },
            process.env.JWT_SECRET,
            { expiresIn: process.env.JWT_EXPIRE }
        );
        
        logger.info(`Новый пользователь: ${username}`);
        res.json({ token, user });
    } catch (error) {
        logger.error('Register error:', error);
        res.status(500).json({ error: 'Ошибка сервера' });
    }
});

// Вход
app.post('/api/auth/login', async (req, res) => {
    try {
        const { username, password } = req.body;
        
        const result = await pool.query(
            `SELECT * FROM users WHERE (username = $1 OR email = $1) AND is_active = true AND is_banned = false`,
            [username]
        );
        
        if (result.rows.length === 0) {
            return res.status(401).json({ error: 'Неверные учетные данные' });
        }
        
        const user = result.rows[0];
        const validPassword = await bcrypt.compare(password, user.password_hash);
        
        if (!validPassword) {
            logger.warn(`Неудачная попытка входа: ${username}`);
            return res.status(401).json({ error: 'Неверные учетные данные' });
        }
        
        const token = jwt.sign(
            { id: user.id, username: user.username, role: user.role },
            process.env.JWT_SECRET,
            { expiresIn: process.env.JWT_EXPIRE }
        );
        
        await pool.query('UPDATE users SET last_login = NOW() WHERE id = $1', [user.id]);
        
        const { password_hash, ...userData } = user;
        logger.info(`Успешный вход: ${username}`);
        res.json({ token, user: userData });
    } catch (error) {
        logger.error('Login error:', error);
        res.status(500).json({ error: 'Ошибка сервера' });
    }
});

// Получение каналов
app.get('/api/channels', async (req, res) => {
    try {
        const { type, category, search, limit = 100, offset = 0 } = req.query;
        
        let query = 'SELECT id, name, url, type, logo, category, country FROM channels WHERE is_active = true';
        const params = [];
        
        if (type) {
            query += ' AND type = $' + (params.length + 1);
            params.push(type);
        }
        
        if (category) {
            query += ' AND category = $' + (params.length + 1);
            params.push(category);
        }
        
        if (search) {
            query += ' AND (name ILIKE $' + (params.length + 1) + ' OR category ILIKE $' + (params.length + 1) + ')';
            params.push(`%${search}%`);
        }
        
        query += ' ORDER BY sort_order, name LIMIT $' + (params.length + 1) + ' OFFSET $' + (params.length + 2);
        params.push(limit, offset);
        
        const cacheKey = `channels:${JSON.stringify(req.query)}`;
        const cached = await redis.get(cacheKey);
        
        if (cached) {
            return res.json(JSON.parse(cached));
        }
        
        const result = await pool.query(query, params);
        await redis.setex(cacheKey, 300, JSON.stringify(result.rows));
        
        res.json(result.rows);
    } catch (error) {
        logger.error('Channels error:', error);
        res.status(500).json({ error: 'Ошибка сервера' });
    }
});

// Профиль пользователя
app.get('/api/user/profile', authenticateToken, async (req, res) => {
    try {
        const result = await pool.query(
            `SELECT id, username, email, full_name, avatar_url, phone, role, 
                    subscription_plan, subscription_expires, language, timezone,
                    created_at, last_login
             FROM users WHERE id = $1`,
            [req.user.id]
        );
        
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Пользователь не найден' });
        }
        
        res.json(result.rows[0]);
    } catch (error) {
        logger.error('Profile error:', error);
        res.status(500).json({ error: 'Ошибка сервера' });
    }
});

// Обновление профиля
app.put('/api/user/profile', authenticateToken, async (req, res) => {
    try {
        const { full_name, email, phone, language, timezone } = req.body;
        
        const result = await pool.query(
            `UPDATE users 
             SET full_name = COALESCE($1, full_name),
                 email = COALESCE($2, email),
                 phone = COALESCE($3, phone),
                 language = COALESCE($4, language),
                 timezone = COALESCE($5, timezone)
             WHERE id = $6
             RETURNING id, username, email, full_name, phone, language, timezone`,
            [full_name, email, phone, language, timezone, req.user.id]
        );
        
        res.json(result.rows[0]);
    } catch (error) {
        logger.error('Update profile error:', error);
        res.status(500).json({ error: 'Ошибка обновления профиля' });
    }
});

// Проверка токена
app.get('/api/auth/verify', authenticateToken, (req, res) => {
    res.json({ valid: true, user: req.user });
});

// Запуск сервера
app.listen(PORT, async () => {
    await initializeAdmin();
    logger.info(`✅ ${process.env.SITE_NAME} Backend запущен на порту ${PORT}`);
    logger.info(`🌐 http://localhost:${PORT}`);
    logger.info(`👤 Админ: ${process.env.ADMIN_USERNAME}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
    logger.info('SIGTERM received, shutting down gracefully');
    await redis.quit();
    await pool.end();
    process.exit(0);
});
EOF

    # Dockerfile
    cat > backend/Dockerfile << 'EOF'
FROM node:18-alpine

RUN apk add --no-cache tzdata curl

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY . .

RUN mkdir -p logs uploads
RUN chown -R node:node /app

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["node", "server.js"]
EOF

    echo -e "${GREEN}✅ Backend создан${NC}"
}

# Создание фронтенда
create_frontend() {
    echo -e "\n${BLUE}🎨 Создание фронтенда...${NC}"
    
    # index.html с динамическим названием
    cat > frontend/index.html << EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <title>${SITE_NAME} — Премиум телевидение</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:'Inter',sans-serif;background:#0a0e17;color:#e8edf5;line-height:1.5}
        .app{display:flex;min-height:100vh}
        .sidebar{width:300px;background:rgba(8,13,22,0.95);backdrop-filter:blur(24px);border-right:1px solid rgba(255,255,255,0.04);position:fixed;height:100vh;overflow-y:auto}
        .main{flex:1;margin-left:300px;padding:24px 32px}
        .logo{display:flex;align-items:center;gap:14px;padding:32px 24px}
        .logo-icon{width:52px;height:52px;background:linear-gradient(145deg,#ff5e3a,#d9381e);border-radius:18px;display:flex;align-items:center;justify-content:center;box-shadow:0 15px 30px -8px rgba(255,94,58,0.4)}
        .logo-icon i{font-size:28px;color:white}
        .logo-text{font-size:26px;font-weight:800;background:linear-gradient(120deg,#ffffff,#ffb347);-webkit-background-clip:text;background-clip:text;color:transparent}
        .welcome-screen{display:flex;align-items:center;justify-content:center;min-height:70vh;text-align:center}
        .welcome-content{max-width:600px}
        .welcome-icon{font-size:80px;color:#ff5e3a;margin-bottom:30px}
        .welcome-title{font-size:48px;font-weight:800;margin-bottom:20px;background:linear-gradient(120deg,#ffffff,#ffb347);-webkit-background-clip:text;background-clip:text;color:transparent}
        .welcome-text{font-size:18px;color:#b9c7d9;margin-bottom:40px;line-height:1.6}
        .btn{padding:14px 32px;border-radius:40px;font-weight:600;font-size:16px;cursor:pointer;transition:all 0.2s;border:none;margin:0 10px}
        .btn-primary{background:#ff5e3a;color:white}
        .btn-primary:hover{background:#ff7a5c;transform:scale(1.05)}
        .btn-secondary{background:rgba(255,255,255,0.1);color:white;border:1px solid rgba(255,255,255,0.2)}
        .btn-secondary:hover{background:rgba(255,255,255,0.2)}
        .user-menu{position:fixed;top:20px;right:20px;z-index:1000}
        @media (max-width:768px){.sidebar{display:none}.main{margin-left:0}}
    </style>
</head>
<body>
    <div class="app">
        <aside class="sidebar">
            <div class="logo">
                <div class="logo-icon"><i class="fas fa-eye"></i></div>
                <div><div class="logo-text">${SITE_NAME}</div></div>
            </div>
        </aside>
        <main class="main">
            <div class="welcome-screen">
                <div class="welcome-content">
                    <div class="welcome-icon"><i class="fas fa-tv"></i></div>
                    <h1 class="welcome-title">${SITE_NAME}</h1>
                    <p class="welcome-text">Премиум телевидение и радио в высоком качестве. Смотрите любимые каналы где угодно и когда угодно.</p>
                    <div>
                        <button class="btn btn-primary" onclick="location.href='/register.html'">
                            <i class="fas fa-user-plus"></i> Регистрация
                        </button>
                        <button class="btn btn-secondary" onclick="location.href='/login.html'">
                            <i class="fas fa-sign-in-alt"></i> Вход
                        </button>
                    </div>
                </div>
            </div>
        </main>
    </div>
</body>
</html>
EOF

    echo -e "${GREEN}✅ Фронтенд создан${NC}"
}

# Настройка SSL
setup_ssl() {
    if [[ "$SSL_ENABLED" =~ ^[Yy]$ ]]; then
        echo -e "\n${BLUE}🔒 Настройка SSL сертификата для ${SITE_DOMAIN}...${NC}"
        
        # Остановка контейнеров для получения сертификата
        docker-compose stop nginx 2>/dev/null || true
        
        # Получение сертификата
        certbot certonly --standalone \
            -d "${SITE_DOMAIN}" \
            --non-interactive \
            --agree-tos \
            -m "${ADMIN_EMAIL}" \
            --preferred-challenges http
        
        if [ $? -eq 0 ]; then
            # Копирование сертификатов
            mkdir -p ssl
            cp /etc/letsencrypt/live/${SITE_DOMAIN}/fullchain.pem ssl/cert.pem
            cp /etc/letsencrypt/live/${SITE_DOMAIN}/privkey.pem ssl/key.pem
            
            # Обновление конфигурации Nginx для HTTPS
            cat >> nginx/nginx.conf << EOF

# HTTPS сервер
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${SITE_DOMAIN};
    
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        root /var/www/html;
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api/ {
        proxy_pass http://backend:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Редирект с HTTP на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${SITE_DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
EOF
            
            echo -e "${GREEN}✅ SSL сертификат установлен${NC}"
        else
            echo -e "${YELLOW}⚠️  Не удалось получить SSL сертификат, продолжаем без HTTPS${NC}"
        fi
        
        docker-compose start nginx 2>/dev/null || true
    fi
}

# Настройка файрвола
setup_firewall() {
    echo -e "\n${BLUE}🛡️  Настройка файрвола...${NC}"
    
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp comment 'SSH'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
        ufw --force enable
        echo -e "${GREEN}✅ UFW настроен${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        echo -e "${GREEN}✅ FirewallD настроен${NC}"
    fi
}

# Запуск сервисов
start_services() {
    echo -e "\n${BLUE}🚀 Запуск сервисов...${NC}"
    
    docker-compose up -d
    
    echo -e "${GREEN}✅ Сервисы запущены${NC}"
}

# Сохранение информации
save_info() {
    cat > credentials.txt << EOF
============================================
${SITE_NAME} - ДАННЫЕ ДЛЯ ДОСТУПА
============================================

🌐 Сайт: http${SSL_ENABLED:+"s"}://${SITE_DOMAIN}
👑 Админ-панель: http${SSL_ENABLED:+"s"}://${SITE_DOMAIN}/admin

🔑 АДМИНИСТРАТОР:
   Логин:  admin
   Пароль: ${ADMIN_PASSWORD}
   Email:  ${ADMIN_EMAIL}

📁 Файлы:
   Конфигурация: ${INSTALL_DIR}/.env
   Логи: ${INSTALL_DIR}/logs/

💾 Команды управления:
   cd ${INSTALL_DIR}
   docker-compose ps          # Статус
   docker-compose logs -f     # Логи
   docker-compose restart     # Перезапуск
   docker-compose down        # Остановка
   docker-compose up -d       # Запуск

============================================
Сохраните эту информацию!
============================================
EOF

    chmod 600 credentials.txt
}

# Показ финальной информации
show_final_info() {
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    ✅ УСТАНОВКА ЗАВЕРШЕНА!                         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${CYAN}🎉 ${SITE_NAME} успешно установлен!${NC}\n"
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📱 ДОСТУП К СИСТЕМЕ:${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    PROTOCOL="http"
    if [[ "$SSL_ENABLED" =~ ^[Yy]$ ]]; then
        PROTOCOL="https"
    fi
    
    echo -e "${GREEN}🌐 Сайт:${NC}             ${PROTOCOL}://${SITE_DOMAIN}"
    echo -e "${GREEN}📝 Регистрация:${NC}      ${PROTOCOL}://${SITE_DOMAIN}/register.html"
    echo -e "${GREEN}🔐 Вход:${NC}            ${PROTOCOL}://${SITE_DOMAIN}/login.html"
    echo -e "${GREEN}👤 Личный кабинет:${NC}  ${PROTOCOL}://${SITE_DOMAIN}/cabinet.html"
    echo -e "${GREEN}👑 Админ-панель:${NC}    ${PROTOCOL}://${SITE_DOMAIN}/admin.html"
    
    echo -e "\n${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🔑 ДАННЫЕ АДМИНИСТРАТОРА:${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Логин:${NC}     admin"
    echo -e "${GREEN}Пароль:${NC}    ${ADMIN_PASSWORD}"
    echo -e "${GREEN}Email:${NC}     ${ADMIN_EMAIL}"
    
    echo -e "\n${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}💾 УПРАВЛЕНИЕ:${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}cd ${INSTALL_DIR}${NC}"
    echo -e "${BLUE}docker-compose ps${NC}          # Статус сервисов"
    echo -e "${BLUE}docker-compose logs -f${NC}     # Просмотр логов"
    echo -e "${BLUE}docker-compose restart${NC}     # Перезапуск"
    echo -e "${BLUE}docker-compose down${NC}        # Остановка"
    echo -e "${BLUE}docker-compose up -d${NC}       # Запуск"
    
    echo -e "\n${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📁 Данные сохранены в: ${INSTALL_DIR}/credentials.txt${NC}"
    echo -e "${RED}⚠️  СОХРАНИТЕ ПАРОЛЬ АДМИНИСТРАТОРА!${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Главная функция
main() {
    show_logo
    check_root
    detect_os
    interactive_setup
    
    echo -e "\n${CYAN}🚀 НАЧИНАЕМ УСТАНОВКУ ${SITE_NAME}...${NC}\n"
    
    install_dependencies
    install_docker
    create_project_structure
    generate_config
    create_docker_compose
    create_nginx_config
    create_database_schema
    create_backend
    create_frontend
    setup_firewall
    start_services
    setup_ssl
    save_info
    show_final_info
}

# Запуск
main "$@"