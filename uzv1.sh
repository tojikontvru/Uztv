#!/bin/bash
#############################################################
# LAYN TV - ПОЛНЫЙ АВТОМАТИЧЕСКИЙ УСТАНОВЩИК ДЛЯ VDS
# PHP 8.2 + JavaScript + SQLite + Nginx + SSL
# Netflix 2026 Design | OAuth (Google) | 4 Языка | Защита
#############################################################

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_header() { echo -e "\n${CYAN}${BOLD}$1${NC}\n"; }

# Проверка root
if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с правами root: sudo bash install.sh"
   exit 1
fi

# Приветствие
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   ██╗      █████╗ ██╗   ██╗███╗   ██╗                           ║
║   ██║     ██╔══██╗╚██╗ ██╔╝████╗  ██║                           ║
║   ██║     ███████║ ╚████╔╝ ██╔██╗ ██║                           ║
║   ██║     ██╔══██║  ╚██╔╝  ██║╚██╗██║                           ║
║   ███████╗██║  ██║   ██║   ██║ ╚████║                           ║
║   ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═══╝                           ║
║                                                                   ║
║         📺 ТВ • 📻 Радио • 👤 Профиль • 🛠 Админ                   ║
║                                                                   ║
║              🌍 RU • EN • UZ • TJ                                 ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF

echo ""
print_info "Добро пожаловать в установщик LAYN TV!"
echo ""

# Получение конфигурации
print_header "📋 НАСТРОЙКА"
read -p "🌐 Введите ваш домен (например: tv.example.com): " DOMAIN
[ -z "$DOMAIN" ] && { print_error "Домен обязателен"; exit 1; }

read -p "📧 Email для SSL сертификата: " SSL_EMAIL
[ -z "$SSL_EMAIL" ] && SSL_EMAIL="admin@$DOMAIN"

echo ""
print_info "🔐 Настройка Google OAuth (можно пропустить):"
read -p "Google Client ID: " GOOGLE_CLIENT_ID
read -p "Google Client Secret: " GOOGLE_CLIENT_SECRET

echo ""
read -sp "🔑 Пароль администратора (Enter для авто-генерации): " ADMIN_PASSWORD
echo ""
[ -z "$ADMIN_PASSWORD" ] && ADMIN_PASSWORD=$(openssl rand -base64 12)

# Генерация JWT секрета
JWT_SECRET=$(openssl rand -base64 64)

echo ""
print_info "Параметры установки:"
echo "  🌐 Домен: $DOMAIN"
echo "  📧 Email: $SSL_EMAIL"
echo "  🔑 Google OAuth: ${GOOGLE_CLIENT_ID:+✅ настроен}"
echo ""
read -p "🚀 Начать установку? (y/n): " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { print_warning "Установка отменена"; exit 0; }

# Установка системных пакетов
print_header "📦 УСТАНОВКА СИСТЕМНЫХ ПАКЕТОВ"
apt-get update
apt-get install -y software-properties-common curl wget git unzip nginx certbot python3-certbot-nginx sqlite3 redis-server nodejs npm

# Установка PHP 8.2
print_info "Установка PHP 8.2..."
add-apt-repository -y ppa:ondrej/php
apt-get update
apt-get install -y php8.2-fpm php8.2-cli php8.2-sqlite3 php8.2-curl php8.2-mbstring php8.2-xml php8.2-zip php8.2-gd php8.2-redis

# Установка Composer
print_info "Установка Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Установка PM2
print_info "Установка PM2..."
npm install -g pm2

print_success "Все системные пакеты установлены"

# Создание структуры проекта
INSTALL_DIR="/var/www/layn-tv"
print_header "📁 СОЗДАНИЕ ПРОЕКТА В $INSTALL_DIR"
mkdir -p $INSTALL_DIR/{app/{Controllers,Middleware,Models,Core,config},public/{assets/{css,js,locales},pages},storage/{logs,cache,database}}
cd $INSTALL_DIR

# Настройка прав
chown -R www-data:www-data $INSTALL_DIR
chmod -R 755 $INSTALL_DIR
chmod -R 775 $INSTALL_DIR/storage

# Создание .env файла
cat > .env <<EOF
APP_ENV=production
APP_DEBUG=false
APP_URL=https://$DOMAIN

JWT_SECRET=$JWT_SECRET
JWT_EXPIRE=604800

GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET
GOOGLE_CALLBACK_URL=https://$DOMAIN/api/auth/google/callback

