#!/bin/bash
set -euo pipefail

#================================================================
# PaperPhone Plus - Полный скрипт автоустановки
# Улучшенная версия с проверками и безопасностью
#================================================================

# Цвета для вывода
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Константы
readonly INSTALL_DIR="/opt/paperphone"
readonly LOG_FILE="/var/log/paperphone_install.log"
readonly REQUIRED_PACKAGES="curl openssl nginx certbot python3-certbot-nginx"

# Функции логирования
log_info() { echo -e "${GREEN}[✓ ИНФО]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[⚠ ВНИМАНИЕ]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗ ОШИБКА]${NC} $1" | tee -a "$LOG_FILE"; }
log_step() { echo -e "${BLUE}[▶ ШАГ]${NC} $1" | tee -a "$LOG_FILE"; }

# Очистка при ошибке
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Установка прервана с ошибкой (код: $exit_code)"
        log_error "Проверьте лог: $LOG_FILE"
    fi
    exit $exit_code
}
trap cleanup EXIT

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Этот скрипт должен запускаться от root"
        exit 1
    fi
}

# Проверка домена
validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        log_error "Неверный формат домена: $domain"
        return 1
    fi
    return 0
}

# Проверка email
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Неверный формат email: $email"
        return 1
    fi
    return 0
}

# Проверка IP адреса
validate_ip() {
    local ip=$1
    if [ -z "$ip" ]; then
        return 0
    fi
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Неверный формат IP адреса: $ip"
        return 1
    fi
    return 0
}

# Установка необходимых пакетов
install_prerequisites() {
    log_step "Установка необходимых пакетов..."
    
    apt-get update -qq
    
    for package in $REQUIRED_PACKAGES; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            apt-get install -y "$package" >> "$LOG_FILE" 2>&1
            log_info "Установлен пакет: $package"
        else
            log_info "Пакет уже установлен: $package"
        fi
    done
}

# Установка Docker
install_docker() {
    log_step "Установка Docker..."
    
    if ! command -v docker &> /dev/null; then
        log_info "Docker не найден, устанавливаем..."
        curl -fsSL https://get.docker.com | sh >> "$LOG_FILE" 2>&1
        systemctl enable docker >> "$LOG_FILE" 2>&1
        systemctl start docker >> "$LOG_FILE" 2>&1
        log_info "Docker установлен успешно"
    else
        log_info "Docker уже установлен: $(docker --version)"
    fi

    # Установка Docker Compose
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        log_info "Docker Compose не найден, устанавливаем..."
        local compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
        curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose >> "$LOG_FILE" 2>&1
        chmod +x /usr/local/bin/docker-compose
        log_info "Docker Compose установлен: $compose_version"
    else
        log_info "Docker Compose уже установлен"
    fi
}

# Проверка DNS
check_dns() {
    log_step "Проверка DNS записей..."
    
    local domain_ip=$(dig +short "$DOMAIN" A | tail -n1)
    
    if [ -z "$domain_ip" ]; then
        log_warn "Не удалось разрешить DNS для $DOMAIN"
        log_warn "Убедитесь, что DNS запись создана и успела распространиться"
        return 1
    elif [ "$domain_ip" != "$SERVER_IP" ]; then
        log_error "IP домена ($domain_ip) не совпадает с IP сервера ($SERVER_IP)"
        log_error "Обновите DNS запись для $DOMAIN на $SERVER_IP"
        return 1
    else
        log_info "DNS проверка пройдена: $DOMAIN -> $SERVER_IP"
        return 0
    fi
}

# Создание структуры директорий
create_directory_structure() {
    log_step "Создание структуры директорий..."
    
    mkdir -p "$INSTALL_DIR"/{data/{pgdata,redis},uploads,coturn,nginx,backups}
    
    # Установка правильных прав
    chown -R 1000:1000 "$INSTALL_DIR/uploads" 2>/dev/null || true
    chmod 750 "$INSTALL_DIR"
    chmod 750 "$INSTALL_DIR/backups"
    
    log_info "Структура директорий создана в $INSTALL_DIR"
}

