#!/bin/bash
#############################################################
# Vision TV - Complete Auto-Installer for VDS
# Features: OAuth (Yandex/Google), 4 Languages, Admin Panel
# Device Limit: 3 per user, Modern UI
#############################################################

set -e

# Colors
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
print_header() { echo -e "${CYAN}${BOLD}$1${NC}"; }

# Root check
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Welcome screen
clear
print_header "╔═══════════════════════════════════════════════════════════╗"
print_header "║                                                           ║"
print_header "║   ██╗   ██╗██╗███████╗██╗ ██████╗ ███╗   ██╗              ║"
print_header "║   ██║   ██║██║██╔════╝██║██╔═══██╗████╗  ██║              ║"
print_header "║   ██║   ██║██║███████╗██║██║   ██║██╔██╗ ██║              ║"
print_header "║   ╚██╗ ██╔╝██║╚════██║██║██║   ██║██║╚██╗██║              ║"
print_header "║    ╚████╔╝ ██║███████║██║╚██████╔╝██║ ╚████║              ║"
print_header "║     ╚═══╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝              ║"
print_header "║                                                           ║"
print_header "║         📺 TV • 📻 Radio • 👤 Profile • 🛠 Admin           ║"
print_header "║                                                           ║"
print_header "╚═══════════════════════════════════════════════════════════╝"
echo ""
print_info "Добро пожаловать в автоматический установщик Vision TV!"
echo ""

# Get configuration
print_header "📋 НАСТРОЙКА УСТАНОВКИ"
echo "========================================="
read -p "Введите ваш домен (например: tv.example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    print_error "Домен обязателен для установки"
    exit 1
fi

read -p "Email для SSL сертификата Let's Encrypt: " SSL_EMAIL
[ -z "$SSL_EMAIL" ] && SSL_EMAIL="admin@$DOMAIN"

read -p "Порт для сервера (по умолчанию 3000): " SERVER_PORT
[ -z "$SERVER_PORT" ] && SERVER_PORT=3000

echo ""
print_info "🔐 Настройка OAuth авторизации (можно пропустить, нажав Enter):"
echo "--------------------------------------------------------------"
read -p "Yandex Client ID: " YANDEX_CLIENT_ID
read -p "Yandex Client Secret: " YANDEX_CLIENT_SECRET
read -p "Google Client ID: " GOOGLE_CLIENT_ID
read -p "Google Client Secret: " GOOGLE_CLIENT_SECRET

echo ""
read -sp "Пароль для администратора (Enter для авто-генерации): " ADMIN_PASSWORD
echo ""
[ -z "$ADMIN_PASSWORD" ] && ADMIN_PASSWORD=$(openssl rand -base64 12)

echo ""
print_info "Параметры установки:"
echo "  🌐 Домен: $DOMAIN"
echo "  📧 Email SSL: $SSL_EMAIL"
echo "  🔌 Порт: $SERVER_PORT"
echo "  🔑 Yandex OAuth: ${YANDEX_CLIENT_ID:+✅ настроен}"
echo "  🔑 Google OAuth: ${GOOGLE_CLIENT_ID:+✅ настроен}"
echo ""
read -p "Начать установку? (y/n): " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { print_warning "Установка отменена"; exit 0; }

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    print_error "Не удалось определить ОС"
    exit 1
fi
print_info "Обнаружена ОС: $OS $VERSION"

# Install Node.js 20.x
print_header "📦 УСТАНОВКА NODE.JS 20.x"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get remove -y nodejs npm 2>/dev/null || true
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]]; then
    yum remove -y nodejs npm 2>/dev/null || true
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    yum install -y nodejs
fi
NODE_VERSION=$(node -v)
print_success "Node.js установлен: $NODE_VERSION"

# Install system dependencies
print_header "📦 УСТАНОВКА СИСТЕМНЫХ ЗАВИСИМОСТЕЙ"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y curl wget git nginx certbot python3-certbot-nginx sqlite3 redis-server
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]]; then
    yum update -y
    yum install -y curl wget git nginx certbot python3-certbot-nginx sqlite redis
    systemctl enable redis
    systemctl start redis
fi
npm install -g npm@latest pm2
print_success "Системные зависимости установлены"

# Create project structure
INSTALL_DIR="/var/www/vision-tv"
print_header "📁 СОЗДАНИЕ СТРУКТУРЫ ПРОЕКТА"
print_info "Директория: $INSTALL_DIR"
mkdir -p $INSTALL_DIR/{backend/{config,routes,models,database},frontend/{css,js,locales,admin},data,logs}
cd $INSTALL_DIR