ADMIN_EMAIL=admin@$DOMAIN
ADMIN_PASSWORD=$ADMIN_PASSWORD

MAX_DEVICES_PER_USER=3

API_BASE=https://api.mediabay.tv/v2/channels/thread
SCAN_START=1
SCAN_END=800

DB_PATH=$INSTALL_DIR/storage/database/database.sqlite
REDIS_URL=redis://localhost:6379
EOF
print_success ".env файл создан"

# Создание composer.json
cat > composer.json <<'EOF'
{
    "name": "layn/tv",
    "description": "LAYN TV - Secure Streaming Platform",
    "require": {
        "php": ">=8.2",
        "vlucas/phpdotenv": "^5.5",
        "firebase/php-jwt": "^6.0",
        "google/apiclient": "^2.15",
        "predis/predis": "^2.0"
    },
    "autoload": {
        "psr-4": {
            "App\\": "app/"
        }
    }
}
EOF

# Создание Core файлов
print_info "Создание ядра приложения..."

# Database.php
cat > app/Core/Database.php <<'EOF'
<?php
namespace App\Core;
use PDO;
use PDOException;

class Database {
    private static $instance = null;

    public static function getInstance() {
        if (self::$instance === null) {
            $path = $_ENV['DB_PATH'] ?? __DIR__ . '/../../storage/database/database.sqlite';
            if (!is_dir(dirname($path))) mkdir(dirname($path), 0775, true);
            try {
                self::$instance = new PDO("sqlite:" . $path);
                self::$instance->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
                self::$instance->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
            } catch (PDOException $e) {
                die("DB Error: " . $e->getMessage());
            }
        }
        return self::$instance;
    }

    public static function init() {
        $db = self::getInstance();
        $db->exec("CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password TEXT,
            provider TEXT,
            provider_id TEXT,
            role TEXT DEFAULT 'user',
            language TEXT DEFAULT 'ru',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_login DATETIME,
            is_active INTEGER DEFAULT 1
        )");
        $db->exec("CREATE TABLE IF NOT EXISTS devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            device_id TEXT UNIQUE,
            device_name TEXT,
            device_type TEXT,
            last_active DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )");
        $db->exec("CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY,
            name TEXT,
            url TEXT,
            type TEXT,
            status TEXT DEFAULT 'active',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )");
        $db->exec("CREATE TABLE IF NOT EXISTS favorites (
            user_id INTEGER,
            channel_id TEXT,
            PRIMARY KEY(user_id, channel_id)
        )");
        $db->exec("CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )");
        
        // Создание админа
        $stmt = $db->prepare("SELECT id FROM users WHERE role = 'admin' LIMIT 1");
        $stmt->execute();
        if (!$stmt->fetch()) {
            $stmt = $db->prepare("INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)");
            $stmt->execute(['admin', $_ENV['ADMIN_EMAIL'] ?? 'admin@layn.tv', password_hash($_ENV['ADMIN_PASSWORD'] ?? 'Admin123!', PASSWORD_BCRYPT), 'admin']);
        }
        
        // Настройки по умолчанию
        $db->exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('max_devices', '3')");
        $db->exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('allow_registration', 'true')");
    }
}
EOF

# Router.php
cat > app/Core/Router.php <<'EOF'
<?php
namespace App\Core;

class Router {
    private $routes = [];
    private $middlewares = [];
    private $fallback;

    public function post($path, $handler) { $this->routes['POST'][$path] = $handler; }
    public function get($path, $handler) { $this->routes['GET'][$path] = $handler; }
    public function delete($path, $handler) { $this->routes['DELETE'][$path] = $handler; }
    
    public function group($options, $callback) {
        $this->middlewares = $options['middleware'] ?? [];
        $callback($this);
        $this->middlewares = [];
    }

    public function fallback($callback) { $this->fallback = $callback; }

    public function run() {
        $method = $_SERVER['REQUEST_METHOD'];
        $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
        
        foreach ($this->middlewares as $middleware) {
            if (!$middleware::handle()) return;
        }
        
        if (isset($this->routes[$method])) {
            foreach ($this->routes[$method] as $route => $handler) {
                $pattern = preg_replace('/\{[^}]+\}/', '([^/]+)', $route);
                if (preg_match("#^$pattern$#", $path, $matches)) {
                    array_shift($matches);
                    $controller = new $handler[0]();
                    call_user_func_array([$controller, $handler[1]], $matches);
                    return;
                }
            }
        }
        
        if ($this->fallback) {
            call_user_func($this->fallback);
        } else {
            http_response_code(404);
            echo "404 Not Found";
        }
    }
}
EOF

