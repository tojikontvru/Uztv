#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║          Установка Online TV Platform           ║"
echo "║        с регистрацией через Telegram           ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Пожалуйста, запустите скрипт с правами root: sudo ./install.sh${NC}"
    exit 1
fi

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ Ошибка: $1${NC}"
        exit 1
    fi
}

# Update system
echo -e "${YELLOW}Обновление системы...${NC}"
apt-get update
apt-get upgrade -y
check_success "Система обновлена"

# Install required packages
echo -e "${YELLOW}Установка необходимых пакетов...${NC}"
apt-get install -y apache2 php php-mysql php-curl php-gd php-mbstring php-xml php-zip mysql-server git curl
check_success "Пакеты установлены"

# Enable Apache modules
a2enmod rewrite
systemctl restart apache2

# Create project directory
PROJECT_DIR="/var/www/online-tv"
echo -e "${YELLOW}Создание директории проекта...${NC}"
mkdir -p $PROJECT_DIR
check_success "Директория создана: $PROJECT_DIR"

# Clone or create project structure
echo -e "${YELLOW}Создание структуры проекта...${NC}"
cd $PROJECT_DIR

# Create directory structure
mkdir -p {admin,user,api,config,database,uploads/channels,uploads/users,logs,cache,telegram}
check_success "Структура директорий создана"

# Create main configuration files
cat > config/database.php << 'EOL'
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', 'online_tv');
define('DB_USER', 'tv_user');
define('DB_PASS', 'tv_password123');
define('DB_CHARSET', 'utf8mb4');
?>
EOL

cat > config/settings.php << 'EOL'
<?php
// Basic Settings
define('SITE_NAME', 'Online TV Platform');
define('SITE_URL', 'http://localhost');
define('DEFAULT_TIMEZONE', 'Europe/Moscow');

// Upload Settings
define('MAX_FILE_SIZE', 50 * 1024 * 1024); // 50MB
define('ALLOWED_IMAGE_TYPES', ['jpg', 'jpeg', 'png', 'gif']);

// Player Settings
define('DEFAULT_VOLUME', 80);
define('AUTO_PLAY', true);
define('PRELOAD_VIDEO', 'auto');

// Security
define('SESSION_TIMEOUT', 3600); // 1 hour

// Telegram Settings
define('TELEGRAM_BOT_TOKEN', 'YOUR_BOT_TOKEN_HERE');
define('TELEGRAM_BOT_USERNAME', 'YOUR_BOT_USERNAME');
define('TELEGRAM_WEBHOOK_URL', SITE_URL . '/api/telegram_webhook.php');
?>
EOL

# Create database setup script with Telegram support
cat > database/setup.php << 'EOL'
<?php
require_once '../config/database.php';