# Генерация безопасных паролей
generate_passwords() {
    log_step "Генерация безопасных паролей..."
    
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    TURN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    ADMIN_KEY=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-48)
    JWT_SECRET=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-48)
    
    log_info "Пароли сгенерированы успешно"
}

# Создание docker-compose.yml
create_docker_compose() {
    log_step "Создание docker-compose.yml..."
    
    cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: paperphone_db
    restart: unless-stopped
    environment:
      POSTGRES_USER: paperphone
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: paperphone
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C"
    volumes:
      - ./data/pgdata:/var/lib/postgresql/data
    networks:
      - paperphone_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U paperphone -d paperphone"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  redis:
    image: redis:7-alpine
    container_name: paperphone_redis
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass \${REDIS_PASSWORD}
    environment:
      REDIS_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ./data/redis:/data
    networks:
      - paperphone_network
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  coturn:
    image: coturn/coturn:4.6.2-alpine
    container_name: paperphone_turn
    restart: unless-stopped
    network_mode: host
    environment:
      EXTERNAL_IP: ${SERVER_IP}
    volumes:
      - ./coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro
    command:
      - -n
      - --log-file=stdout
      - --listening-port=3478
      - --tls-listening-port=5349
      - --external-ip=${SERVER_IP}/$(dig +short myip.opendns.com @resolver1.opendns.com | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
      - --user=paperphone:${TURN_PASSWORD}
      - --realm=${DOMAIN}
      - --fingerprint
      - --lt-cred-mech
      - --no-cli
      - --no-tlsv1
      - --no-tlsv1_1
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  server:
    image: facilisvelox/paperphone-plus-server:latest
    container_name: paperphone_server
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://paperphone:${DB_PASSWORD}@postgres:5432/paperphone
      REDIS_URL: redis://:${DB_PASSWORD}@redis:6379
      STORAGE_TYPE: local
      STORAGE_PATH: /app/uploads
      STORAGE_MAX_SIZE: "500MB"
      TURN_SERVER: turn://paperphone:${TURN_PASSWORD}@${SERVER_IP}:3478
      ADMIN_KEY: ${ADMIN_KEY}
      JWT_SECRET: ${JWT_SECRET}
      RUST_LOG: info
      RUST_BACKTRACE: 1
      DOMAIN: ${DOMAIN}
      SERVER_IP: ${SERVER_IP}
    volumes:
      - ./uploads:/app/uploads
    networks:
      - paperphone_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "5"

  client:
    image: facilisvelox/paperphone-plus-client:latest
    container_name: paperphone_client
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    depends_on:
      - server
    environment:
      NODE_ENV: production
      API_URL: https://${DOMAIN}
    networks:
      - paperphone_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Сервис для автоматического бэкапа
  backup:
    image: postgres:15-alpine
    container_name: paperphone_backup
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./backups:/backups
      - ./scripts/backup.sh:/backup.sh:ro
    environment:
      PGPASSWORD: ${DB_PASSWORD}
      POSTGRES_HOST: postgres
      POSTGRES_DB: paperphone
      POSTGRES_USER: paperphone
    entrypoint: |
      /bin/sh -c '
      while true; do
        echo "Starting backup..."
        pg_dump -h $$POSTGRES_HOST -U $$POSTGRES_USER $$POSTGRES_DB > /backups/db_$$(date +%Y%m%d_%H%M%S).sql
        find /backups -name "*.sql" -mtime +7 -delete
        echo "Backup completed at $$(date)"
        sleep 86400
      done
      '
    networks:
      - paperphone_network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  paperphone_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
EOF

    log_info "docker-compose.yml создан"
}

# Создание конфигурации TURN сервера
create_turn_config() {
    log_step "Создание конфигурации TURN сервера..."
    
    cat > "$INSTALL_DIR/coturn/turnserver.conf" <<EOF
# PaperPhone Plus TURN Server Configuration
listening-port=3478
tls-listening-port=5349
external-ip=${SERVER_IP}
relay-ip=${SERVER_IP}
realm=${DOMAIN}
user=paperphone:${TURN_PASSWORD}
lt-cred-mech
fingerprint
no-cli
no-tlsv1
no-tlsv1_1
verbose
EOF

    log_info "Конфигурация TURN сервера создана"
}

# Настройка Nginx и SSL
configure_nginx() {
    log_step "Настройка Nginx и SSL..."
    
    # Создание конфигурации Nginx
    cat > "/etc/nginx/sites-available/paperphone" <<EOF
# PaperPhone Plus Nginx Configuration
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    
    # Редирект на HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # SSL конфигурация
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${DOMAIN}/chain.pem;

    # SSL настройки безопасности
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_session_tickets off;

    # Заголовки безопасности
    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Настройки проксирования
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Настройки времени ожидания
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Буферизация
        proxy_buffering off;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        # Защита от DoS
        limit_req zone=api_limit burst=10 nodelay;
    }

    # WebSocket endpoint
    location /ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # API endpoint
    location /api {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        client_max_body_size 50M;
        client_body_timeout 60s;
    }

    # Статические файлы
    location /static {
        alias /var/www/paperphone/static;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Медиа файлы
    location /media {
        alias /var/www/paperphone/media;
        expires 7d;
        add_header Cache-Control "public";
    }

    # Ограничение доступа к sensitive файлам
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Логирование
    access_log /var/log/nginx/paperphone_access.log;
    error_log /var/log/nginx/paperphone_error.log;
}

# Настройки ограничения запросов
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=5r/s;
EOF

    # Активация сайта
    ln -sf /etc/nginx/sites-available/paperphone /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Проверка и перезагрузка Nginx
    if nginx -t 2>> "$LOG_FILE"; then
        systemctl reload nginx
        log_info "Nginx настроен и перезагружен"
    else
        log_error "Ошибка в конфигурации Nginx"
        return 1
    fi
}