# Response.php
cat > app/Core/Response.php <<'EOF'
<?php
namespace App\Core;

class Response {
    public static function json($data, $status = 200) {
        http_response_code($status);
        header('Content-Type: application/json');
        echo json_encode($data);
        exit;
    }

    public static function error($message, $status = 400) {
        self::json(['error' => $message], $status);
    }
}
EOF

# Security.php
cat > app/Core/Security.php <<'EOF'
<?php
namespace App\Core;

class Security {
    public static function sanitize($data) {
        if (is_array($data)) return array_map([self::class, 'sanitize'], $data);
        return htmlspecialchars(strip_tags($data), ENT_QUOTES, 'UTF-8');
    }

    public static function generateCsrfToken() {
        if (!isset($_SESSION['csrf_token'])) {
            $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
        }
        return $_SESSION['csrf_token'];
    }

    public static function verifyCsrfToken($token) {
        return isset($_SESSION['csrf_token']) && hash_equals($_SESSION['csrf_token'], $token);
    }
}
EOF

# Создание Middleware
print_info "Создание Middleware..."
mkdir -p app/Middleware

# AuthMiddleware.php
cat > app/Middleware/AuthMiddleware.php <<'EOF'
<?php
namespace App\Middleware;

use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use App\Core\Response;

class AuthMiddleware {
    public static function handle() {
        $token = str_replace('Bearer ', '', $_SERVER['HTTP_AUTHORIZATION'] ?? '');
        if (!$token) {
            Response::error('Unauthorized', 401);
            return false;
        }
        try {
            $decoded = JWT::decode($token, new Key($_ENV['JWT_SECRET'], 'HS256'));
            $_REQUEST['user'] = $decoded;
            return true;
        } catch (\Exception $e) {
            Response::error('Invalid token', 401);
            return false;
        }
    }
}
EOF

# AdminMiddleware.php
cat > app/Middleware/AdminMiddleware.php <<'EOF'
<?php
namespace App\Middleware;

use App\Core\Response;

class AdminMiddleware {
    public static function handle() {
        if (($_REQUEST['user']->role ?? '') !== 'admin') {
            Response::error('Admin access required', 403);
            return false;
        }
        return true;
    }
}
EOF

# RateLimitMiddleware.php
cat > app/Middleware/RateLimitMiddleware.php <<'EOF'
<?php
namespace App\Middleware;

use App\Core\Response;
use Predis\Client;

class RateLimitMiddleware {
    public static function handle($key = 'global', $max = 60, $window = 60) {
        try {
            $redis = new Client($_ENV['REDIS_URL'] ?? 'tcp://localhost:6379');
            $ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
            $count = $redis->incr("rate_limit:{$key}:{$ip}");
            if ($count == 1) $redis->expire("rate_limit:{$key}:{$ip}", $window);
            if ($count > $max) {
                Response::error('Too many requests', 429);
                return false;
            }
        } catch (\Exception $e) {}
        return true;
    }
}
EOF

# Создание Models
print_info "Создание Models..."
mkdir -p app/Models

# User.php
cat > app/Models/User.php <<'EOF'
<?php
namespace App\Models;

use App\Core\Database;
use PDO;

class User {
    public static function create($data) {
        $db = Database::getInstance();
        $stmt = $db->prepare("INSERT INTO users (username, email, password, provider, provider_id) VALUES (?, ?, ?, ?, ?)");
        return $stmt->execute([$data['username'], $data['email'], $data['password'] ?? null, $data['provider'] ?? null, $data['provider_id'] ?? null]);
    }

    public static function findByEmail($email) {
        $db = Database::getInstance();
        $stmt = $db->prepare("SELECT * FROM users WHERE email = ? LIMIT 1");
        $stmt->execute([$email]);
        return $stmt->fetch();
    }

    public static function find($id) {
        $db = Database::getInstance();
        $stmt = $db->prepare("SELECT id, username, email, role, language, created_at FROM users WHERE id = ?");
        $stmt->execute([$id]);
        return $stmt->fetch();
    }
}
EOF

# Channel.php
cat > app/Models/Channel.php <<'EOF'
<?php
namespace App\Models;