try {
    $pdo = new PDO("mysql:host=" . DB_HOST, DB_USER, DB_PASS);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // Create database
    $pdo->exec("CREATE DATABASE IF NOT EXISTS " . DB_NAME . " CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
    $pdo->exec("USE " . DB_NAME);
    
    // Users table with Telegram fields
    $pdo->exec("CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100),
        password VARCHAR(255),
        role ENUM('admin', 'user') DEFAULT 'user',
        telegram_id BIGINT UNIQUE,
        telegram_username VARCHAR(100),
        telegram_first_name VARCHAR(100),
        telegram_last_name VARCHAR(100),
        telegram_photo_url VARCHAR(500),
        auth_method ENUM('password', 'telegram') DEFAULT 'password',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP NULL,
        status ENUM('active', 'inactive') DEFAULT 'active',
        INDEX idx_telegram_id (telegram_id),
        INDEX idx_telegram_username (telegram_username)
    )");
    
    // Channels table
    $pdo->exec("CREATE TABLE IF NOT EXISTS channels (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        stream_url TEXT NOT NULL,
        description TEXT,
        category VARCHAR(50),
        logo_url VARCHAR(255),
        is_active BOOLEAN DEFAULT true,
        created_by INT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (created_by) REFERENCES users(id)
    )");
    
    // Settings table
    $pdo->exec("CREATE TABLE IF NOT EXISTS settings (
        id INT AUTO_INCREMENT PRIMARY KEY,
        setting_key VARCHAR(100) UNIQUE NOT NULL,
        setting_value TEXT,
        setting_type VARCHAR(50),
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )");
    
    // Telegram sessions table
    $pdo->exec("CREATE TABLE IF NOT EXISTS telegram_sessions (
        id INT AUTO_INCREMENT PRIMARY KEY,
        chat_id BIGINT NOT NULL,
        user_id INT,
        auth_code VARCHAR(10),
        auth_expires TIMESTAMP,
        session_data TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_chat_id (chat_id),
        INDEX idx_auth_code (auth_code),
        FOREIGN KEY (user_id) REFERENCES users(id)
    )");
    
    // Insert default admin user
    $hashed_password = password_hash('admin123', PASSWORD_DEFAULT);
    $pdo->exec("INSERT IGNORE INTO users (username, email, password, role) 
                VALUES ('admin', 'admin@tvplatform.com', '$hashed_password', 'admin')");
    
    // Insert default settings
    $default_settings = [
        ['site_name', 'Online TV Platform', 'string'],
        ['site_description', 'Лучшая платформа для онлайн ТВ', 'string'],
        ['max_users', '1000', 'number'],
        ['allow_registration', '1', 'boolean'],
        ['telegram_login_enabled', '1', 'boolean'],
        ['telegram_bot_token', 'YOUR_BOT_TOKEN_HERE', 'string'],
        ['telegram_bot_username', 'YOUR_BOT_USERNAME', 'string']
    ];
    
    $stmt = $pdo->prepare("INSERT IGNORE INTO settings (setting_key, setting_value, setting_type) VALUES (?, ?, ?)");
    foreach ($default_settings as $setting) {
        $stmt->execute($setting);
    }
    
    echo "Database setup completed successfully!";
    
} catch (PDOException $e) {
    die("Database error: " . $e->getMessage());
}
?>
EOL

# Create Telegram bot handler
cat > api/telegram_webhook.php << 'EOL'
<?php
require_once '../config/database.php';
require_once '../config/settings.php';

// Get the input data
$input = file_get_contents('php://input');
$data = json_decode($input, true);

if (!$data) {
    http_response_code(400);
    exit;
}

// Log the request
file_put_contents('../logs/telegram_webhook.log', date('Y-m-d H:i:s') . " - " . $input . "\n", FILE_APPEND);

try {
    $pdo = new PDO("mysql:host=" . DB_HOST . ";dbname=" . DB_NAME, DB_USER, DB_PASS);
    
    $chat_id = $data['message']['chat']['id'] ?? null;
    $text = $data['message']['text'] ?? '';
    $username = $data['message']['chat']['username'] ?? '';
    $first_name = $data['message']['chat']['first_name'] ?? '';
    $last_name = $data['message']['chat']['last_name'] ?? '';
    
    if ($chat_id) {
        // Check if user exists
        $stmt = $pdo->prepare("SELECT * FROM users WHERE telegram_id = ?");
        $stmt->execute([$chat_id]);
        $user = $stmt->fetch();
        
        if ($user) {
            // User exists - show menu
            sendMessage($chat_id, "Добро пожаловать назад, {$first_name}!\n\n" .
                "Ваш аккаунт привязан к платформе Online TV.\n" .
                "Для входа на сайт используйте Telegram авторизацию.");
        } else {
            // New user - start registration
            if ($text === '/start') {
                // Generate auth code
                $auth_code = generateAuthCode();
                $expires = date('Y-m-d H:i:s', time() + 600); // 10 minutes
                
                // Save session
                $stmt = $pdo->prepare("INSERT INTO telegram_sessions (chat_id, auth_code, auth_expires) VALUES (?, ?, ?)");
                $stmt->execute([$chat_id, $auth_code, $expires]);
                
                sendMessage($chat_id, "👋 Привет, {$first_name}!\n\n" .
                    "Для регистрации на платформе Online TV:\n" .
                    "1. Перейдите на сайт: " . SITE_URL . "\n" .
                    "2. Нажмите 'Войти через Telegram'\n" .
                    "3. Введите код: *{$auth_code}*\n\n" .
                    "Код действителен 10 минут.");
            } else {
                sendMessage($chat_id, "Для начала работы отправьте /start");
            }
        }
    }
    
} catch (Exception $e) {
    file_put_contents('../logs/telegram_errors.log', date('Y-m-d H:i:s') . " - " . $e->getMessage() . "\n", FILE_APPEND);
}

function sendMessage($chat_id, $text) {
    $token = TELEGRAM_BOT_TOKEN;
    $url = "https://api.telegram.org/bot{$token}/sendMessage";
    
    $data = [
        'chat_id' => $chat_id,
        'text' => $text,
        'parse_mode' => 'Markdown'
    ];
    
    $options = [
        'http' => [
            'header' => "Content-type: application/x-www-form-urlencoded\r\n",
            'method' => 'POST',
            'content' => http_build_query($data)
        ]
    ];
    
    $context = stream_context_create($options);
    file_get_contents($url, false, $context);
}

function generateAuthCode() {
    return sprintf("%06d", mt_rand(1, 999999));
}
?>
EOL

# Create Telegram login handler
cat > api/telegram_login.php << 'EOL'
<?php
session_start();
require_once '../config/database.php';
require_once '../config/settings.php';

header('Content-Type: application/json');

try {
    $pdo = new PDO("mysql:host=" . DB_HOST . ";dbname=" . DB_NAME, DB_USER, DB_PASS);
    
    $action = $_POST['action'] ?? '';
    
    switch ($action) {
        case 'request_code':
            // Generate and send auth code
            $auth_code = generateAuthCode();
            $expires = date('Y-m-d H:i:s', time() + 600);
            
            $stmt = $pdo->prepare("INSERT INTO telegram_sessions (auth_code, auth_expires) VALUES (?, ?)");
            $stmt->execute([$auth_code, $expires]);
            
            echo json_encode([
                'success' => true,
                'auth_code' => $auth_code,
                'bot_username' => TELEGRAM_BOT_USERNAME,
                'message' => 'Код отправлен в Telegram'
            ]);
            break;
            
        case 'verify_code':
            // Verify auth code
            $auth_code = $_POST['auth_code'] ?? '';
            
            $stmt = $pdo->prepare("SELECT * FROM telegram_sessions WHERE auth_code = ? AND auth_expires > NOW()");
            $stmt->execute([$auth_code]);
            $session = $stmt->fetch();
            
            if ($session && $session['chat_id']) {
                // Check if user exists
                $stmt = $pdo->prepare("SELECT * FROM users WHERE telegram_id = ?");
                $stmt->execute([$session['chat_id']]);
                $user = $stmt->fetch();
                
                if (!$user) {
                    // Create new user from Telegram data
                    $username = 'tg_' . $session['chat_id'];
                    $stmt = $pdo->prepare("INSERT INTO users (username, telegram_id, auth_method, status) VALUES (?, ?, 'telegram', 'active')");
                    $stmt->execute([$username, $session['chat_id']]);
                    $user_id = $pdo->lastInsertId();
                    
                    $stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
                    $stmt->execute([$user_id]);
                    $user = $stmt->fetch();
                }
                
                // Update session with user ID
                $stmt = $pdo->prepare("UPDATE telegram_sessions SET user_id = ? WHERE auth_code = ?");
                $stmt->execute([$user['id'], $auth_code]);
                
                // Set session
                $_SESSION['user_id'] = $user['id'];
                $_SESSION['user_role'] = $user['role'];
                $_SESSION['auth_method'] = 'telegram';
                
                echo json_encode([
                    'success' => true,
                    'message' => 'Авторизация успешна!',
                    'user' => [
                        'id' => $user['id'],
                        'username' => $user['username']
                    ]
                ]);
            } else {
                echo json_encode([
                    'success' => false,
                    'message' => 'Неверный или просроченный код'
                ]);
            }
            break;
            
        default:
            echo json_encode([
                'success' => false,
                'message' => 'Неизвестное действие'
            ]);
    }
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Ошибка сервера: ' . $e->getMessage()
    ]);
}

