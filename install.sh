#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ошибка: Этот скрипт должен запускаться от root (sudo)${NC}" 
   exit 1
fi

# Запрос домена у пользователя
echo -e "${GREEN}=== Установка ownCloud на Ubuntu 22.04 ===${NC}"
read -p "Введите домен (например, cloud.example.com) или IP-адрес: " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Ошибка: Домен или IP не может быть пустым${NC}"
    exit 1
fi

echo -e "${YELLOW}Начинаю установку ownCloud для домена: $DOMAIN${NC}"

# Шаг 1: Обновление системы
echo -e "${GREEN}[1/10] Обновление системы...${NC}"
apt update && apt upgrade -y

# Шаг 2: Установка Apache
echo -e "${GREEN}[2/10] Установка Apache...${NC}"
apt install apache2 -y

# Шаг 3: Установка PHP 7.4
echo -e "${GREEN}[3/10] Установка PHP 7.4...${NC}"
add-apt-repository ppa:ondrej/php -y
apt update
apt install php7.4 php7.4-{opcache,gd,curl,mysqlnd,intl,json,ldap,mbstring,xml,zip,common} -y

# Шаг 4: Установка MariaDB
echo -e "${GREEN}[4/10] Установка MariaDB...${NC}"
apt install mariadb-server -y

# Шаг 5: Настройка базы данных
echo -e "${GREEN}[5/10] Настройка базы данных...${NC}"
DB_PASSWORD=$(openssl rand -base64 24)
mysql <<EOF
CREATE DATABASE IF NOT EXISTS owncloud;
CREATE USER IF NOT EXISTS 'owncloud'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON owncloud.* TO 'owncloud'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF

# Сохраняем пароль базы данных в файл
echo "Пароль базы данных owncloud: ${DB_PASSWORD}" > /root/owncloud_db_password.txt
chmod 600 /root/owncloud_db_password.txt

# Шаг 6: Скачивание ownCloud
echo -e "${GREEN}[6/10] Скачивание ownCloud...${NC}"
apt install unzip wget -y
wget https://download.owncloud.com/server/stable/owncloud-complete-latest.zip -O /tmp/owncloud.zip
unzip /tmp/owncloud.zip -d /var/www/
rm /tmp/owncloud.zip

# Шаг 7: Настройка прав
echo -e "${GREEN}[7/10] Настройка прав доступа...${NC}"
mkdir -p /var/www/owncloud/data
chown -R www-data:www-data /var/www/owncloud/
chmod -R 755 /var/www/owncloud/

# Шаг 8: Настройка виртуального хоста Apache
echo -e "${GREEN}[8/10] Настройка виртуального хоста для $DOMAIN...${NC}"
cat > /etc/apache2/sites-available/owncloud.conf <<EOF
<VirtualHost *:80>
    ServerAdmin admin@${DOMAIN}
    ServerName ${DOMAIN}
    DocumentRoot /var/www/owncloud
    
    <Directory /var/www/owncloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/owncloud_error.log
    CustomLog \${APACHE_LOG_DIR}/owncloud_access.log combined
</VirtualHost>
EOF

# Активация сайта и модулей
a2ensite owncloud.conf
a2dissite 000-default.conf
a2enmod rewrite headers env dir mime setenvif
systemctl restart apache2

# Шаг 9: Установка автозапуска сервисов
echo -e "${GREEN}[9/10] Настройка автозапуска...${NC}"
systemctl enable apache2
systemctl enable mariadb

# Шаг 10: Настройка файла конфигурации ownCloud
echo -e "${GREEN}[10/10] Финальная настройка ownCloud...${NC}"
cat > /var/www/owncloud/config/autoconfig.php <<EOF
<?php
\$AUTOCONFIG = array(
    'directory'     => '/var/www/owncloud/data',
    'dbtype'        => 'mysql',
    'dbname'        => 'owncloud',
    'dbuser'        => 'owncloud',
    'dbpass'        => '${DB_PASSWORD}',
    'dbhost'        => 'localhost',
    'dbtableprefix' => '',
    'adminlogin'    => 'admin',
    'adminpass'     => '$(openssl rand -base64 12)',
);
EOF

# Установка правильных прав на config
chown -R www-data:www-data /var/www/owncloud/config/

# Получаем пароль админа из файла конфигурации
ADMIN_PASS=$(grep "'adminpass'" /var/www/owncloud/config/autoconfig.php | cut -d"'" -f4)

# Вывод информации для пользователя
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Установка ownCloud завершена успешно!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Доступ к хранилищу:${NC} http://${DOMAIN}"
echo -e "${YELLOW}Логин администратора:${NC} admin"
echo -e "${YELLOW}Пароль администратора:${NC} ${ADMIN_PASS}"
echo -e "${RED}⚠️  Сохраните пароли:${NC}"
echo -e "   Пароль базы данных сохранен в: /root/owncloud_db_password.txt"
echo -e ""
echo -e "${YELLOW}Для защиты соединения рекомендуется настроить SSL:${NC}"
echo -e "   sudo apt install certbot python3-certbot-apache -y"
echo -e "   sudo certbot --apache -d ${DOMAIN}"
echo -e "${GREEN}========================================${NC}"