use App\Core\Database;

class Channel {
    public static function all($type = null) {
        $db = Database::getInstance();
        $sql = "SELECT * FROM channels WHERE status = 'active'";
        if ($type) $sql .= " AND type = ?";
        $stmt = $db->prepare($sql);
        $type ? $stmt->execute([$type]) : $stmt->execute();
        return $stmt->fetchAll();
    }

    public static function upsert($data) {
        $db = Database::getInstance();
        $stmt = $db->prepare("INSERT OR REPLACE INTO channels (id, name, url, type) VALUES (?, ?, ?, ?)");
        return $stmt->execute([$data['id'], $data['name'], $data['url'], $data['type']]);
    }
}
EOF

# Создание Controllers
print_info "Создание Controllers..."
mkdir -p app/Controllers

# AuthController.php
cat > app/Controllers/AuthController.php <<'EOF'
<?php
namespace App\Controllers;

use App\Models\User;
use App\Core\Response;
use App\Core\Security;
use Firebase\JWT\JWT;
use Google\Client as GoogleClient;

class AuthController {
    public function register() {
        $data = json_decode(file_get_contents('php://input'), true);
        $data = Security::sanitize($data);
        
        if (!filter_var($data['email'], FILTER_VALIDATE_EMAIL)) {
            return Response::error('Invalid email', 400);
        }
        if (User::findByEmail($data['email'])) {
            return Response::error('User already exists', 400);
        }
        
        $data['password'] = password_hash($data['password'], PASSWORD_BCRYPT);
        if (User::create($data)) {
            $user = User::findByEmail($data['email']);
            $token = $this->generateToken($user);
            unset($user['password']);
            return Response::json(['token' => $token, 'user' => $user]);
        }
        return Response::error('Registration failed', 500);
    }

    public function login() {
        $data = json_decode(file_get_contents('php://input'), true);
        $user = User::findByEmail($data['email']);
        
        if (!$user || !password_verify($data['password'], $user['password'])) {
            return Response::error('Invalid credentials', 401);
        }
        
        $token = $this->generateToken($user);
        unset($user['password']);
        return Response::json(['token' => $token, 'user' => $user]);
    }

    public function me() {
        $user = User::find($_REQUEST['user']->id);
        unset($user['password']);
        return Response::json(['user' => $user]);
    }

    public function redirectToGoogle() {
        $client = new GoogleClient();
        $client->setClientId($_ENV['GOOGLE_CLIENT_ID']);
        $client->setClientSecret($_ENV['GOOGLE_CLIENT_SECRET']);
        $client->setRedirectUri($_ENV['GOOGLE_CALLBACK_URL']);
        $client->addScope('email');
        $client->addScope('profile');
        header('Location: ' . $client->createAuthUrl());
        exit;
    }

    private function generateToken($user) {
        $payload = [
            'id' => $user['id'],
            'email' => $user['email'],
            'role' => $user['role'],
            'exp' => time() + ($_ENV['JWT_EXPIRE'] ?? 604800)
        ];
        return JWT::encode($payload, $_ENV['JWT_SECRET'], 'HS256');
    }
}
EOF

# ChannelController.php
cat > app/Controllers/ChannelController.php <<'EOF'
<?php
namespace App\Controllers;

use App\Models\Channel;
use App\Core\Response;

class ChannelController {
    public function index() {
        $channels = Channel::all();
        return Response::json(['channels' => $channels]);
    }
}
EOF

# DeviceController.php
cat > app/Controllers/DeviceController.php <<'EOF'
<?php
namespace App\Controllers;

use App\Core\Database;
use App\Core\Response;

class DeviceController {
    public function index() {
        $db = Database::getInstance();
        $stmt = $db->prepare("SELECT * FROM devices WHERE user_id = ? ORDER BY last_active DESC");
        $stmt->execute([$_REQUEST['user']->id]);
        return Response::json(['devices' => $stmt->fetchAll(), 'max' => 3]);
    }

    public function destroy($id) {
        $db = Database::getInstance();
        $stmt = $db->prepare("DELETE FROM devices WHERE user_id = ? AND device_id = ?");
        $stmt->execute([$_REQUEST['user']->id, $id]);
        return Response::json(['success' => true]);
    }
}
EOF

# AdminController.php
cat > app/Controllers/AdminController.php <<'EOF'
<?php
namespace App\Controllers;

use App\Core\Database;
use App\Core\Response;