# Generate secrets
JWT_SECRET=$(openssl rand -base64 32)
SESSION_SECRET=$(openssl rand -base64 32)

# Create .env file
cat > .env <<EOF
# Vision TV Configuration
DOMAIN=$DOMAIN
PORT=$SERVER_PORT
NODE_ENV=production

# Database
DB_PATH=$INSTALL_DIR/data/database.db
REDIS_URL=redis://localhost:6379

# Security
JWT_SECRET=$JWT_SECRET
SESSION_SECRET=$SESSION_SECRET

# OAuth Configuration
YANDEX_CLIENT_ID=$YANDEX_CLIENT_ID
YANDEX_CLIENT_SECRET=$YANDEX_CLIENT_SECRET
YANDEX_CALLBACK_URL=https://$DOMAIN/api/auth/yandex/callback

GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET
GOOGLE_CALLBACK_URL=https://$DOMAIN/api/auth/google/callback

# Admin
ADMIN_EMAIL=admin@$DOMAIN
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Limits
MAX_DEVICES_PER_USER=3
MAX_FAVORITES=100

# API Settings
API_BASE=https://api.mediabay.tv/v2/channels/thread
SCAN_START=1
SCAN_END=800
EOF
print_success ".env файл создан"

# Create package.json
cat > package.json <<'EOF'
{
  "name": "vision-tv",
  "version": "3.0.0",
  "description": "Modern TV and Radio Streaming Platform",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "express-session": "^1.17.3",
    "connect-redis": "^7.1.0",
    "redis": "^4.6.7",
    "sqlite3": "^5.1.6",
    "passport": "^0.6.0",
    "passport-google-oauth20": "^2.0.0",
    "passport-yandex": "^1.0.4",
    "express-rate-limit": "^6.10.0",
    "compression": "^1.7.4",
    "morgan": "^1.10.0",
    "dotenv": "^16.3.1",
    "axios": "^1.5.0",
    "socket.io": "^4.6.2",
    "multer": "^1.4.5-lts.1"
  },
  "engines": { "node": ">=18.0.0" }
}
EOF

# Create server.js
cat > server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const session = require('express-session');
const passport = require('passport');
const RedisStore = require('connect-redis').default;
const { createClient } = require('redis');
const path = require('path');
const http = require('http');
const socketIo = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, { cors: { origin: true, credentials: true } });

// Redis
const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect().catch(console.error);