function generateAuthCode() {
    return sprintf("%06d", mt_rand(1, 999999));
}
?>
EOL

# Create Telegram bot setup script
cat > telegram/setup_bot.php << 'EOL'
<?php
require_once '../config/database.php';
require_once '../config/settings.php';

if (php_sapi_name() !== 'cli') {
    die('Этот скрипт можно запускать только из командной строки');
}

echo "=== Настройка Telegram бота ===\n";

try {
    $pdo = new PDO("mysql:host=" . DB_HOST . ";dbname=" . DB_NAME, DB_USER, DB_PASS);
    
    // Get bot token from user
    echo "Введите токен вашего Telegram бота: ";
    $bot_token = trim(fgets(STDIN));
    
    if (empty($bot_token)) {
        die("Токен бота не может быть пустым\n");
    }
    
    // Get bot info
    $url = "https://api.telegram.org/bot{$bot_token}/getMe";
    $response = file_get_contents($url);
    $data = json_decode($response, true);
    
    if (!$data['ok']) {
        die("Ошибка: Неверный токен бота\n");
    }
    
    $bot_username = $data['result']['username'];
    echo "Бот найден: @{$bot_username}\n";
    
    // Set webhook
    $webhook_url = SITE_URL . '/api/telegram_webhook.php';
    $set_webhook_url = "https://api.telegram.org/bot{$bot_token}/setWebhook?url={$webhook_url}";
    $webhook_response = file_get_contents($set_webhook_url);
    $webhook_data = json_decode($webhook_response, true);
    
    if ($webhook_data['ok']) {
        echo "Webhook установлен: {$webhook_url}\n";
    } else {
        echo "Ошибка установки webhook: " . $webhook_data['description'] . "\n";
    }
    
    // Update settings in database
    $stmt = $pdo->prepare("UPDATE settings SET setting_value = ? WHERE setting_key = 'telegram_bot_token'");
    $stmt->execute([$bot_token]);
    
    $stmt = $pdo->prepare("UPDATE settings SET setting_value = ? WHERE setting_key = 'telegram_bot_username'");
    $stmt->execute([$bot_username]);
    
    // Update config file
    $config_file = '../config/settings.php';
    $config_content = file_get_contents($config_file);
    $config_content = preg_replace("/define\('TELEGRAM_BOT_TOKEN', '.*?'\);/", "define('TELEGRAM_BOT_TOKEN', '{$bot_token}');", $config_content);
    $config_content = preg_replace("/define\('TELEGRAM_BOT_USERNAME', '.*?'\);/", "define('TELEGRAM_BOT_USERNAME', '{$bot_username}');", $config_content);
    file_put_contents($config_file, $config_content);
    
    echo "\n=== Настройка завершена ===\n";
    echo "Токен бота: {$bot_token}\n";
    echo "Имя бота: @{$bot_username}\n";
    echo "Webhook URL: {$webhook_url}\n";
    echo "\nИнструкция:\n";
    echo "1. Найдите вашего бота в Telegram: @{$bot_username}\n";
    echo "2. Начните диалог с ботом, отправив /start\n";
    echo "3. Используйте код авторизации на сайте\n";
    
} catch (Exception $e) {
    die("Ошибка: " . $e->getMessage() . "\n");
}
?>
EOL