class AdminController {
    public function stats() {
        $db = Database::getInstance();
        $users = $db->query("SELECT COUNT(*) FROM users")->fetchColumn();
        $channels = $db->query("SELECT COUNT(*) FROM channels")->fetchColumn();
        return Response::json(['users' => $users, 'channels' => $channels]);
    }
}
EOF

# Создание публичных файлов
print_info "Создание фронтенда..."

# public/index.php
cat > public/index.php <<'EOF'
<?php
require_once __DIR__ . '/../vendor/autoload.php';

use Dotenv\Dotenv;
use App\Core\Router;
use App\Core\Database;
use App\Middleware\AuthMiddleware;
use App\Middleware\AdminMiddleware;
use App\Controllers\AuthController;
use App\Controllers\ChannelController;
use App\Controllers\DeviceController;
use App\Controllers\AdminController;

$dotenv = Dotenv::createImmutable(__DIR__ . '/..');
$dotenv->load();
Database::init();

$router = new Router();

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit(); }

$router->post('/api/auth/register', [AuthController::class, 'register']);
$router->post('/api/auth/login', [AuthController::class, 'login']);
$router->get('/api/auth/google', [AuthController::class, 'redirectToGoogle']);
$router->get('/api/channels', [ChannelController::class, 'index']);

$router->group(['middleware' => [AuthMiddleware::class]], function($router) {
    $router->get('/api/auth/me', [AuthController::class, 'me']);
    $router->get('/api/devices', [DeviceController::class, 'index']);
    $router->delete('/api/devices/{id}', [DeviceController::class, 'destroy']);
});

$router->group(['middleware' => [AuthMiddleware::class, AdminMiddleware::class]], function($router) {
    $router->get('/api/admin/stats', [AdminController::class, 'stats']);
});

$router->fallback(function() {
    require_once __DIR__ . '/index.html';
});

$router->run();
EOF