# Получение SSL сертификата
get_ssl_certificate() {
    log_step "Получение SSL сертификата..."
    
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect --hsts >> "$LOG_FILE" 2>&1; then
        log_info "SSL сертификат успешно получен"
        
        # Добавление автоматического обновления
        if ! grep -q "certbot renew" /etc/crontab 2>/dev/null; then
            echo "0 0 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" >> /etc/crontab
        fi
    else
        log_error "Ошибка получения SSL сертификата"
        return 1
    fi
}

# Настройка фаервола
configure_firewall() {
    log_step "Настройка фаервола..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp comment 'SSH'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
        ufw allow 3478/tcp comment 'TURN TCP'
        ufw allow 3478/udp comment 'TURN UDP'
        ufw allow 5349/tcp comment 'TURN TLS'
        
        if ufw status | grep -q "Status: inactive"; then
            echo "y" | ufw enable >> "$LOG_FILE" 2>&1
        else
            ufw reload >> "$LOG_FILE" 2>&1
        fi
        log_info "Фаервол настроен"
    else
        log_warn "UFW не установлен, фаервол не настроен"
    fi
}

# Создание скрипта резервного копирования
create_backup_script() {
    log_step "Создание скрипта резервного копирования..."
    
    mkdir -p "$INSTALL_DIR/scripts"
    
    cat > "$INSTALL_DIR/scripts/backup.sh" <<EOF
#!/bin/bash
# PaperPhone Plus Backup Script

BACKUP_DIR="/opt/paperphone/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="paperphone_backup_\${DATE}.tar.gz"

# Создание директории для бэкапа
mkdir -p "\$BACKUP_DIR/\$DATE"

# Остановка контейнеров для консистентного бэкапа
cd /opt/paperphone
docker compose stop server

# Бэкап базы данных
docker compose exec -T postgres pg_dump -U paperphone paperphone > "\$BACKUP_DIR/\$DATE/database.sql"

# Бэкап конфигураций
cp docker-compose.yml "\$BACKUP_DIR/\$DATE/"
cp -r coturn "\$BACKUP_DIR/\$DATE/"
cp -r nginx "\$BACKUP_DIR/\$DATE/"

# Запуск контейнеров
docker compose start server

# Упаковка бэкапа
tar -czf "\$BACKUP_DIR/\$BACKUP_FILE" -C "\$BACKUP_DIR" "\$DATE"
rm -rf "\$BACKUP_DIR/\$DATE"

# Удаление старых бэкапов (старше 7 дней)
find "\$BACKUP_DIR" -name "paperphone_backup_*.tar.gz" -mtime +7 -delete

echo "Backup created: \$BACKUP_DIR/\$BACKUP_FILE"
EOF

    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    log_info "Скрипт резервного копирования создан"
}