# Create updated user interface with Telegram login
cat > user/index.php << 'EOL'
<?php
session_start();
require_once '../config/database.php';
require_once '../config/settings.php';

try {
    $pdo = new PDO("mysql:host=" . DB_HOST . ";dbname=" . DB_NAME, DB_USER, DB_PASS);
    $channels = $pdo->query("SELECT * FROM channels WHERE is_active = true ORDER BY name")->fetchAll();
    
    // Check Telegram login enabled
    $stmt = $pdo->prepare("SELECT setting_value FROM settings WHERE setting_key = 'telegram_login_enabled'");
    $stmt->execute();
    $telegram_enabled = $stmt->fetchColumn();
    
} catch (PDOException $e) {
    die("Connection failed: " . $e->getMessage());
}
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= SITE_NAME ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        .channel-card { transition: transform 0.2s; }
        .channel-card:hover { transform: translateY(-5px); }
        .player-container { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: black; z-index: 1000; display: none; }
        .telegram-login { background: #0088cc; color: white; border: none; }
        .telegram-login:hover { background: #0077b3; }
    </style>
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-primary">
        <div class="container">
            <a class="navbar-brand" href="#">
                <i class="fas fa-tv"></i> <?= SITE_NAME ?>
            </a>
            
            <div class="navbar-nav ms-auto">
                <?php if (isset($_SESSION['user_id'])): ?>
                    <span class="navbar-text me-3">
                        <i class="fas fa-user"></i> <?= $_SESSION['auth_method'] === 'telegram' ? 'Telegram' : '' ?> 
                        Пользователь #<?= $_SESSION['user_id'] ?>
                    </span>
                    <a href="logout.php" class="btn btn-outline-light btn-sm">Выйти</a>
                <?php else: ?>
                    <button class="btn telegram-login btn-sm" data-bs-toggle="modal" data-bs-target="#telegramModal">
                        <i class="fab fa-telegram"></i> Войти через Telegram
                    </button>
                <?php endif; ?>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        <h2>Телеканалы</h2>
        
        <?php if (!isset($_SESSION['user_id'])): ?>
            <div class="alert alert-info">
                <i class="fas fa-info-circle"></i> Для просмотра каналов войдите через Telegram
            </div>
        <?php endif; ?>
        
        <div class="row" id="channels-container">
            <?php foreach ($channels as $channel): ?>
            <div class="col-md-3 mb-4">
                <div class="card channel-card">
                    <img src="<?= $channel['logo_url'] ?: 'https://via.placeholder.com/300x150?text=TV+Channel' ?>" 
                         class="card-img-top" alt="<?= $channel['name'] ?>" style="height: 150px; object-fit: cover;">
                    <div class="card-body">
                        <h5 class="card-title"><?= htmlspecialchars($channel['name']) ?></h5>
                        <p class="card-text"><?= htmlspecialchars($channel['description']) ?></p>
                        <button class="btn btn-primary btn-sm watch-channel" 
                                data-url="<?= htmlspecialchars($channel['stream_url']) ?>"
                                data-name="<?= htmlspecialchars($channel['name']) ?>"
                                <?= !isset($_SESSION['user_id']) ? 'disabled' : '' ?>>
                            <?= isset($_SESSION['user_id']) ? 'Смотреть' : 'Войдите для просмотра' ?>
                        </button>
                    </div>
                </div>
            </div>
            <?php endforeach; ?>
        </div>
    </div>

    <!-- Telegram Login Modal -->
    <div class="modal fade" id="telegramModal" tabindex="-1">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Вход через Telegram</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <div id="telegram-steps">
                        <div class="step" id="step1">
                            <p>1. Нажмите кнопку ниже чтобы получить код авторизации</p>
                            <button class="btn telegram-login w-100 mb-3" onclick="requestAuthCode()">
                                <i class="fab fa-telegram"></i> Получить код
                            </button>
                        </div>
                        <div class="step" id="step2" style="display: none;">
                            <p>2. Откройте Telegram и найдите бота: <strong id="bot-username"></strong></p>
                            <p>3. Отправьте боту команду <code>/start</code></p>
                            <p>4. Введите полученный код ниже:</p>
                            <div class="input-group mb-3">
                                <input type="text" class="form-control" id="auth-code" placeholder="000000" maxlength="6">
                                <button class="btn btn-primary" onclick="verifyAuthCode()">Подтвердить</button>
                            </div>
                        </div>
                        <div class="step" id="step3" style="display: none;">
                            <div class="alert alert-success">
                                <i class="fas fa-check"></i> Авторизация успешна! Перенаправление...
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Video Player Modal -->
    <div class="player-container" id="player-container">
        <div class="d-flex justify-content-between align-items-center p-3 bg-dark">
            <h4 class="text-white mb-0" id="player-title"></h4>
            <button class="btn btn-danger btn-sm" id="close-player">Закрыть</button>
        </div>
        <video id="video-player" controls autoplay style="width: 100%; height: calc(100% - 60px);">
            Ваш браузер не поддерживает видео тег.
        </video>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Telegram login functions
        function requestAuthCode() {
            fetch('../api/telegram_login.php', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: 'action=request_code'
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    document.getElementById('step1').style.display = 'none';
                    document.getElementById('step2').style.display = 'block';
                    document.getElementById('bot-username').textContent = data.bot_username;
                } else {
                    alert('Ошибка: ' + data.message);
                }
            });
        }

        function verifyAuthCode() {
            const authCode = document.getElementById('auth-code').value;
            
            fetch('../api/telegram_login.php', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: 'action=verify_code&auth_code=' + authCode
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    document.getElementById('step2').style.display = 'none';
                    document.getElementById('step3').style.display = 'block';
                    setTimeout(() => {
                        window.location.reload();
                    }, 2000);
                } else {
                    alert('Ошибка: ' + data.message);
                }
            });
        }

        // Video player functions
        document.querySelectorAll('.watch-channel').forEach(button => {
            button.addEventListener('click', function() {
                const streamUrl = this.getAttribute('data-url');
                const channelName = this.getAttribute('data-name');
                
                document.getElementById('player-title').textContent = channelName;
                document.getElementById('video-player').src = streamUrl;
                document.getElementById('player-container').style.display = 'block';
            });
        });

        document.getElementById('close-player').addEventListener('click', function() {
            document.getElementById('player-container').style.display = 'none';
            document.getElementById('video-player').pause();
        });
    </script>