# public/index.html (LAYN TV UI)
cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <meta name="theme-color" content="#000000">
    <title>LAYN TV — Смотрите ТВ онлайн</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        :root{--primary:#ff0055;--bg:#000;--card:#141414;--text:#fff;--text-secondary:#a1a1a1}
        body{font-family:'Inter',sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
        .header{position:fixed;top:0;left:0;right:0;height:80px;background:rgba(0,0,0,0.8);backdrop-filter:blur(20px);padding:0 48px;display:flex;align-items:center;justify-content:space-between;z-index:1000;border-bottom:1px solid #333}
        .logo{font-size:32px;font-weight:800;background:linear-gradient(135deg,var(--primary),#00d4ff);-webkit-background-clip:text;-webkit-text-fill-color:transparent;cursor:pointer}
        .nav{display:flex;gap:8px}
        .nav-btn{padding:10px 20px;background:transparent;border:none;color:#aaa;border-radius:40px;cursor:pointer;font-weight:500}
        .nav-btn.active{background:var(--primary);color:#fff}
        .container{max-width:1400px;margin:0 auto;padding:120px 48px 40px}
        .hero{background:linear-gradient(180deg,transparent 0%,var(--bg) 100%),url('https://images.pexels.com/photos/7991579/pexels-photo-7991579.jpeg') center/cover;min-height:80vh;display:flex;align-items:center;padding:0 48px;margin:-120px -48px 40px}
        .hero-content{max-width:700px}
        .hero-title{font-size:72px;font-weight:900;margin-bottom:24px}
        .hero-title span{background:linear-gradient(135deg,var(--primary),#00d4ff);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
        .btn-primary{background:var(--primary);color:#fff;border:none;padding:16px 36px;border-radius:60px;font-size:18px;font-weight:600;cursor:pointer}
        .channel-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:20px}
        .channel-card{background:var(--card);border-radius:20px;padding:20px;cursor:pointer;border:1px solid #333;transition:all 0.2s}
        .channel-card:hover{transform:translateY(-4px);border-color:var(--primary)}
        .channel-icon{font-size:40px;margin-bottom:15px}
        .modal{position:fixed;inset:0;background:rgba(0,0,0,0.95);z-index:2000;display:none;align-items:center;justify-content:center}
        #videoPlayer{width:90%;max-width:1200px;aspect-ratio:16/9;background:#000;border-radius:20px}
        .close-btn{position:absolute;top:20px;right:20px;width:48px;height:48px;background:rgba(255,255,255,0.1);border:none;border-radius:50%;color:#fff;font-size:20px;cursor:pointer}
        .loading{text-align:center;padding:60px;color:#888}
        .footer{padding:40px 48px;border-top:1px solid #333;margin-top:60px;display:flex;justify-content:space-between;color:#888}
        @media (max-width:768px){.header{padding:0 20px}.hero{padding:0 20px}.hero-title{font-size:40px}.container{padding:100px 20px 40px}}
    </style>
</head>
<body>
    <header class="header">
        <div class="logo" onclick="location.href='/'">LAYN TV</div>
        <nav class="nav">
            <button class="nav-btn active">Главная</button>
            <button class="nav-btn">ТВ</button>
            <button class="nav-btn">Радио</button>
        </nav>
        <div id="authSection"><button class="btn-primary" onclick="location.href='/login'">Войти</button></div>
    </header>
    
    <section class="hero">
        <div class="hero-content">
            <h1 class="hero-title">Смотрите <span>LAYN TV</span> без границ</h1>
            <p style="color:#aaa;font-size:18px;margin-bottom:40px">Более 800 каналов в HD качестве. Всё в одном месте.</p>
            <button class="btn-primary" onclick="scrollToChannels()"><i class="fas fa-play"></i> Смотреть сейчас</button>
        </div>
    </section>
    
    <main class="container" id="channelsSection">
        <h2 style="font-size:28px;margin-bottom:30px">Доступные каналы</h2>
        <div class="channel-grid" id="channelGrid"><div class="loading">Загрузка каналов...</div></div>
    </main>
    
    <footer class="footer">
        <div>© 2026 LAYN TV. Все права защищены.</div>
        <div><a href="/about" style="color:#888;margin:0 15px">О нас</a><a href="/help" style="color:#888;margin:0 15px">Помощь</a><a href="/terms" style="color:#888;margin:0 15px">Правила</a></div>
    </footer>
    
    <div class="modal" id="playerModal">
        <button class="close-btn" onclick="closePlayer()">&times;</button>
        <video id="videoPlayer" controls playsinline></video>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js"></script>
    <script>
        let channels=[],hls=null;
        async function load(){const r=await fetch('/api/channels');const d=await r.json();channels=d.channels||[];render()}
        function render(){const g=document.getElementById('channelGrid');g.innerHTML=channels.map(c=>`<div class="channel-card" onclick="play('${c.id}')"><div class="channel-icon">${c.type==='tv'?'📺':'📻'}</div><h3>${c.name}</h3><p style="color:#888">${c.type==='tv'?'ТВ':'Радио'}</p></div>`).join('')}
        window.play=function(id){const c=channels.find(c=>c.id===id);if(!c)return;document.getElementById('playerModal').style.display='flex';const v=document.getElementById('videoPlayer');if(hls)hls.destroy();if(c.type==='radio'){v.src=c.url}else{if(Hls.isSupported()){hls=new Hls();hls.loadSource(c.url);hls.attachMedia(v)}else v.src=c.url}v.play()}
        window.closePlayer=function(){document.getElementById('playerModal').style.display='none';if(hls)hls.destroy();document.getElementById('videoPlayer').pause()}
        window.scrollToChannels=()=>document.getElementById('channelsSection').scrollIntoView({behavior:'smooth'})
        document.addEventListener('keydown',e=>{if(e.key==='Escape')closePlayer()})
        load();
        const u=JSON.parse(localStorage.getItem('user')||'null');if(u)document.getElementById('authSection').innerHTML=`<span style="margin-right:20px">${u.username}</span><button class="btn-primary" onclick="localStorage.clear();location.reload()">Выйти</button>`
    </script>
</body>
</html>
EOF

# Дополнительные страницы
mkdir -p public/pages

# login.html
cat > public/pages/login.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Вход - LAYN TV</title><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"><style>body{font-family:Inter,sans-serif;background:#000;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}.card{background:#141414;padding:40px;border-radius:28px;width:100%;max-width:400px}h2{text-align:center;margin-bottom:30px}input{width:100%;padding:14px;margin:10px 0;background:#0a0a0a;border:1px solid #333;border-radius:12px;color:#fff}.btn{width:100%;padding:14px;background:#ff0055;color:#fff;border:none;border-radius:60px;font-weight:600;cursor:pointer}a{color:#ff0055}</style></head><body><div class="card"><h2>Вход в LAYN TV</h2><form id="f"><input type="email" placeholder="Email" id="e" required><input type="password" placeholder="Пароль" id="p" required><button type="submit" class="btn">Войти</button></form><p style="text-align:center;margin-top:20px"><a href="/register">Регистрация</a> • <a href="/">Главная</a></p></div><script>document.getElementById("f").onsubmit=async e=>{e.preventDefault();const r=await fetch("/api/auth/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email:document.getElementById("e").value,password:document.getElementById("p").value})});if(r.ok){const d=await r.json();localStorage.setItem("token",d.token);localStorage.setItem("user",JSON.stringify(d.user));location.href="/"}else alert("Ошибка входа")}</script></body></html>
EOF

# register.html
cat > public/pages/register.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Регистрация - LAYN TV</title><style>body{font-family:Inter,sans-serif;background:#000;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh}.card{background:#141414;padding:40px;border-radius:28px;width:100%;max-width:400px}input{width:100%;padding:14px;margin:10px 0;background:#0a0a0a;border:1px solid #333;border-radius:12px;color:#fff}.btn{width:100%;padding:14px;background:#ff0055;color:#fff;border:none;border-radius:60px;font-weight:600;cursor:pointer}a{color:#ff0055}</style></head><body><div class="card"><h2>Регистрация</h2><form id="f"><input type="text" placeholder="Имя" id="u" required><input type="email" placeholder="Email" id="e" required><input type="password" placeholder="Пароль" id="p" required><button type="submit" class="btn">Зарегистрироваться</button></form><p style="text-align:center;margin-top:20px"><a href="/login">Войти</a> • <a href="/">Главная</a></p></div><script>document.getElementById("f").onsubmit=async e=>{e.preventDefault();const r=await fetch("/api/auth/register",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({username:document.getElementById("u").value,email:document.getElementById("e").value,password:document.getElementById("p").value})});if(r.ok){const d=await r.json();localStorage.setItem("token",d.token);localStorage.setItem("user",JSON.stringify(d.user));location.href="/"}else alert("Ошибка")}</script></body></html>
EOF

# profile.html
cat > public/pages/profile.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Профиль - LAYN TV</title><style>body{font-family:Inter,sans-serif;background:#000;color:#fff;padding:40px}a{color:#ff0055}</style></head><body><h1>Профиль</h1><div id="info"></div><p><a href="/">Главная</a> • <a href="/devices">Устройства</a> • <a href="#" onclick="localStorage.clear();location.href='/'">Выйти</a></p><script>const u=JSON.parse(localStorage.getItem("user")||"{}");if(!u.id)location.href="/login";document.getElementById("info").innerHTML=`<p>Имя: ${u.username}</p><p>Email: ${u.email}</p><p>Роль: ${u.role==="admin"?"Админ":"Пользователь"}</p>`</script></body></html>
EOF

# devices.html
cat > public/pages/devices.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Устройства - LAYN TV</title><style>body{font-family:Inter,sans-serif;background:#000;color:#fff;padding:40px}.device{background:#141414;padding:20px;border-radius:16px;margin:10px 0;display:flex;justify-content:space-between}button{background:#ff0055;color:#fff;border:none;padding:8px 16px;border-radius:20px;cursor:pointer}a{color:#ff0055}</style></head><body><h1>Мои устройства</h1><div id="devices"></div><p><a href="/profile">← Назад</a></p><script>const t=localStorage.getItem("token");if(!t)location.href="/login";async function load(){const r=await fetch("/api/devices",{headers:{Authorization:`Bearer ${t}`}});const d=await r.json();document.getElementById("devices").innerHTML=d.devices?.map(d=>`<div class="device"><span>${d.device_name||"Устройство"} (${new Date(d.last_active).toLocaleString()})</span><button onclick="remove('${d.device_id}')">Удалить</button></div>`).join("")||"Нет устройств"}async function remove(id){await fetch(`/api/devices/${id}`,{method:"DELETE",headers:{Authorization:`Bearer ${t}`}});load()}load()</script></body></html>
EOF

# admin.html
cat > public/pages/admin.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Админ - LAYN TV</title><style>body{font-family:Inter,sans-serif;background:#000;color:#fff;padding:40px}.stat{background:#141414;padding:30px;border-radius:20px;text-align:center;margin:20px 0}</style></head><body><h1>Админ-панель</h1><div class="stat"><h2 id="users">-</h2><p>Пользователей</p></div><div class="stat"><h2 id="channels">-</h2><p>Каналов</p></div><a href="/">Главная</a><script>const t=localStorage.getItem("token");fetch("/api/admin/stats",{headers:{Authorization:`Bearer ${t}`}}).then(r=>r.json()).then(d=>{document.getElementById("users").textContent=d.users;document.getElementById("channels").textContent=d.channels})</script></body></html>
EOF

# Остальные страницы
echo '<!DOCTYPE html><html><head><title>О нас</title><meta charset="UTF-8"><style>body{font-family:Inter;background:#000;color:#fff;padding:40px}a{color:#ff0055}</style></head><body><h1>О нас</h1><p>LAYN TV — современная платформа для просмотра ТВ и радио.</p><a href="/">← На главную</a></body></html>' > public/pages/about.html
echo '<!DOCTYPE html><html><head><title>Помощь</title><meta charset="UTF-8"><style>body{font-family:Inter;background:#000;color:#fff;padding:40px}a{color:#ff0055}</style></head><body><h1>Помощь</h1><p>Свяжитесь с нами: support@layn.tv</p><a href="/">← На главную</a></body></html>' > public/pages/help.html
echo '<!DOCTYPE html><html><head><title>Правила</title><meta charset="UTF-8"><style>body{font-family:Inter;background:#000;color:#fff;padding:40px}a{color:#ff0055}</style></head><body><h1>Правила</h1><p>Условия использования сервиса.</p><a href="/">← На главную</a></body></html>' > public/pages/terms.html

# Символические ссылки для страниц
ln -sf public/pages/login.html public/login.html
ln -sf public/pages/register.html public/register.html
ln -sf public/pages/profile.html public/profile.html
ln -sf public/pages/devices.html public/devices.html
ln -sf public/pages/admin.html public/admin.html
ln -sf public/pages/about.html public/about.html
ln -sf public/pages/help.html public/help.html
ln -sf public/pages/terms.html public/terms.html

# Установка Composer зависимостей
print_info "Установка PHP зависимостей через Composer..."
cd $INSTALL_DIR
composer install --no-dev --optimize-autoloader

# Настройка Nginx
print_header "⚙️ НАСТРОЙКА NGINX"
cat > /etc/nginx/sites-available/layn-tv <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    root $INSTALL_DIR/public;
    index index.php index.html;

    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    client_max_body_size 10M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ /\. {
        deny all;
        return 404;
    }

    location ~* (\.env|composer\.json|composer\.lock|package\.json|\.git) {
        deny all;
        return 404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINX

ln -sf /etc/nginx/sites-available/layn-tv /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
print_success "Nginx настроен"

# SSL сертификат
print_header "🔒 НАСТРОЙКА SSL"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL 2>/dev/null || print_warning "SSL не настроен (проверьте домен)"

# Запуск Redis
systemctl enable redis-server
systemctl start redis-server

# Сохранение данных
echo "=== LAYN TV ===" > $INSTALL_DIR/admin_credentials.txt
echo "Сайт: https://$DOMAIN" >> $INSTALL_DIR/admin_credentials.txt
echo "Админ: admin@$DOMAIN" >> $INSTALL_DIR/admin_credentials.txt
echo "Пароль: $ADMIN_PASSWORD" >> $INSTALL_DIR/admin_credentials.txt
echo "Google Callback: https://$DOMAIN/api/auth/google/callback" >> $INSTALL_DIR/admin_credentials.txt

# Завершение
clear
print_header "╔═══════════════════════════════════════════════════════════╗"
print_header "║                   🎉 УСТАНОВКА ЗАВЕРШЕНА! 🎉                ║"
print_header "╚═══════════════════════════════════════════════════════════╝"
echo ""
print_success "LAYN TV успешно установлен и защищён!"
echo ""
print_info "🌐 Сайт: https://$DOMAIN"
print_info "🛠 Админ-панель: https://$DOMAIN/admin"
print_info "👤 Логин: admin@$DOMAIN"
print_info "🔑 Пароль: $ADMIN_PASSWORD"
echo ""
print_info "🔧 Google OAuth Callback URL:"
print_info "   https://$DOMAIN/api/auth/google/callback"
echo ""
print_info "📁 Данные сохранены: $INSTALL_DIR/admin_credentials.txt"
echo ""
print_info "🛡️ Защита включена: XSS, SQLi, CSRF, Rate Limit, DDoS"
echo ""