# Создание информационных файлов
create_info_files() {
    log_step "Создание информационных файлов..."
    
    cat > "$INSTALL_DIR/INSTALL_INFO.txt" <<EOF
========================================
   PaperPhone Plus УСТАНОВЛЕН
========================================
Дата установки: $(date)
Домен: https://${DOMAIN}
Версия: 2.0.0

--- ДАННЫЕ ДЛЯ АДМИНИСТРИРОВАНИЯ ---
Admin Key: ${ADMIN_KEY}
JWT Secret: ${JWT_SECRET}

--- БАЗА ДАННЫХ ---
Хост: postgres
Порт: 5432
Пользователь: paperphone
База данных: paperphone
Пароль: ${DB_PASSWORD}

--- TURN СЕРВЕР ---
Хост: ${DOMAIN}
Порт: 3478 (TCP/UDP), 5349 (TLS)
Пользователь: paperphone
Пароль: ${TURN_PASSWORD}

--- КОМАНДЫ УПРАВЛЕНИЯ ---
Запуск: cd ${INSTALL_DIR} && docker compose up -d
Остановка: cd ${INSTALL_DIR} && docker compose down
Перезапуск: cd ${INSTALL_DIR} && docker compose restart
Логи: cd ${INSTALL_DIR} && docker compose logs -f
Бэкап: ${INSTALL_DIR}/scripts/backup.sh

--- ФАЙЛЫ ---
Docker Compose: ${INSTALL_DIR}/docker-compose.yml
Бэкапы: ${INSTALL_DIR}/backups/
Загрузки: ${INSTALL_DIR}/uploads/

--- БЕЗОПАСНОСТЬ ---
❗ СОХРАНИТЕ ЭТОТ ФАЙЛ В БЕЗОПАСНОМ МЕСТЕ
❗ УДАЛИТЕ ЭТОТ ФАЙЛ ПОСЛЕ СОХРАНЕНИЯ ДАННЫХ
❗ РЕГУЛЯРНО ДЕЛАЙТЕ РЕЗЕРВНЫЕ КОПИИ
========================================
EOF

    # Установка прав доступа
    chmod 600 "$INSTALL_DIR/INSTALL_INFO.txt"
    chown root:root "$INSTALL_DIR/INSTALL_INFO.txt"
    
    # Создание .env файла
    cat > "$INSTALL_DIR/.env" <<EOF
DB_PASSWORD=${DB_PASSWORD}
TURN_PASSWORD=${TURN_PASSWORD}
ADMIN_KEY=${ADMIN_KEY}
JWT_SECRET=${JWT_SECRET}
DOMAIN=${DOMAIN}
SERVER_IP=${SERVER_IP}
EMAIL=${EMAIL}
EOF
    chmod 600 "$INSTALL_DIR/.env"
}