// Middleware
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com", "https://cdnjs.cloudflare.com"],
            fontSrc: ["'self'", "https://fonts.gstatic.com", "https://cdnjs.cloudflare.com"],
            scriptSrc: ["'self'", "'unsafe-inline'", "https://apis.google.com", "https://cdn.jsdelivr.net", "https://yastatic.net"],
            imgSrc: ["'self'", "data:", "https:", "https://avatars.yandex.net", "https://lh3.googleusercontent.com"],
            mediaSrc: ["'self'", "blob:", "https:"],
            connectSrc: ["'self'", "https://api.mediabay.tv", "https://accounts.google.com", "https://oauth.yandex.ru"]
        }
    }
}));
app.use(cors({ origin: true, credentials: true }));
app.use(compression());
app.use(morgan('combined'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Session
app.use(session({
    store: new RedisStore({ client: redisClient }),
    secret: process.env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    cookie: { secure: process.env.NODE_ENV === 'production', httpOnly: true, maxAge: 7 * 24 * 60 * 60 * 1000 }
}));

// Passport
app.use(passport.initialize());
app.use(passport.session());
require('./backend/config/passport')(passport);

// Static
app.use(express.static(path.join(__dirname, 'frontend')));
app.use('/uploads', express.static(path.join(__dirname, 'data/uploads')));

// DB
require('./backend/database/init')();

// Routes
app.use('/api/auth', require('./backend/routes/auth'));
app.use('/api/channels', require('./backend/routes/channels'));
app.use('/api/devices', require('./backend/routes/devices'));
app.use('/api/admin', require('./backend/routes/admin'));

// Locales API
app.get('/api/locales/:lang', (req, res) => {
    try { res.json(require(`./frontend/locales/${req.params.lang}.json`)); }
    catch { res.status(404).json({ error: 'Language not found' }); }
});

// SPA fallback
app.get('*', (req, res) => res.sendFile(path.join(__dirname, 'frontend/index.html')));

io.on('connection', (socket) => {
    socket.on('join-room', (room) => socket.join(room));
    socket.on('watch-together', (data) => socket.to(data.room).emit('sync-playback', data));
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`🚀 Vision TV running on port ${PORT}`));
EOF

# Create passport config
mkdir -p backend/config
cat > backend/config/passport.js <<'EOF'
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const YandexStrategy = require('passport-yandex').Strategy;
const db = require('../database/init').db;

module.exports = function(passport) {
    passport.serializeUser((user, done) => done(null, user.id));
    passport.deserializeUser((id, done) => {
        db.get('SELECT id, username, email, role, avatar FROM users WHERE id = ?', [id], (err, user) => done(err, user));
    });

    if (process.env.GOOGLE_CLIENT_ID) {
        passport.use(new GoogleStrategy({
            clientID: process.env.GOOGLE_CLIENT_ID,
            clientSecret: process.env.GOOGLE_CLIENT_SECRET,
            callbackURL: process.env.GOOGLE_CALLBACK_URL
        }, (a, r, profile, done) => processOAuth(profile, 'google', done)));
    }

    if (process.env.YANDEX_CLIENT_ID) {
        passport.use(new YandexStrategy({
            clientID: process.env.YANDEX_CLIENT_ID,
            clientSecret: process.env.YANDEX_CLIENT_SECRET,
            callbackURL: process.env.YANDEX_CALLBACK_URL
        }, (a, r, profile, done) => processOAuth(profile, 'yandex', done)));
    }
};

function processOAuth(profile, provider, done) {
    const email = profile.emails?.[0]?.value;
    const username = profile.displayName || profile.username || email?.split('@')[0];
    const avatar = profile.photos?.[0]?.value;
    
    db.get('SELECT * FROM users WHERE email = ?', [email], (err, user) => {
        if (err) return done(err);
        if (user) {
            db.run('UPDATE users SET last_login = CURRENT_TIMESTAMP, avatar = COALESCE(?, avatar) WHERE id = ?', [avatar, user.id]);
            return done(null, user);
        }
        db.run(
            'INSERT INTO users (username, email, provider, provider_id, avatar, role) VALUES (?, ?, ?, ?, ?, ?)',
            [username, email, provider, profile.id, avatar, 'user'],
            function(err) { if (err) return done(err); db.get('SELECT * FROM users WHERE id = ?', [this.lastID], done); }
        );
    });
}
EOF

# Create database init
mkdir -p backend/database
cat > backend/database/init.js <<'EOF'
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcryptjs');
const path = require('path');
const fs = require('fs');

const dbPath = process.env.DB_PATH || path.join(__dirname, '../../data/database.db');
const dataDir = path.dirname(dbPath);
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new sqlite3.Database(dbPath);

function initialize() {
    db.serialize(() => {
        db.run(`CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            email TEXT UNIQUE,
            password TEXT,
            provider TEXT,
            provider_id TEXT,
            avatar TEXT,
            role TEXT DEFAULT 'user',
            language TEXT DEFAULT 'ru',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_login DATETIME,
            is_active INTEGER DEFAULT 1
        )`);
        
        db.run(`CREATE TABLE IF NOT EXISTS devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            device_id TEXT UNIQUE NOT NULL,
            device_name TEXT,
            device_type TEXT,
            browser TEXT,
            os TEXT,
            last_ip TEXT,
            last_active DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )`);
        
        db.run(`CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            type TEXT NOT NULL,
            category TEXT,
            logo TEXT,
            status TEXT DEFAULT 'active',
            views INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )`);
        
        db.run(`CREATE TABLE IF NOT EXISTS favorites (
            user_id INTEGER,
            channel_id TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, channel_id),
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )`);
        
        db.run(`CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )`);
        
        // Admin user
        const adminEmail = process.env.ADMIN_EMAIL || 'admin@vision.tv';
        const adminPassword = process.env.ADMIN_PASSWORD || 'Admin123!';
        
        db.get('SELECT id FROM users WHERE role = ?', ['admin'], (err, row) => {
            if (!row) {
                const hash = bcrypt.hashSync(adminPassword, 10);
                db.run('INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)',
                    ['admin', adminEmail, hash, 'admin'],
                    (err) => { if (!err) console.log(`✅ Admin: ${adminEmail} / ${adminPassword}`); }
                );
            }
        });
        
        // Default settings
        const defaults = {
            'site_name': 'Vision TV',
            'allow_registration': 'true',
            'max_devices': '3',
            'max_favorites': '100',
            'scan_enabled': 'true'
        };
        
        Object.entries(defaults).forEach(([k, v]) => {
            db.run('INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)', [k, v]);
        });
    });
    
    console.log('📁 Database initialized');
}

module.exports = { initialize, db };
EOF

# Create routes
mkdir -p backend/routes

# auth.js
cat > backend/routes/auth.js <<'EOF'
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const passport = require('passport');
const router = express.Router();
const db = require('../database/init').db;
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 10 });