</body>
</html>
EOL

# Create logout script
cat > user/logout.php << 'EOL'
<?php
session_start();
session_destroy();
header('Location: index.php');
exit;
?>
EOL

# Set permissions
echo -e "${YELLOW}Установка прав доступа...${NC}"
chown -R www-data:www-data $PROJECT_DIR
chmod -R 755 $PROJECT_DIR
chmod -R 777 $PROJECT_DIR/uploads
chmod -R 777 $PROJECT_DIR/logs
chmod -R 777 $PROJECT_DIR/cache
check_success "Права доступа установлены"

# Configure Apache
echo -e "${YELLOW}Настройка Apache...${NC}"
cat > /etc/apache2/sites-available/online-tv.conf << EOL
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot $PROJECT_DIR/user
    
    Alias /admin "$PROJECT_DIR/admin"
    Alias /api "$PROJECT_DIR/api"
    
    <Directory "$PROJECT_DIR">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/online_tv_error.log
    CustomLog \${APACHE_LOG_DIR}/online_tv_access.log combined
</VirtualHost>
EOL

a2ensite online-tv.conf
a2dissite 000-default.conf
systemctl restart apache2
check_success "Apache настроен"

# Setup database
echo -e "${YELLOW}Настройка базы данных...${NC}"
php $PROJECT_DIR/database/setup.php
check_success "База данных настроена"

# Display installation summary
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║           Установка завершена успешно!          ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║                 ДАННЫЕ ДОСТУПА                  ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║ Админ панель: http://localhost/admin            ║"
echo "║ Логин: admin                                    ║"
echo "║ Пароль: admin123                                ║"
echo "║                                                  ║"
echo "║ Пользовательский сайт: http://localhost         ║"
echo "║ База данных: online_tv                          ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}Следующие шаги для настройки Telegram:${NC}"
echo "1. Создайте бота в Telegram через @BotFather"
echo "2. Получите токен бота"
echo "3. Запустите настройку бота:"
echo "   php $PROJECT_DIR/telegram/setup_bot.php"
echo "4. Найдите вашего бота в Telegram и отправьте /start"
echo "5. Используйте код авторизации на сайте"

echo -e "${GREEN}Платформа с Telegram авторизацией готова!${NC}"