# Проверка работоспособности
health_check() {
    log_step "Проверка работоспособности..."
    
    # Ожидание запуска сервисов
    sleep 15
    
    # Проверка HTTPS
    if curl -fsSL -o /dev/null -w "%{http_code}" "https://${DOMAIN}" | grep -q "200\|301\|302"; then
        log_info "✅ Приложение доступно по HTTPS"
    else
        log_warn "⚠ Приложение может быть еще недоступно. Это нормально для первого запуска."
    fi
    
    # Проверка WebSocket
    if curl -fsSL -o /dev/null -w "%{http_code}" "https://${DOMAIN}/ws" | grep -q "101"; then
        log_info "✅ WebSocket работает"
    else
        log_warn "⚠ WebSocket может требовать дополнительной настройки"
    fi
}

# Отображение сводной информации
show_summary() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}  ✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!     ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e ""
    echo -e "🌐 Ваш мессенджер: ${GREEN}https://${DOMAIN}${NC}"
    echo -e ""
    echo -e "${BLUE}Статус сервисов:${NC}"
    cd "$INSTALL_DIR"
    docker compose ps 2>/dev/null | grep -E "paperphone|Up"
    echo -e ""
    echo -e "${YELLOW}⚠️  ВАЖНАЯ ИНФОРМАЦИЯ:${NC}"
    echo -e "   📁 Все данные сохранены в: ${INSTALL_DIR}/INSTALL_INFO.txt"
    echo -e "   🔐 Установите пароль администратора через веб-интерфейс"
    echo -e "   💾 Настройте автоматическое резервное копирование"
    echo -e "   📊 Мониторинг логов: docker compose logs -f"
    echo -e ""
    echo -e "${GREEN}Полезные команды:${NC}"
    echo -e "   ▶ Запуск:    docker compose up -d"
    echo -e "   ▶ Остановка: docker compose down"
    echo -e "   ▶ Логи:      docker compose logs -f"
    echo -e "   ▶ Бэкап:     ${INSTALL_DIR}/scripts/backup.sh"
    echo -e ""
    echo -e "${YELLOW}Поздравляем! Ваш мессенджер готов к использованию.${NC}"
}

# Основная функция установки
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  PaperPhone Plus Full Auto-Install    ${NC}"
    echo -e "${GREEN}  Улучшенная версия 2.0               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Создание лог-файла
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Проверка прав
    check_root
    
    # Сбор данных от пользователя
    echo -e "${YELLOW}Пожалуйста, введите данные для настройки:${NC}"
    
    while true; do
        read -p "Ваш домен (например, chat.example.com): " DOMAIN
        if validate_domain "$DOMAIN"; then
            break
        fi
    done
    
    while true; do
        read -p "Email для SSL-сертификатов: " EMAIL
        if validate_email "$EMAIL"; then
            break
        fi
    done
    
    read -p "IP-адрес сервера (Enter для автоопределения): " SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -s ifconfig.me)
        log_info "Автоопределен IP: $SERVER_IP"
    else
        if ! validate_ip "$SERVER_IP"; then
            exit 1
        fi
    fi
    
    # Подтверждение данных
    echo -e "\n${BLUE}Проверьте введенные данные:${NC}"
    echo -e "  Домен: $DOMAIN"
    echo -e "  Email: $EMAIL"
    echo -e "  IP: $SERVER_IP"
    read -p "Всё верно? (y/n): " CONFIRM
    
    if [ "$CONFIRM" != "y" ]; then
        log_error "Установка отменена пользователем"
        exit 1
    fi
    
    # Выполнение установки
    install_prerequisites
    install_docker
    check_dns
    create_directory_structure
    generate_passwords
    create_docker_compose
    create_turn_config
    configure_nginx
    get_ssl_certificate
    configure_firewall
    create_backup_script
    create_info_files
    
    # Запуск контейнеров
    log_step "Запуск PaperPhone Plus..."
    cd "$INSTALL_DIR"
    
    if docker compose version &> /dev/null; then
        docker compose up -d >> "$LOG_FILE" 2>&1
    else
        docker-compose up -d >> "$LOG_FILE" 2>&1
    fi
    
    # Проверка работоспособности
    health_check
    
    # Отображение результатов
    show_summary
}

# Запуск установки
main "$@"