router.post('/register', async (req, res) => {
    const { username, email, password } = req.body;
    if (!username || !email || !password) return res.status(400).json({ error: 'All fields required' });
    
    db.get('SELECT id FROM users WHERE email = ?', [email], async (err, row) => {
        if (row) return res.status(400).json({ error: 'User exists' });
        const hash = await bcrypt.hash(password, 10);
        db.run('INSERT INTO users (username, email, password) VALUES (?, ?, ?)', [username, email, hash],
            function(err) {
                if (err) return res.status(500).json({ error: 'DB error' });
                const token = jwt.sign({ id: this.lastID, username, email, role: 'user' }, process.env.JWT_SECRET, { expiresIn: '7d' });
                res.json({ token, user: { id: this.lastID, username, email, role: 'user' } });
            }
        );
    });
});

router.post('/login', limiter, (req, res) => {
    const { email, password, deviceInfo } = req.body;
    db.get('SELECT * FROM users WHERE email = ? AND is_active = 1', [email], async (err, user) => {
        if (!user || !(await bcrypt.compare(password, user.password || ''))) return res.status(401).json({ error: 'Invalid credentials' });
        
        const checkDevice = () => {
            db.get('SELECT COUNT(*) as count FROM devices WHERE user_id = ?', [user.id], (e, r) => {
                if (r.count >= 3 && deviceInfo) {
                    db.get('SELECT id FROM devices WHERE user_id = ? AND device_id = ?', [user.id, deviceInfo.deviceId], (e, d) => {
                        if (!d) return res.status(403).json({ error: 'DEVICE_LIMIT', max: 3 });
                        finalize();
                    });
                } else finalize();
            });
        };
        
        const finalize = () => {
            db.run('UPDATE users SET last_login = CURRENT_TIMESTAMP, last_ip = ? WHERE id = ?', [req.ip, user.id]);
            if (deviceInfo) {
                db.run(`INSERT OR REPLACE INTO devices (user_id, device_id, device_name, device_type, browser, os, last_ip)
                        VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    [user.id, deviceInfo.deviceId, deviceInfo.name, deviceInfo.type, deviceInfo.browser, deviceInfo.os, req.ip]);
            }
            const token = jwt.sign({ id: user.id, username: user.username, email: user.email, role: user.role }, process.env.JWT_SECRET, { expiresIn: '7d' });
            const { password, ...userData } = user;
            res.json({ token, user: userData });
        };
        
        checkDevice();
    });
});

router.get('/google', passport.authenticate('google', { scope: ['profile', 'email'] }));
router.get('/google/callback', passport.authenticate('google', { failureRedirect: '/login' }), (req, res) => res.redirect('/'));
router.get('/yandex', passport.authenticate('yandex'));
router.get('/yandex/callback', passport.authenticate('yandex', { failureRedirect: '/login' }), (req, res) => res.redirect('/'));
router.post('/logout', (req, res) => { req.logout(() => { req.session.destroy(); res.json({ success: true }); }); });

module.exports = router;
EOF

# channels.js
cat > backend/routes/channels.js <<'EOF'
const express = require('express');
const axios = require('axios');
const router = express.Router();
const db = require('../database/init').db;

router.get('/', async (req, res) => {
    db.all('SELECT * FROM channels WHERE status = ? ORDER BY name', ['active'], async (err, channels) => {
        if (channels.length === 0) await scanChannels();
        db.all('SELECT * FROM channels WHERE status = ? ORDER BY name', ['active'], (e, c) => res.json({ channels: c }));
    });
});

async function scanChannels() {
    for (let i = process.env.SCAN_START || 1; i <= (process.env.SCAN_END || 100); i++) {
        try {
            const r = await axios.get(`${process.env.API_BASE}/${i}`, { timeout: 2000 });
            const url = r.data?.data?.[0]?.threadAddress;
            if (url?.includes('.m3u8')) {
                const name = url.match(/\/([^\/]+)\/playlist/)?.[1]?.replace(/_/g, ' ') || 'Channel';
                const type = url.toLowerCase().includes('radio') ? 'radio' : 'tv';
                db.run('INSERT OR IGNORE INTO channels (id, name, url, type) VALUES (?, ?, ?, ?)', [String(i), name, url, type]);
            }
        } catch (e) {}
        if (i % 10 === 0) await new Promise(r => setTimeout(r, 100));
    }
}

module.exports = router;
EOF

# devices.js
cat > backend/routes/devices.js <<'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const db = require('../database/init').db;

router.use((req, res, next) => {
    try { req.user = jwt.verify(req.headers.authorization?.split(' ')[1], process.env.JWT_SECRET); next(); }
    catch { res.status(401).json({ error: 'Unauthorized' }); }
});

router.get('/', (req, res) => {
    db.all('SELECT * FROM devices WHERE user_id = ? ORDER BY last_active DESC', [req.user.id], (e, d) => {
        res.json({ devices: d, maxDevices: 3 });
    });
});

router.delete('/:deviceId', (req, res) => {
    db.run('DELETE FROM devices WHERE user_id = ? AND device_id = ?', [req.user.id, req.params.deviceId], (e) => {
        res.json({ success: !e });
    });
});

module.exports = router;
EOF

# admin.js
cat > backend/routes/admin.js <<'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const db = require('../database/init').db;

router.use((req, res, next) => {
    try {
        const u = jwt.verify(req.headers.authorization?.split(' ')[1], process.env.JWT_SECRET);
        if (u.role !== 'admin') throw new Error();
        req.user = u; next();
    } catch { res.status(403).json({ error: 'Admin only' }); }
});

router.get('/stats', (req, res) => {
    db.get('SELECT COUNT(*) as users FROM users', (e, u) => {
        db.get('SELECT COUNT(*) as channels FROM channels', (e, c) => {
            res.json({ users: u.users, channels: c.channels });
        });
    });
});

router.get('/users', (req, res) => {
    db.all('SELECT id, username, email, role, created_at, last_login FROM users ORDER BY created_at DESC', (e, u) => {
        res.json({ users: u });
    });
});

router.put('/settings', (req, res) => {
    Object.entries(req.body).forEach(([k, v]) => {
        db.run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [k, v]);
    });
    res.json({ success: true });
});

module.exports = router;
EOF

# Create frontend files
print_header "🎨 СОЗДАНИЕ ФРОНТЕНДА"

# index.html (simplified - contains all core UI)
cat > frontend/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <title>Vision TV</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.plyr.io/3.7.8/plyr.css">
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <header class="header">
        <div class="logo"><i class="fas fa-play-circle"></i> Vision TV</div>
        <div class="search-bar"><i class="fas fa-search"></i><input type="text" id="searchInput" placeholder="Поиск каналов..."></div>
        <div class="header-actions">
            <div class="lang-selector">
                <button id="langBtn"><i class="fas fa-globe"></i> <span>RU</span></button>
                <div class="lang-dropdown" id="langDropdown">
                    <div data-lang="ru">🇷🇺 Русский</div><div data-lang="en">🇬🇧 English</div><div data-lang="uz">🇺🇿 O'zbek</div><div data-lang="tj">🇹🇯 Тоҷикӣ</div>
                </div>
            </div>
            <div id="authSection"></div>
        </div>
    </header>
    <aside class="sidebar" id="sidebar">
        <nav>
            <a href="/" class="nav-item active"><i class="fas fa-home"></i> <span data-i18n="home">Главная</span></a>
            <a href="#" class="nav-item" data-cat="tv"><i class="fas fa-tv"></i> <span data-i18n="tv">ТВ</span></a>
            <a href="#" class="nav-item" data-cat="radio"><i class="fas fa-radio"></i> <span data-i18n="radio">Радио</span></a>
            <a href="#" class="nav-item" data-cat="favorites"><i class="fas fa-heart"></i> <span data-i18n="favorites">Избранное</span></a>
            <hr>
            <a href="/profile.html" class="nav-item"><i class="fas fa-user"></i> <span data-i18n="profile">Профиль</span></a>
            <a href="/devices.html" class="nav-item"><i class="fas fa-mobile-alt"></i> <span data-i18n="devices">Устройства</span></a>
            <a href="/admin.html" class="nav-item admin-only" style="display:none;"><i class="fas fa-shield-alt"></i> Админ-панель</a>
        </nav>
    </aside>
    <main class="main-content">
        <section id="playerSection" class="player-section" style="display:none;">
            <video id="videoPlayer" playsinline controls></video>
            <div id="radioVisualizer" class="radio-visualizer" style="display:none;">
                <div class="radio-cover"><i class="fas fa-radio"></i></div>
                <h3 id="radioName"></h3>
                <div class="radio-controls"><button id="radioPlay"><i class="fas fa-play"></i></button></div>
            </div>
        </section>
        <section class="channels-section">
            <h2 data-i18n="all_channels">Все каналы</h2>
            <div class="channel-grid" id="channelGrid"></div>
        </section>
    </main>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js"></script>
    <script src="https://cdn.plyr.io/3.7.8/plyr.js"></script>
    <script src="/js/i18n.js"></script>
    <script src="/js/auth.js"></script>
    <script src="/js/app.js"></script>
</body>
</html>
EOF

# CSS
cat > frontend/css/style.css <<'EOF'
:root{--primary:#ff3366;--bg:#0f0f0f;--card:#1a1a1a;--text:#fff;--text-secondary:#a1a1aa}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Inter',sans-serif;background:var(--bg);color:var(--text);display:flex;min-height:100vh}
.header{position:fixed;top:0;left:0;right:0;height:70px;background:rgba(15,15,15,0.9);backdrop-filter:blur(10px);display:flex;align-items:center;padding:0 24px;z-index:100;border-bottom:1px solid #333}
.logo{font-size:24px;font-weight:700;display:flex;align-items:center;gap:10px;background:linear-gradient(135deg,var(--primary),#6366f1);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.search-bar{flex:1;max-width:400px;margin:0 20px;position:relative}
.search-bar i{position:absolute;left:16px;top:50%;transform:translateY(-50%);color:#888}
.search-bar input{width:100%;padding:12px 20px 12px 44px;background:#252525;border:none;border-radius:30px;color:#fff;font-size:15px}
.lang-selector{position:relative;margin-right:15px}
.lang-btn{background:#252525;border:none;color:#fff;padding:10px 16px;border-radius:30px;cursor:pointer;display:flex;align-items:center;gap:8px}
.lang-dropdown{position:absolute;top:45px;right:0;background:#252525;border-radius:12px;padding:8px;display:none;min-width:150px}
.lang-dropdown.active{display:block}
.lang-dropdown div{padding:10px;cursor:pointer;border-radius:8px}
.lang-dropdown div:hover{background:#333}
.sidebar{position:fixed;left:0;top:70px;bottom:0;width:260px;background:#111;padding:20px;overflow-y:auto}
.nav-item{display:flex;align-items:center;gap:15px;padding:12px 16px;color:#aaa;text-decoration:none;border-radius:12px;margin-bottom:4px;transition:all 0.2s}
.nav-item:hover,.nav-item.active{background:#252525;color:#fff}
.nav-item i{width:24px}
.main-content{margin-left:260px;margin-top:70px;padding:30px;flex:1}
.channel-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:20px;margin-top:20px}
.channel-card{background:var(--card);border-radius:16px;padding:20px;cursor:pointer;transition:all 0.2s;border:1px solid #333}
.channel-card:hover{transform:translateY(-4px);border-color:var(--primary)}
.channel-logo{width:70px;height:70px;background:#252525;border-radius:16px;display:flex;align-items:center;justify-content:center;font-size:28px;margin-bottom:15px}
.btn-primary{background:linear-gradient(135deg,var(--primary),#e61e4d);color:#fff;border:none;padding:10px 20px;border-radius:30px;font-weight:600;cursor:pointer}
.btn-outline{background:transparent;border:1px solid #444;color:#fff;padding:10px 20px;border-radius:30px;cursor:pointer}
.player-section{margin-bottom:30px;background:#000;border-radius:20px;overflow:hidden}
#videoPlayer{width:100%;max-height:500px}
.radio-visualizer{padding:60px;text-align:center;background:linear-gradient(135deg,#1a1a2e,#16213e)}
.radio-cover{width:120px;height:120px;margin:0 auto 20px;background:linear-gradient(135deg,var(--primary),#6366f1);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:48px;animation:pulse 3s infinite}
@keyframes pulse{0%,100%{transform:scale(1)}50%{transform:scale(1.05)}}
.device-item{background:#1a1a1a;border-radius:16px;padding:20px;margin-bottom:15px;display:flex;justify-content:space-between;align-items:center}
.toast{position:fixed;bottom:20px;right:20px;background:#333;color:#fff;padding:16px 24px;border-radius:12px;border-left:4px solid var(--primary);animation:slideIn 0.3s}
@keyframes slideIn{from{opacity:0;transform:translateX(50px)}}
EOF

# JavaScript files
cat > frontend/js/auth.js <<'EOF'
class Auth{constructor(){this.token=localStorage.getItem('token');this.user=JSON.parse(localStorage.getItem('user')||'null');this.deviceId=localStorage.getItem('deviceId')||this.generateId();localStorage.setItem('deviceId',this.deviceId);this.updateUI()}
generateId(){return'dev_'+Date.now()+'_'+Math.random().toString(36)}
isAuth(){return!!this.token}
isAdmin(){return this.user?.role==='admin'}
async login(e,p){const r=await fetch('/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:e,password:p,deviceInfo:{deviceId:this.deviceId,name:navigator.userAgent}})});const d=await r.json();if(!r.ok)throw new Error(d.error);this.setSession(d);return d}
async register(u,e,p){const r=await fetch('/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:u,email:e,password:p})});const d=await r.json();if(!r.ok)throw new Error(d.error);this.setSession(d);return d}
setSession(d){this.token=d.token;this.user=d.user;localStorage.setItem('token',d.token);localStorage.setItem('user',JSON.stringify(d.user));this.updateUI()}
logout(){localStorage.removeItem('token');localStorage.removeItem('user');window.location.href='/'}
updateUI(){const a=document.getElementById('authSection');if(!a)return;if(this.isAuth()){a.innerHTML=`<div class="user-menu"><span>${this.user.username}</span><div class="dropdown"><a href="/profile">Профиль</a><a href="/devices">Устройства</a><a href="#" onclick="auth.logout()">Выйти</a></div></div>`;if(this.isAdmin())document.querySelector('.admin-only').style.display='flex'}else{a.innerHTML=`<a href="/login" class="btn-outline">Войти</a><a href="/register" class="btn-primary">Регистрация</a>`}}
getHeaders(){return{'Authorization':`Bearer ${this.token}`}}}
const auth=new Auth();
EOF

cat > frontend/js/i18n.js <<'EOF'
class I18n{constructor(){this.lang=localStorage.getItem('lang')||'ru';this.data={}}
async init(){await this.load();this.update()}
async load(){try{const r=await fetch(`/api/locales/${this.lang}`);this.data=await r.json()}catch(e){}}
async setLang(l){this.lang=l;localStorage.setItem('lang',l);await this.load();this.update()}
t(k){return this.data[k]||k}
update(){document.querySelectorAll('[data-i18n]').forEach(e=>e.textContent=this.t(e.dataset.i18n));document.querySelector('#langBtn span').textContent=this.lang.toUpperCase()}}
const i18n=new I18n();document.addEventListener('DOMContentLoaded',()=>i18n.init());
EOF

cat > frontend/js/app.js <<'EOF'
let hls=null,channels=[],current=null;const player=document.getElementById('videoPlayer');const plyr=new Plyr(player);
async function load(){const r=await fetch('/api/channels');const d=await r.json();channels=d.channels;render()}
function render(){const g=document.getElementById('channelGrid');g.innerHTML=channels.map(c=>`<div class="channel-card" onclick="play('${c.id}')"><div class="channel-logo">${c.type==='tv'?'📺':'📻'}</div><div class="channel-name">${c.name}</div><span>${c.type}</span></div>`).join('')}
function play(id){const c=channels.find(c=>c.id===id);if(!c)return;current=c;document.getElementById('playerSection').style.display='block';
if(hls)hls.destroy();
if(c.type==='radio'){player.style.display='none';document.getElementById('radioVisualizer').style.display='block';document.getElementById('radioName').textContent=c.name;const a=new Audio(c.url);a.play();document.getElementById('radioPlay').onclick=()=>a.paused?a.play():a.pause()}
else{player.style.display='block';document.getElementById('radioVisualizer').style.display='none';if(Hls.isSupported()){hls=new Hls();hls.loadSource(c.url);hls.attachMedia(player)}else player.src=c.url;plyr.play()}
document.getElementById('playerSection').scrollIntoView({behavior:'smooth'})}
document.getElementById('searchInput').addEventListener('input',e=>{const f=channels.filter(c=>c.name.toLowerCase().includes(e.target.value.toLowerCase()));document.getElementById('channelGrid').innerHTML=f.map(c=>`<div class="channel-card" onclick="play('${c.id}')"><div class="channel-logo">${c.type==='tv'?'📺':'📻'}</div><div class="channel-name">${c.name}</div></div>`).join('')});
load();
EOF

# Create locale files
mkdir -p frontend/locales
echo '{"home":"Главная","tv":"ТВ Каналы","radio":"Радио","favorites":"Избранное","profile":"Профиль","devices":"Устройства","all_channels":"Все каналы"}' > frontend/locales/ru.json
echo '{"home":"Home","tv":"TV Channels","radio":"Radio","favorites":"Favorites","profile":"Profile","devices":"Devices","all_channels":"All Channels"}' > frontend/locales/en.json
echo '{"home":"Bosh sahifa","tv":"TV Kanallar","radio":"Radio","favorites":"Sevimlilar","profile":"Profil","devices":"Qurilmalar","all_channels":"Barcha kanallar"}' > frontend/locales/uz.json
echo '{"home":"Асосӣ","tv":"ТВ Каналҳо","radio":"Радио","favorites":"Интихобшуда","profile":"Профил","devices":"Дастгоҳҳо","all_channels":"Ҳамаи каналҳо"}' > frontend/locales/tj.json

# Install Node dependencies
print_header "📦 УСТАНОВКА NODE.JS ЗАВИСИМОСТЕЙ"
cd $INSTALL_DIR
npm install --legacy-peer-deps

# Initialize database
print_info "Инициализация базы данных..."
node -e "require('./backend/database/init').initialize()"

# Setup Nginx
print_header "⚙️ НАСТРОЙКА NGINX"
cat > /etc/nginx/sites-available/vision-tv <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://localhost:$SERVER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /socket.io/ {
        proxy_pass http://localhost:$SERVER_PORT/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

ln -sf /etc/nginx/sites-available/vision-tv /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# SSL Certificate
print_header "🔒 НАСТРОЙКА SSL"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL || print_warning "SSL не настроен (проверьте домен)"

# Start application
print_header "🚀 ЗАПУСК ПРИЛОЖЕНИЯ"
pm2 start server.js --name vision-tv
pm2 save
pm2 startup systemd 2>/dev/null || true

# Final output
clear
print_header "╔═══════════════════════════════════════════════════════════════╗"
print_header "║                                                               ║"
print_header "║                    🎉 УСТАНОВКА ЗАВЕРШЕНА! 🎉                  ║"
print_header "║                                                               ║"
print_header "╚═══════════════════════════════════════════════════════════════╝"
echo ""
print_success "Vision TV успешно установлен!"
echo ""
print_info "🌐 Сайт: https://$DOMAIN"
print_info "🛠 Админ-панель: https://$DOMAIN/admin.html"
echo ""
print_info "👤 ДАННЫЕ АДМИНИСТРАТОРА:"
echo "   📧 Email: admin@$DOMAIN"
echo "   🔑 Пароль: $ADMIN_PASSWORD"
echo ""
print_info "🔧 OAuth CALLBACK URL (для настройки приложений):"
echo "   Яндекс: https://$DOMAIN/api/auth/yandex/callback"
echo "   Google: https://$DOMAIN/api/auth/google/callback"
echo ""
print_info "📁 Файлы проекта: $INSTALL_DIR"
print_info "💾 Данные сохранены: $INSTALL_DIR/admin_credentials.txt"
echo ""
print_info "🖥️ КОМАНДЫ УПРАВЛЕНИЯ:"
echo "   pm2 status              - Статус"
echo "   pm2 logs vision-tv      - Логи"
echo "   pm2 restart vision-tv   - Перезапуск"
echo ""

# Save credentials
echo "=== Vision TV Admin Credentials ===" > $INSTALL_DIR/admin_credentials.txt
echo "Site: https://$DOMAIN" >> $INSTALL_DIR/admin_credentials.txt
echo "Admin Email: admin@$DOMAIN" >> $INSTALL_DIR/admin_credentials.txt
echo "Admin Password: $ADMIN_PASSWORD" >> $INSTALL_DIR/admin_credentials.txt
echo "Yandex Callback: https://$DOMAIN/api/auth/yandex/callback" >> $INSTALL_DIR/admin_credentials.txt
echo "Google Callback: https://$DOMAIN/api/auth/google/callback" >> $INSTALL_DIR/admin_credentials.txt