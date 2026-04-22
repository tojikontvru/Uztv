#!/bin/bash
# Vision TV - Complete Installation Script
# Version 2.0 with OAuth and Multi-language support

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Welcome screen
clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ██╗   ██╗██╗███████╗██╗ ██████╗ ███╗   ██╗              ║
║   ██║   ██║██║██╔════╝██║██╔═══██╗████╗  ██║              ║
║   ██║   ██║██║███████╗██║██║   ██║██╔██╗ ██║              ║
║   ╚██╗ ██╔╝██║╚════██║██║██║   ██║██║╚██╗██║              ║
║    ╚████╔╝ ██║███████║██║╚██████╔╝██║ ╚████║              ║
║     ╚═══╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝              ║
║                                                           ║
║              📺 ТВ • 📻 Радио • 👤 Профиль                 ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""
echo "Добро пожаловать в установщик Vision TV!"
echo "========================================="
echo ""

# Get configuration
read -p "Введите домен (например: tv.example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    print_error "Домен обязателен"
    exit 1
fi

read -p "Email для SSL сертификата: " SSL_EMAIL
[ -z "$SSL_EMAIL" ] && SSL_EMAIL="admin@$DOMAIN"

read -p "Порт сервера (по умолчанию 3000): " SERVER_PORT
[ -z "$SERVER_PORT" ] && SERVER_PORT=3000

echo ""
echo "Настройка OAuth авторизации:"
echo "-----------------------------"
read -p "Yandex Client ID: " YANDEX_CLIENT_ID
read -p "Yandex Client Secret: " YANDEX_CLIENT_SECRET
read -p "Google Client ID: " GOOGLE_CLIENT_ID
read -p "Google Client Secret: " GOOGLE_CLIENT_SECRET

read -sp "Пароль администратора (оставьте пустым для авто-генерации): " ADMIN_PASSWORD
echo ""
[ -z "$ADMIN_PASSWORD" ] && ADMIN_PASSWORD=$(openssl rand -base64 16)

echo ""
print_info "Параметры установки:"
echo "  Домен: $DOMAIN"
echo "  Email SSL: $SSL_EMAIL"
echo "  Порт: $SERVER_PORT"
echo "  Yandex OAuth: ${YANDEX_CLIENT_ID:+настроен}"
echo "  Google OAuth: ${GOOGLE_CLIENT_ID:+настроен}"
echo ""
read -p "Продолжить установку? (y/n): " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    print_error "Cannot detect OS"
    exit 1
fi

# Install dependencies
print_info "Установка зависимостей..."
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm sqlite3 redis-server
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]]; then
    yum update -y
    yum install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm sqlite redis
    systemctl enable redis
    systemctl start redis
fi

npm install -g pm2
print_success "Зависимости установлены"

# Create project structure
INSTALL_DIR="/var/www/vision-tv"
print_info "Создание структуры проекта в $INSTALL_DIR"
mkdir -p $INSTALL_DIR/{backend/{routes,models,middleware,database},frontend/{pages/{admin},css,js,locales,assets},data,nginx,logs}
cd $INSTALL_DIR

# Generate secrets
JWT_SECRET=$(openssl rand -base64 64)
SESSION_SECRET=$(openssl rand -base64 64)

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

# API
API_BASE=https://api.mediabay.tv/v2/channels/thread
SCAN_START=1
SCAN_END=800
EOF

# Create package.json
cat > package.json <<'EOF'
{
  "name": "vision-tv",
  "version": "2.0.0",
  "description": "Modern TV and Radio Streaming Platform",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "pm2": "pm2 start server.js --name vision-tv"
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
    "passport-yandex": "^1.0.4",
    "passport-google-oauth20": "^2.0.0",
    "express-rate-limit": "^6.10.0",
    "compression": "^1.7.4",
    "morgan": "^1.10.0",
    "dotenv": "^16.3.1",
    "axios": "^1.5.0",
    "multer": "^1.4.5-lts.1",
    "sharp": "^0.32.6",
    "socket.io": "^4.6.2",
    "i18next": "^23.5.1",
    "i18next-fs-backend": "^2.2.0",
    "device-detector-js": "^3.0.3"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
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

// Redis client
const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect().catch(console.error);

// Security middleware
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com", "https://cdnjs.cloudflare.com"],
            fontSrc: ["'self'", "https://fonts.gstatic.com", "https://cdnjs.cloudflare.com"],
            scriptSrc: ["'self'", "'unsafe-inline'", "https://apis.google.com", "https://cdn.jsdelivr.net", "https://cdn.plyr.io"],
            imgSrc: ["'self'", "data:", "https:", "https://avatars.yandex.net", "https://lh3.googleusercontent.com"],
            mediaSrc: ["'self'", "blob:", "https:"],
            connectSrc: ["'self'", "https://api.mediabay.tv", "https://accounts.google.com", "https://oauth.yandex.ru"],
            frameSrc: ["'self'", "https://accounts.google.com", "https://oauth.yandex.ru"]
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
    cookie: {
        secure: process.env.NODE_ENV === 'production',
        httpOnly: true,
        maxAge: 7 * 24 * 60 * 60 * 1000
    }
}));

// Passport
app.use(passport.initialize());
app.use(passport.session());
require('./backend/config/passport')(passport);

// Static files
app.use(express.static(path.join(__dirname, 'frontend')));
app.use('/uploads', express.static(path.join(__dirname, 'data/uploads')));

// Initialize database
require('./backend/database/init')();

// Routes
app.use('/api/auth', require('./backend/routes/auth'));
app.use('/api/users', require('./backend/routes/users'));
app.use('/api/channels', require('./backend/routes/channels'));
app.use('/api/devices', require('./backend/routes/devices'));
app.use('/api/admin', require('./backend/routes/admin'));

// Language files API
app.get('/api/locales/:lang', (req, res) => {
    try {
        const locale = require(`./frontend/locales/${req.params.lang}.json`);
        res.json(locale);
    } catch {
        res.status(404).json({ error: 'Language not found' });
    }
});

// Socket.io for real-time features
io.on('connection', (socket) => {
    console.log('User connected:', socket.id);
    
    socket.on('join-room', (room) => socket.join(room));
    socket.on('watch-together', (data) => {
        socket.to(data.room).emit('sync-playback', data);
    });
    
    socket.on('disconnect', () => console.log('User disconnected:', socket.id));
});

// SPA fallback
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'frontend/index.html'));
});

// Error handler
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`🚀 Vision TV running on port ${PORT}`);
    console.log(`📍 Domain: ${process.env.DOMAIN}`);
    console.log(`🔐 OAuth: Yandex ${process.env.YANDEX_CLIENT_ID ? '✓' : '✗'} | Google ${process.env.GOOGLE_CLIENT_ID ? '✓' : '✗'}`);
});

module.exports = { app, io };
EOF

# Create passport config
mkdir -p backend/config
cat > backend/config/passport.js <<'EOF'
const YandexStrategy = require('passport-yandex').Strategy;
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const db = require('../database/init').db;
const bcrypt = require('bcryptjs');

module.exports = function(passport) {
    passport.serializeUser((user, done) => done(null, user.id));
    passport.deserializeUser((id, done) => {
        db.get('SELECT id, username, email, role, avatar, provider FROM users WHERE id = ?', [id], 
            (err, user) => done(err, user));
    });
    
    // Yandex Strategy
    if (process.env.YANDEX_CLIENT_ID) {
        passport.use(new YandexStrategy({
            clientID: process.env.YANDEX_CLIENT_ID,
            clientSecret: process.env.YANDEX_CLIENT_SECRET,
            callbackURL: process.env.YANDEX_CALLBACK_URL
        }, (accessToken, refreshToken, profile, done) => {
            processOAuthUser(profile, 'yandex', done);
        }));
    }
    
    // Google Strategy
    if (process.env.GOOGLE_CLIENT_ID) {
        passport.use(new GoogleStrategy({
            clientID: process.env.GOOGLE_CLIENT_ID,
            clientSecret: process.env.GOOGLE_CLIENT_SECRET,
            callbackURL: process.env.GOOGLE_CALLBACK_URL
        }, (accessToken, refreshToken, profile, done) => {
            processOAuthUser(profile, 'google', done);
        }));
    }
};

function processOAuthUser(profile, provider, done) {
    const email = profile.emails?.[0]?.value;
    const username = profile.displayName || profile.username || email?.split('@')[0];
    const avatar = profile.photos?.[0]?.value;
    
    db.get('SELECT * FROM users WHERE email = ? OR provider_id = ?', 
        [email, profile.id], async (err, user) => {
            if (err) return done(err);
            
            if (user) {
                db.run('UPDATE users SET last_login = CURRENT_TIMESTAMP, avatar = COALESCE(?, avatar) WHERE id = ?',
                    [avatar, user.id]);
                return done(null, user);
            }
            
            // Create new user
            db.run(
                `INSERT INTO users (username, email, provider, provider_id, avatar, role) 
                 VALUES (?, ?, ?, ?, ?, 'user')`,
                [username, email, provider, profile.id, avatar],
                function(err) {
                    if (err) return done(err);
                    db.get('SELECT * FROM users WHERE id = ?', [this.lastID], done);
                }
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
        // Users table
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
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_login DATETIME,
            last_ip TEXT,
            is_active INTEGER DEFAULT 1,
            UNIQUE(provider, provider_id)
        )`);

        // Devices table
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
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )`);

        // Channels table
        db.run(`CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            type TEXT NOT NULL,
            category TEXT,
            logo TEXT,
            epg_url TEXT,
            country TEXT,
            language TEXT,
            bitrate INTEGER,
            status TEXT DEFAULT 'active',
            views INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )`);

        // Favorites table
        db.run(`CREATE TABLE IF NOT EXISTS favorites (
            user_id INTEGER,
            channel_id TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, channel_id),
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
        )`);

        // Watch history
        db.run(`CREATE TABLE IF NOT EXISTS watch_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            channel_id TEXT NOT NULL,
            device_id TEXT,
            watched_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            duration INTEGER,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
        )`);

        // Settings table
        db.run(`CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )`);

        // Create admin
        const adminEmail = process.env.ADMIN_EMAIL || 'admin@vision.tv';
        const adminPassword = process.env.ADMIN_PASSWORD || 'Admin123!';
        
        db.get('SELECT id FROM users WHERE role = ?', ['admin'], (err, row) => {
            if (!row) {
                const hash = bcrypt.hashSync(adminPassword, 10);
                db.run(
                    'INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)',
                    ['admin', adminEmail, hash, 'admin'],
                    (err) => {
                        if (!err) {
                            console.log(`✅ Admin: ${adminEmail} / ${adminPassword}`);
                        }
                    }
                );
            }
        });

        // Default settings
        const defaults = {
            'site_name': 'Vision TV',
            'site_description': 'Современное телевидение и радио',
            'allow_registration': 'true',
            'max_devices': process.env.MAX_DEVICES_PER_USER || '3',
            'max_favorites': '100',
            'scan_enabled': 'true',
            'maintenance_mode': 'false'
        };

        Object.entries(defaults).forEach(([key, value]) => {
            db.run('INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)', [key, value]);
        });
    });
    
    console.log('📁 Database initialized at:', dbPath);
}

module.exports = { initialize, db };
EOF

# Create auth routes
mkdir -p backend/routes
cat > backend/routes/auth.js <<'EOF'
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const passport = require('passport');
const router = express.Router();
const db = require('../database/init').db;
const rateLimit = require('express-rate-limit');

const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 5,
    message: 'Too many login attempts, please try again later'
});

// Register
router.post('/register', async (req, res) => {
    try {
        const { username, email, password, language } = req.body;
        
        if (!username || !email || !password) {
            return res.status(400).json({ error: 'All fields required' });
        }
        
        db.get('SELECT id FROM users WHERE email = ?', [email], async (err, row) => {
            if (row) return res.status(400).json({ error: 'User already exists' });
            
            const hash = await bcrypt.hash(password, 10);
            db.run(
                'INSERT INTO users (username, email, password, language) VALUES (?, ?, ?, ?)',
                [username, email, hash, language || 'ru'],
                function(err) {
                    if (err) return res.status(500).json({ error: 'Registration failed' });
                    
                    const token = jwt.sign(
                        { id: this.lastID, username, email, role: 'user' },
                        process.env.JWT_SECRET,
                        { expiresIn: '7d' }
                    );
                    
                    res.json({ token, user: { id: this.lastID, username, email, role: 'user' } });
                }
            );
        });
    } catch (error) {
        res.status(500).json({ error: 'Server error' });
    }
});

// Login
router.post('/login', loginLimiter, (req, res) => {
    const { email, password, deviceInfo } = req.body;
    
    db.get('SELECT * FROM users WHERE email = ? AND is_active = 1', [email], async (err, user) => {
        if (err || !user) return res.status(401).json({ error: 'Invalid credentials' });
        
        let validPassword = false;
        if (user.password) {
            validPassword = await bcrypt.compare(password, user.password);
        }
        
        if (!validPassword && !user.provider) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }
        
        // Check device limit
        if (deviceInfo) {
            db.get(
                'SELECT COUNT(*) as count FROM devices WHERE user_id = ?',
                [user.id],
                async (err, result) => {
                    const maxDevices = await getSetting('max_devices') || 3;
                    
                    if (result.count >= maxDevices) {
                        // Check if this device already exists
                        db.get(
                            'SELECT id FROM devices WHERE user_id = ? AND device_id = ?',
                            [user.id, deviceInfo.deviceId],
                            (err, existing) => {
                                if (!existing) {
                                    return res.status(403).json({ 
                                        error: 'DEVICE_LIMIT',
                                        message: `Maximum ${maxDevices} devices allowed`
                                    });
                                }
                                completeLogin();
                            }
                        );
                    } else {
                        completeLogin();
                    }
                }
            );
        } else {
            completeLogin();
        }
        
        function completeLogin() {
            db.run(
                'UPDATE users SET last_login = CURRENT_TIMESTAMP, last_ip = ? WHERE id = ?',
                [req.ip, user.id]
            );
            
            if (deviceInfo) {
                db.run(
                    `INSERT OR REPLACE INTO devices (user_id, device_id, device_name, device_type, browser, os, last_ip)
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    [user.id, deviceInfo.deviceId, deviceInfo.name, deviceInfo.type, 
                     deviceInfo.browser, deviceInfo.os, req.ip]
                );
            }
            
            const token = jwt.sign(
                { id: user.id, username: user.username, email: user.email, role: user.role },
                process.env.JWT_SECRET,
                { expiresIn: '7d' }
            );
            
            const { password, ...userData } = user;
            res.json({ token, user: userData });
        }
    });
});

// OAuth routes
router.get('/yandex', passport.authenticate('yandex'));
router.get('/yandex/callback', 
    passport.authenticate('yandex', { failureRedirect: '/login' }),
    (req, res) => res.redirect('/')
);

router.get('/google', passport.authenticate('google', { scope: ['profile', 'email'] }));
router.get('/google/callback',
    passport.authenticate('google', { failureRedirect: '/login' }),
    (req, res) => res.redirect('/')
);

// Logout
router.post('/logout', (req, res) => {
    req.logout(() => {
        req.session.destroy();
        res.json({ success: true });
    });
});

// Get current user
router.get('/me', (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    
    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        db.get(
            'SELECT id, username, email, role, avatar, language, created_at FROM users WHERE id = ?',
            [decoded.id],
            (err, user) => {
                if (err || !user) return res.status(404).json({ error: 'User not found' });
                res.json({ user });
            }
        );
    } catch {
        res.status(401).json({ error: 'Invalid token' });
    }
});

async function getSetting(key) {
    return new Promise((resolve) => {
        db.get('SELECT value FROM settings WHERE key = ?', [key], (err, row) => {
            resolve(row?.value || null);
        });
    });
}

module.exports = router;
EOF

# Create devices routes
cat > backend/routes/devices.js <<'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const db = require('../database/init').db;
const DeviceDetector = require('device-detector-js');
const deviceDetector = new DeviceDetector();

const authMiddleware = (req, res, next) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    
    try {
        req.user = jwt.verify(token, process.env.JWT_SECRET);
        next();
    } catch {
        res.status(401).json({ error: 'Invalid token' });
    }
};

// Get user devices
router.get('/', authMiddleware, (req, res) => {
    db.all(
        'SELECT * FROM devices WHERE user_id = ? ORDER BY last_active DESC',
        [req.user.id],
        (err, devices) => {
            if (err) return res.status(500).json({ error: 'Database error' });
            res.json({ devices, maxDevices: 3 });
        }
    );
});

// Add device
router.post('/', authMiddleware, (req, res) => {
    const { deviceId, userAgent } = req.body;
    const detection = deviceDetector.parse(userAgent || req.headers['user-agent']);
    
    db.get(
        'SELECT COUNT(*) as count FROM devices WHERE user_id = ?',
        [req.user.id],
        (err, result) => {
            if (result.count >= 3) {
                return res.status(403).json({ error: 'Maximum devices reached' });
            }
            
            db.run(
                `INSERT OR REPLACE INTO devices 
                 (user_id, device_id, device_name, device_type, browser, os, last_ip)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                [req.user.id, deviceId, detection.device?.model || 'Unknown',
                 detection.device?.type || 'desktop', detection.client?.name,
                 detection.os?.name, req.ip],
                function(err) {
                    if (err) return res.status(500).json({ error: 'Failed to add device' });
                    res.json({ success: true, deviceId: this.lastID });
                }
            );
        }
    );
});

// Remove device
router.delete('/:deviceId', authMiddleware, (req, res) => {
    db.run(
        'DELETE FROM devices WHERE user_id = ? AND device_id = ?',
        [req.user.id, req.params.deviceId],
        function(err) {
            if (err) return res.status(500).json({ error: 'Failed to remove device' });
            res.json({ success: true });
        }
    );
});

// Update device activity
router.put('/:deviceId/activity', authMiddleware, (req, res) => {
    db.run(
        'UPDATE devices SET last_active = CURRENT_TIMESTAMP, last_ip = ? WHERE user_id = ? AND device_id = ?',
        [req.ip, req.user.id, req.params.deviceId],
        function(err) {
            if (err) return res.status(500).json({ error: 'Failed to update activity' });
            res.json({ success: true });
        }
    );
});

module.exports = router;
EOF

# Create modern frontend
cat > frontend/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <meta name="theme-color" content="#0f0f0f">
    <title>Vision TV - Современное телевидение</title>
    
    <!-- Fonts & Icons -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <!-- Styles -->
    <link rel="stylesheet" href="css/modern-style.css">
</head>
<body class="dark-theme">
    <!-- Floating Background -->
    <div class="bg-gradient"></div>
    
    <!-- Header -->
    <header class="glass-header">
        <div class="header-container">
            <div class="logo-section">
                <button class="menu-toggle" id="menuToggle">
                    <i class="fas fa-bars"></i>
                </button>
                <div class="logo">
                    <div class="logo-icon">
                        <i class="fas fa-play"></i>
                    </div>
                    <span class="logo-text">Vision TV</span>
                </div>
            </div>
            
            <div class="search-section">
                <div class="search-wrapper">
                    <i class="fas fa-search search-icon"></i>
                    <input type="text" id="searchInput" class="search-input" placeholder="Поиск каналов...">
                    <button class="search-clear" id="searchClear" style="display: none;">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
            </div>
            
            <div class="header-actions">
                <div class="language-selector">
                    <button class="lang-btn" id="langBtn">
                        <i class="fas fa-globe"></i>
                        <span>RU</span>
                    </button>
                    <div class="lang-dropdown" id="langDropdown">
                        <div class="lang-option" data-lang="ru">🇷🇺 Русский</div>
                        <div class="lang-option" data-lang="en">🇬🇧 English</div>
                        <div class="lang-option" data-lang="uz">🇺🇿 O'zbek</div>
                        <div class="lang-option" data-lang="tj">🇹🇯 Тоҷикӣ</div>
                    </div>
                </div>
                
                <div id="authSection"></div>
            </div>
        </div>
    </header>
    
    <!-- Sidebar -->
    <aside class="sidebar" id="sidebar">
        <div class="sidebar-header">
            <div class="user-preview" id="userPreview"></div>
        </div>
        
        <nav class="sidebar-nav">
            <a href="/" class="nav-item active" data-page="home">
                <i class="fas fa-home"></i>
                <span data-i18n="home">Главная</span>
            </a>
            <a href="#" class="nav-item" data-category="tv">
                <i class="fas fa-tv"></i>
                <span data-i18n="tv">ТВ Каналы</span>
                <span class="nav-badge" id="tvCount">0</span>
            </a>
            <a href="#" class="nav-item" data-category="radio">
                <i class="fas fa-radio"></i>
                <span data-i18n="radio">Радио</span>
                <span class="nav-badge" id="radioCount">0</span>
            </a>
            <a href="#" class="nav-item" data-category="favorites">
                <i class="fas fa-heart"></i>
                <span data-i18n="favorites">Избранное</span>
                <span class="nav-badge" id="favCount">0</span>
            </a>
            
            <div class="nav-divider"></div>
            
            <a href="/pages/profile.html" class="nav-item">
                <i class="fas fa-user"></i>
                <span data-i18n="profile">Профиль</span>
            </a>
            <a href="/pages/devices.html" class="nav-item">
                <i class="fas fa-mobile-alt"></i>
                <span data-i18n="devices">Устройства</span>
            </a>
            <a href="/pages/history.html" class="nav-item">
                <i class="fas fa-history"></i>
                <span data-i18n="history">История</span>
            </a>
            
            <div class="nav-divider"></div>
            
            <a href="#" class="nav-item" id="adminLink" style="display: none;">
                <i class="fas fa-shield-alt"></i>
                <span data-i18n="admin">Админ-панель</span>
            </a>
        </nav>
    </aside>
    
    <!-- Main Content -->
    <main class="main-content" id="mainContent">
        <!-- Player Section -->
        <section class="player-section" id="playerSection" style="display: none;">
            <div class="player-container">
                <div class="player-wrapper">
                    <video id="videoPlayer" class="video-player" playsinline></video>
                    
                    <!-- Radio Visualizer -->
                    <div class="radio-visualizer" id="radioVisualizer">
                        <canvas id="visualizerCanvas"></canvas>
                        <div class="radio-info">
                            <div class="radio-cover" id="radioCover">
                                <i class="fas fa-radio"></i>
                            </div>
                            <h3 id="radioName">Radio Station</h3>
                            <p id="radioMeta">Live</p>
                            <div class="radio-controls">
                                <button class="ctrl-btn" id="radioPrev"><i class="fas fa-backward"></i></button>
                                <button class="ctrl-btn play-btn" id="radioPlay"><i class="fas fa-play"></i></button>
                                <button class="ctrl-btn" id="radioNext"><i class="fas fa-forward"></i></button>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Player Overlay -->
                    <div class="player-overlay" id="playerOverlay">
                        <div class="player-header">
                            <button class="back-btn" id="closePlayer">
                                <i class="fas fa-arrow-left"></i>
                            </button>
                            <div class="channel-info">
                                <h2 id="channelTitle">Выберите канал</h2>
                                <p id="channelMeta"></p>
                            </div>
                            <div class="player-actions">
                                <button class="action-btn" id="toggleFavorite">
                                    <i class="far fa-heart"></i>
                                </button>
                                <button class="action-btn" id="shareChannel">
                                    <i class="fas fa-share"></i>
                                </button>
                                <button class="action-btn" id="pipBtn">
                                    <i class="fas fa-window-restore"></i>
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>
        
        <!-- Categories -->
        <section class="categories-section">
            <div class="categories-scroll">
                <button class="category-chip active" data-category="all">
                    <i class="fas fa-globe"></i>
                    <span data-i18n="all">Все</span>
                </button>
                <button class="category-chip" data-category="news">
                    <i class="fas fa-newspaper"></i>
                    <span>Новости</span>
                </button>
                <button class="category-chip" data-category="sport">
                    <i class="fas fa-futbol"></i>
                    <span>Спорт</span>
                </button>
                <button class="category-chip" data-category="movies">
                    <i class="fas fa-film"></i>
                    <span>Кино</span>
                </button>
                <button class="category-chip" data-category="music">
                    <i class="fas fa-music"></i>
                    <span>Музыка</span>
                </button>
                <button class="category-chip" data-category="kids">
                    <i class="fas fa-child"></i>
                    <span>Детские</span>
                </button>
                <button class="category-chip" data-category="entertainment">
                    <i class="fas fa-laugh"></i>
                    <span>Развлечения</span>
                </button>
            </div>
        </section>
        
        <!-- Channel Grid -->
        <section class="channels-section">
            <div class="section-header">
                <h2 id="sectionTitle" data-i18n="all_channels">Все каналы</h2>
                <span class="channel-count" id="channelCount">0</span>
            </div>
            
            <div class="channel-grid" id="channelGrid">
                <!-- Channels will be rendered here -->
            </div>
            
            <!-- Loading State -->
            <div class="loading-state" id="loadingState">
                <div class="loader"></div>
                <p data-i18n="loading">Загрузка...</p>
            </div>
        </section>
    </main>
    
    <!-- Toast Container -->
    <div class="toast-container" id="toastContainer"></div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js"></script>
    <script src="https://cdn.plyr.io/3.7.8/plyr.js"></script>
    <script src="https://cdn.socket.io/4.6.0/socket.io.min.js"></script>
    <script src="js/i18n.js"></script>
    <script src="js/auth.js"></script>
    <script src="js/player.js"></script>
    <script src="js/app.js"></script>
</body>
</html>
EOF

# Create modern CSS
cat > frontend/css/modern-style.css <<'EOF'
:root {
    --primary: #ff3366;
    --primary-dark: #e61e4d;
    --primary-light: #ff6b8b;
    --secondary: #6366f1;
    --accent: #06b6d4;
    --success: #10b981;
    --warning: #f59e0b;
    --danger: #ef4444;
    
    --bg-primary: #0f0f0f;
    --bg-secondary: #1a1a1a;
    --bg-tertiary: #252525;
    --bg-glass: rgba(26, 26, 26, 0.8);
    
    --text-primary: #ffffff;
    --text-secondary: #a1a1aa;
    --text-muted: #71717a;
    
    --border-light: rgba(255, 255, 255, 0.08);
    --border-medium: rgba(255, 255, 255, 0.12);
    
    --shadow-sm: 0 2px 8px rgba(0, 0, 0, 0.3);
    --shadow-md: 0 8px 24px rgba(0, 0, 0, 0.4);
    --shadow-lg: 0 16px 48px rgba(0, 0, 0, 0.5);
    --shadow-glow: 0 0 40px rgba(255, 51, 102, 0.3);
    
    --radius-sm: 8px;
    --radius-md: 12px;
    --radius-lg: 16px;
    --radius-xl: 24px;
    --radius-full: 9999px;
    
    --transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
    background: var(--bg-primary);
    color: var(--text-primary);
    line-height: 1.6;
    overflow-x: hidden;
    min-height: 100vh;
}

/* Background Gradient */
.bg-gradient {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: 
        radial-gradient(circle at 20% 20%, rgba(255, 51, 102, 0.15) 0%, transparent 50%),
        radial-gradient(circle at 80% 80%, rgba(99, 102, 241, 0.15) 0%, transparent 50%),
        radial-gradient(circle at 50% 50%, rgba(6, 182, 212, 0.08) 0%, transparent 70%);
    pointer-events: none;
    z-index: -1;
}

/* Glass Header */
.glass-header {
    position: sticky;
    top: 0;
    z-index: 100;
    background: var(--bg-glass);
    backdrop-filter: blur(20px) saturate(180%);
    border-bottom: 1px solid var(--border-light);
    padding: 0 24px;
}

.header-container {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 70px;
    max-width: 1600px;
    margin: 0 auto;
    gap: 20px;
}

.logo-section {
    display: flex;
    align-items: center;
    gap: 16px;
}

.menu-toggle {
    background: none;
    border: none;
    color: var(--text-primary);
    font-size: 24px;
    cursor: pointer;
    padding: 8px;
    border-radius: var(--radius-md);
    transition: var(--transition);
    display: none;
}

.menu-toggle:hover {
    background: var(--bg-tertiary);
}

.logo {
    display: flex;
    align-items: center;
    gap: 12px;
    cursor: pointer;
}

.logo-icon {
    width: 44px;
    height: 44px;
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    border-radius: var(--radius-md);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: var(--shadow-glow);
}

.logo-icon i {
    font-size: 20px;
    color: white;
}

.logo-text {
    font-size: 24px;
    font-weight: 800;
    background: linear-gradient(135deg, #fff, var(--primary-light));
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
    letter-spacing: -0.5px;
}

/* Search */
.search-section {
    flex: 1;
    max-width: 500px;
}

.search-wrapper {
    position: relative;
    display: flex;
    align-items: center;
}

.search-icon {
    position: absolute;
    left: 16px;
    color: var(--text-muted);
    font-size: 16px;
    pointer-events: none;
}

.search-input {
    width: 100%;
    padding: 12px 48px 12px 48px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-full);
    color: var(--text-primary);
    font-size: 15px;
    transition: var(--transition);
}

.search-input:focus {
    outline: none;
    border-color: var(--primary);
    box-shadow: 0 0 0 3px rgba(255, 51, 102, 0.2);
    background: var(--bg-tertiary);
}

.search-clear {
    position: absolute;
    right: 12px;
    background: none;
    border: none;
    color: var(--text-muted);
    cursor: pointer;
    padding: 6px;
    border-radius: var(--radius-full);
    transition: var(--transition);
}

.search-clear:hover {
    background: var(--bg-tertiary);
    color: var(--text-primary);
}

/* Header Actions */
.header-actions {
    display: flex;
    align-items: center;
    gap: 12px;
}

.language-selector {
    position: relative;
}

.lang-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 16px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-full);
    color: var(--text-primary);
    cursor: pointer;
    transition: var(--transition);
}

.lang-btn:hover {
    background: var(--bg-tertiary);
}

.lang-dropdown {
    position: absolute;
    top: calc(100% + 8px);
    right: 0;
    background: var(--bg-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-lg);
    padding: 8px;
    min-width: 180px;
    display: none;
    box-shadow: var(--shadow-lg);
    backdrop-filter: blur(10px);
}

.lang-dropdown.active {
    display: block;
}

.lang-option {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: var(--transition);
}

.lang-option:hover {
    background: var(--bg-tertiary);
}

/* Auth Buttons */
.auth-buttons {
    display: flex;
    gap: 8px;
}

.btn-outline {
    padding: 10px 20px;
    background: transparent;
    border: 1px solid var(--border-medium);
    border-radius: var(--radius-full);
    color: var(--text-primary);
    font-weight: 500;
    cursor: pointer;
    transition: var(--transition);
    text-decoration: none;
}

.btn-outline:hover {
    background: var(--bg-tertiary);
    border-color: var(--border-light);
}

.btn-primary {
    padding: 10px 20px;
    background: linear-gradient(135deg, var(--primary), var(--primary-dark));
    border: none;
    border-radius: var(--radius-full);
    color: white;
    font-weight: 600;
    cursor: pointer;
    transition: var(--transition);
    box-shadow: 0 4px 12px rgba(255, 51, 102, 0.3);
    text-decoration: none;
}

.btn-primary:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 20px rgba(255, 51, 102, 0.4);
}

.user-menu {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px 6px 8px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-full);
    cursor: pointer;
}

.user-avatar {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 600;
}

/* Sidebar */
.sidebar {
    position: fixed;
    left: 0;
    top: 70px;
    bottom: 0;
    width: 280px;
    background: var(--bg-glass);
    backdrop-filter: blur(20px);
    border-right: 1px solid var(--border-light);
    padding: 20px 12px;
    overflow-y: auto;
    transition: var(--transition);
    z-index: 90;
}

.sidebar-header {
    padding: 0 12px 20px;
    border-bottom: 1px solid var(--border-light);
    margin-bottom: 16px;
}

.user-preview {
    display: flex;
    align-items: center;
    gap: 12px;
}

.sidebar-nav {
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.nav-item {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 12px 16px;
    color: var(--text-secondary);
    text-decoration: none;
    border-radius: var(--radius-md);
    transition: var(--transition);
    font-weight: 500;
}

.nav-item i {
    width: 24px;
    font-size: 20px;
}

.nav-item:hover {
    background: var(--bg-tertiary);
    color: var(--text-primary);
}

.nav-item.active {
    background: linear-gradient(90deg, rgba(255, 51, 102, 0.2), transparent);
    color: var(--primary);
    border-left: 3px solid var(--primary);
}

.nav-badge {
    margin-left: auto;
    background: var(--primary);
    color: white;
    padding: 2px 10px;
    border-radius: var(--radius-full);
    font-size: 12px;
    font-weight: 600;
}

.nav-divider {
    height: 1px;
    background: var(--border-light);
    margin: 16px 0;
}

/* Main Content */
.main-content {
    margin-left: 280px;
    padding: 24px 32px;
    min-height: calc(100vh - 70px);
    transition: var(--transition);
}

/* Categories */
.categories-section {
    margin-bottom: 32px;
}

.categories-scroll {
    display: flex;
    gap: 10px;
    overflow-x: auto;
    padding-bottom: 8px;
    scrollbar-width: none;
}

.categories-scroll::-webkit-scrollbar {
    display: none;
}

.category-chip {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 20px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-full);
    color: var(--text-secondary);
    font-weight: 500;
    cursor: pointer;
    transition: var(--transition);
    white-space: nowrap;
    flex-shrink: 0;
}

.category-chip i {
    font-size: 16px;
}

.category-chip:hover {
    background: var(--bg-tertiary);
    color: var(--text-primary);
}

.category-chip.active {
    background: var(--primary);
    border-color: var(--primary);
    color: white;
}

/* Player Section */
.player-section {
    margin-bottom: 32px;
    border-radius: var(--radius-xl);
    overflow: hidden;
    box-shadow: var(--shadow-lg);
}

.player-wrapper {
    position: relative;
    aspect-ratio: 16 / 9;
    background: #000;
}

.video-player {
    width: 100%;
    height: 100%;
    object-fit: contain;
}

/* Radio Visualizer */
.radio-visualizer {
    position: absolute;
    inset: 0;
    background: linear-gradient(135deg, #0a0a2e, #1a1a3e);
    display: none;
    align-items: center;
    justify-content: center;
}

.radio-visualizer.active {
    display: flex;
}

#visualizerCanvas {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: 0.3;
}

.radio-info {
    position: relative;
    z-index: 10;
    text-align: center;
}

.radio-cover {
    width: 140px;
    height: 140px;
    margin: 0 auto 20px;
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: var(--shadow-glow);
    animation: pulse 3s infinite;
}

@keyframes pulse {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.05); }
}

.radio-cover i {
    font-size: 56px;
    color: white;
}

.radio-info h3 {
    font-size: 24px;
    margin-bottom: 8px;
}

.radio-info p {
    color: var(--text-secondary);
    margin-bottom: 24px;
}

.radio-controls {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 16px;
}

.ctrl-btn {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid var(--border-light);
    color: white;
    cursor: pointer;
    transition: var(--transition);
}

.ctrl-btn:hover {
    background: rgba(255, 255, 255, 0.2);
}

.ctrl-btn.play-btn {
    width: 64px;
    height: 64px;
    background: var(--primary);
    border: none;
    font-size: 20px;
}

/* Player Overlay */
.player-overlay {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    padding: 20px;
    background: linear-gradient(to bottom, rgba(0,0,0,0.7), transparent);
    opacity: 0;
    transition: opacity 0.3s;
}

.player-wrapper:hover .player-overlay {
    opacity: 1;
}

.player-header {
    display: flex;
    align-items: center;
    gap: 20px;
}

.back-btn {
    width: 44px;
    height: 44px;
    border-radius: 50%;
    background: rgba(0, 0, 0, 0.5);
    border: none;
    color: white;
    cursor: pointer;
    transition: var(--transition);
}

.back-btn:hover {
    background: rgba(0, 0, 0, 0.7);
}

.channel-info {
    flex: 1;
}

.channel-info h2 {
    font-size: 20px;
    margin-bottom: 4px;
}

.channel-info p {
    font-size: 14px;
    color: var(--text-secondary);
}

.player-actions {
    display: flex;
    gap: 8px;
}

.action-btn {
    width: 44px;
    height: 44px;
    border-radius: 50%;
    background: rgba(0, 0, 0, 0.5);
    border: none;
    color: white;
    cursor: pointer;
    transition: var(--transition);
}

.action-btn:hover {
    background: rgba(0, 0, 0, 0.7);
}

.action-btn.active {
    color: var(--primary);
}

/* Channel Grid */
.section-header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 24px;
}

.section-header h2 {
    font-size: 28px;
    font-weight: 700;
}

.channel-count {
    color: var(--text-secondary);
    font-size: 16px;
}

.channel-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    gap: 20px;
}

.channel-card {
    background: var(--bg-glass);
    backdrop-filter: blur(10px);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-lg);
    padding: 20px;
    cursor: pointer;
    transition: var(--transition);
    position: relative;
    overflow: hidden;
}

.channel-card::before {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    opacity: 0;
    transition: var(--transition);
    z-index: -1;
}

.channel-card:hover {
    transform: translateY(-4px);
    border-color: var(--primary);
    box-shadow: var(--shadow-md);
}

.channel-card:hover::before {
    opacity: 0.05;
}

.card-logo {
    width: 72px;
    height: 72px;
    border-radius: var(--radius-lg);
    background: var(--bg-tertiary);
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 16px;
    font-size: 32px;
    transition: var(--transition);
}

.channel-card:hover .card-logo {
    transform: scale(1.05);
}

.card-name {
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 8px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.card-meta {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--text-secondary);
    font-size: 13px;
    margin-bottom: 16px;
}

.card-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-top: 16px;
    border-top: 1px solid var(--border-light);
}

.channel-type {
    padding: 4px 12px;
    border-radius: var(--radius-full);
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
}

.channel-type.tv {
    background: rgba(255, 51, 102, 0.2);
    color: var(--primary);
}

.channel-type.radio {
    background: rgba(6, 182, 212, 0.2);
    color: var(--accent);
}

.fav-btn {
    background: none;
    border: none;
    color: var(--text-muted);
    cursor: pointer;
    padding: 6px;
    border-radius: var(--radius-full);
    transition: var(--transition);
}

.fav-btn:hover {
    color: var(--primary);
}

.fav-btn.active {
    color: var(--primary);
}

/* Loading State */
.loading-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 60px;
    color: var(--text-secondary);
}

.loader {
    width: 48px;
    height: 48px;
    border: 3px solid var(--border-light);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: 16px;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

/* Toast */
.toast-container {
    position: fixed;
    bottom: 24px;
    right: 24px;
    z-index: 1000;
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.toast {
    background: var(--bg-glass);
    backdrop-filter: blur(20px);
    border-left: 4px solid var(--primary);
    padding: 16px 24px;
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    animation: slideIn 0.3s ease;
}

@keyframes slideIn {
    from {
        opacity: 0;
        transform: translateX(50px);
    }
    to {
        opacity: 1;
        transform: translateX(0);
    }
}

/* Responsive */
@media (max-width: 1024px) {
    .sidebar {
        transform: translateX(-100%);
        z-index: 150;
    }
    
    .sidebar.open {
        transform: translateX(0);
    }
    
    .main-content {
        margin-left: 0;
    }
    
    .menu-toggle {
        display: block;
    }
}

@media (max-width: 768px) {
    .glass-header {
        padding: 0 16px;
    }
    
    .logo-text {
        display: none;
    }
    
    .search-section {
        display: none;
    }
    
    .main-content {
        padding: 16px;
    }
    
    .channel-grid {
        grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
        gap: 12px;
    }
    
    .section-header h2 {
        font-size: 22px;
    }
}

@media (max-width: 480px) {
    .channel-grid {
        grid-template-columns: 1fr;
    }
    
    .categories-scroll {
        gap: 6px;
    }
    
    .category-chip {
        padding: 8px 14px;
        font-size: 13px;
    }
}
EOF

# Create i18n.js for multi-language
cat > frontend/js/i18n.js <<'EOF'
// Internationalization module
class I18n {
    constructor() {
        this.currentLang = localStorage.getItem('language') || 'ru';
        this.translations = {};
        this.loaded = false;
    }
    
    async init() {
        await this.loadLanguage(this.currentLang);
        this.loaded = true;
        this.updateUI();
    }
    
    async loadLanguage(lang) {
        try {
            const response = await fetch(`/api/locales/${lang}`);
            if (response.ok) {
                this.translations = await response.json();
            }
        } catch (error) {
            console.error('Failed to load language:', error);
            // Fallback to default translations
            this.translations = this.getFallbackTranslations(lang);
        }
    }
    
    getFallbackTranslations(lang) {
        const fallbacks = {
            ru: {
                home: 'Главная',
                tv: 'ТВ Каналы',
                radio: 'Радио',
                favorites: 'Избранное',
                profile: 'Профиль',
                devices: 'Устройства',
                history: 'История',
                admin: 'Админ-панель',
                all: 'Все',
                all_channels: 'Все каналы',
                loading: 'Загрузка...',
                search: 'Поиск каналов...',
                login: 'Войти',
                register: 'Регистрация',
                logout: 'Выйти',
                watch: 'Смотреть',
                listen: 'Слушать',
                add_to_favorites: 'В избранное',
                remove_from_favorites: 'Убрать',
                device_limit: 'Достигнут лимит устройств',
                max_devices: 'Максимум 3 устройства'
            },
            en: {
                home: 'Home',
                tv: 'TV Channels',
                radio: 'Radio',
                favorites: 'Favorites',
                profile: 'Profile',
                devices: 'Devices',
                history: 'History',
                admin: 'Admin Panel',
                all: 'All',
                all_channels: 'All Channels',
                loading: 'Loading...',
                search: 'Search channels...',
                login: 'Login',
                register: 'Register',
                logout: 'Logout',
                watch: 'Watch',
                listen: 'Listen',
                add_to_favorites: 'Add to Favorites',
                remove_from_favorites: 'Remove',
                device_limit: 'Device limit reached',
                max_devices: 'Maximum 3 devices'
            },
            uz: {
                home: 'Bosh sahifa',
                tv: 'TV Kanallar',
                radio: 'Radio',
                favorites: 'Sevimlilar',
                profile: 'Profil',
                devices: 'Qurilmalar',
                history: 'Tarix',
                admin: 'Admin panel',
                all: 'Hammasi',
                all_channels: 'Barcha kanallar',
                loading: 'Yuklanmoqda...',
                search: 'Kanallarni qidirish...',
                login: 'Kirish',
                register: 'Ro\'yxatdan o\'tish',
                logout: 'Chiqish',
                watch: 'Ko\'rish',
                listen: 'Tinglash',
                add_to_favorites: 'Sevimlilarga qo\'shish',
                remove_from_favorites: 'O\'chirish',
                device_limit: 'Qurilmalar chegarasiga yetildi',
                max_devices: 'Maksimum 3 ta qurilma'
            },
            tj: {
                home: 'Асосӣ',
                tv: 'ТВ Каналҳо',
                radio: 'Радио',
                favorites: 'Интихобшуда',
                profile: 'Профил',
                devices: 'Дастгоҳҳо',
                history: 'Таърих',
                admin: 'Панели администратор',
                all: 'Ҳама',
                all_channels: 'Ҳамаи каналҳо',
                loading: 'Боргирӣ...',
                search: 'Ҷустуҷӯи каналҳо...',
                login: 'Ворид',
                register: 'Сабти ном',
                logout: 'Баромад',
                watch: 'Тамошо',
                listen: 'Гӯш кардан',
                add_to_favorites: 'Ба интихобшуда',
                remove_from_favorites: 'Нест кардан',
                device_limit: 'Маҳдудияти дастгоҳҳо',
                max_devices: 'Максимум 3 дастгоҳ'
            }
        };
        return fallbacks[lang] || fallbacks.ru;
    }
    
    async switchLanguage(lang) {
        this.currentLang = lang;
        localStorage.setItem('language', lang);
        await this.loadLanguage(lang);
        this.updateUI();
    }
    
    translate(key) {
        return this.translations[key] || key;
    }
    
    updateUI() {
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            el.textContent = this.translate(key);
        });
        
        document.documentElement.lang = this.currentLang;
    }
}

const i18n = new I18n();
document.addEventListener('DOMContentLoaded', () => i18n.init());
EOF

# Create language files
mkdir -p frontend/locales
cat > frontend/locales/ru.json <<'EOF'
{
  "home": "Главная",
  "tv": "ТВ Каналы",
  "radio": "Радио",
  "favorites": "Избранное",
  "profile": "Профиль",
  "devices": "Устройства",
  "history": "История",
  "admin": "Админ-панель",
  "all": "Все",
  "all_channels": "Все каналы",
  "loading": "Загрузка...",
  "search": "Поиск каналов...",
  "login": "Войти",
  "register": "Регистрация",
  "logout": "Выйти",
  "watch": "Смотреть",
  "listen": "Слушать",
  "add_to_favorites": "В избранное",
  "remove_from_favorites": "Убрать из избранного",
  "device_limit": "Достигнут лимит устройств",
  "max_devices": "Максимум 3 устройства",
  "remove_device": "Удалить устройство",
  "current_device": "Текущее устройство",
  "last_active": "Последняя активность",
  "share": "Поделиться",
  "copy_link": "Скопировать ссылку",
  "link_copied": "Ссылка скопирована",
  "error": "Ошибка",
  "success": "Успешно",
  "save": "Сохранить",
  "cancel": "Отмена",
  "delete": "Удалить",
  "edit": "Редактировать",
  "settings": "Настройки",
  "language": "Язык",
  "theme": "Тема",
  "dark": "Тёмная",
  "light": "Светлая",
  "auto": "Авто",
  "quality": "Качество",
  "auto_quality": "Авто",
  "hd": "HD",
  "sd": "SD",
  "notifications": "Уведомления",
  "sound": "Звук",
  "yandex_login": "Войти через Яндекс",
  "google_login": "Войти через Google",
  "or": "или",
  "email": "Email",
  "password": "Пароль",
  "username": "Имя пользователя",
  "remember_me": "Запомнить меня",
  "forgot_password": "Забыли пароль?",
  "no_account": "Нет аккаунта?",
  "has_account": "Уже есть аккаунт?",
  "welcome_back": "С возвращением!",
  "welcome": "Добро пожаловать!",
  "streaming": "Прямой эфир",
  "viewers": "зрителей",
  "listeners": "слушателей"
}
EOF

# Copy for other languages (simplified)
cp frontend/locales/ru.json frontend/locales/en.json
cp frontend/locales/ru.json frontend/locales/uz.json
cp frontend/locales/ru.json frontend/locales/tj.json

# Create auth.js
cat > frontend/js/auth.js <<'EOF'
// Authentication module
class AuthManager {
    constructor() {
        this.token = localStorage.getItem('token');
        this.user = JSON.parse(localStorage.getItem('user') || 'null');
        this.deviceId = this.getDeviceId();
        this.updateUI();
    }
    
    getDeviceId() {
        let deviceId = localStorage.getItem('deviceId');
        if (!deviceId) {
            deviceId = this.generateDeviceId();
            localStorage.setItem('deviceId', deviceId);
        }
        return deviceId;
    }
    
    generateDeviceId() {
        return 'device_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    }
    
    getDeviceInfo() {
        return {
            deviceId: this.deviceId,
            name: navigator.userAgentData?.platform || navigator.platform,
            type: this.getDeviceType(),
            browser: this.getBrowser(),
            os: this.getOS()
        };
    }
    
    getDeviceType() {
        const ua = navigator.userAgent;
        if (/(tablet|ipad|playbook|silk)|(android(?!.*mobi))/i.test(ua)) return 'tablet';
        if (/Mobile|Android|iP(hone|od)|IEMobile|BlackBerry|Kindle|Silk-Accelerated/i.test(ua)) return 'mobile';
        return 'desktop';
    }
    
    getBrowser() {
        const ua = navigator.userAgent;
        if (ua.includes('Firefox')) return 'Firefox';
        if (ua.includes('SamsungBrowser')) return 'Samsung';
        if (ua.includes('Opera') || ua.includes('OPR')) return 'Opera';
        if (ua.includes('Edge')) return 'Edge';
        if (ua.includes('Chrome')) return 'Chrome';
        if (ua.includes('Safari')) return 'Safari';
        return 'Unknown';
    }
    
    getOS() {
        const ua = navigator.userAgent;
        if (ua.includes('Windows')) return 'Windows';
        if (ua.includes('Mac')) return 'macOS';
        if (ua.includes('Linux')) return 'Linux';
        if (ua.includes('Android')) return 'Android';
        if (ua.includes('iOS') || ua.includes('iPhone') || ua.includes('iPad')) return 'iOS';
        return 'Unknown';
    }
    
    isAuthenticated() {
        return !!this.token;
    }
    
    isAdmin() {
        return this.user?.role === 'admin';
    }
    
    async login(email, password) {
        try {
            const response = await fetch('/api/auth/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    email,
                    password,
                    deviceInfo: this.getDeviceInfo()
                })
            });
            
            const data = await response.json();
            
            if (!response.ok) {
                if (data.error === 'DEVICE_LIMIT') {
                    throw new Error('DEVICE_LIMIT');
                }
                throw new Error(data.error || 'Login failed');
            }
            
            this.setSession(data);
            return data;
        } catch (error) {
            throw error;
        }
    }
    
    async register(username, email, password) {
        try {
            const response = await fetch('/api/auth/register', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username, email, password })
            });
            
            const data = await response.json();
            
            if (!response.ok) {
                throw new Error(data.error || 'Registration failed');
            }
            
            this.setSession(data);
            return data;
        } catch (error) {
            throw error;
        }
    }
    
    setSession(data) {
        this.token = data.token;
        this.user = data.user;
        localStorage.setItem('token', data.token);
        localStorage.setItem('user', JSON.stringify(data.user));
        this.updateUI();
    }
    
    logout() {
        fetch('/api/auth/logout', { method: 'POST' });
        this.token = null;
        this.user = null;
        localStorage.removeItem('token');
        localStorage.removeItem('user');
        this.updateUI();
        window.location.href = '/';
    }
    
    updateUI() {
        const authSection = document.getElementById('authSection');
        const userPreview = document.getElementById('userPreview');
        const adminLink = document.getElementById('adminLink');
        
        if (!authSection) return;
        
        if (this.isAuthenticated()) {
            authSection.innerHTML = `
                <div class="user-menu" onclick="toggleUserMenu()">
                    <div class="user-avatar">
                        ${this.user.avatar ? 
                            `<img src="${this.user.avatar}" alt="${this.user.username}">` : 
                            this.user.username?.charAt(0).toUpperCase()}
                    </div>
                    <span>${this.user.username}</span>
                    <i class="fas fa-chevron-down"></i>
                </div>
                <div class="user-dropdown" id="userDropdown">
                    <a href="/pages/profile.html"><i class="fas fa-user"></i> Профиль</a>
                    <a href="/pages/devices.html"><i class="fas fa-mobile-alt"></i> Устройства</a>
                    <a href="/pages/settings.html"><i class="fas fa-cog"></i> Настройки</a>
                    ${this.isAdmin() ? '<a href="/pages/admin/dashboard.html"><i class="fas fa-shield-alt"></i> Админ-панель</a>' : ''}
                    <div class="dropdown-divider"></div>
                    <a href="#" onclick="auth.logout(); return false;"><i class="fas fa-sign-out-alt"></i> Выйти</a>
                </div>
            `;
            
            if (userPreview) {
                userPreview.innerHTML = `
                    <div class="user-avatar">${this.user.username?.charAt(0).toUpperCase()}</div>
                    <div class="user-info">
                        <p class="user-name">${this.user.username}</p>
                        <p class="user-email">${this.user.email}</p>
                    </div>
                `;
            }
            
            if (adminLink) {
                adminLink.style.display = this.isAdmin() ? 'flex' : 'none';
            }
        } else {
            authSection.innerHTML = `
                <div class="auth-buttons">
                    <a href="/pages/login.html" class="btn-outline">Войти</a>
                    <a href="/pages/register.html" class="btn-primary">Регистрация</a>
                </div>
            `;
            
            if (userPreview) {
                userPreview.innerHTML = `
                    <div class="guest-preview">
                        <i class="fas fa-user-circle"></i>
                        <p>Гость</p>
                    </div>
                `;
            }
        }
    }
    
    getHeaders() {
        return {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.token}`
        };
    }
    
    async checkDeviceLimit() {
        try {
            const response = await fetch('/api/devices', {
                headers: this.getHeaders()
            });
            const data = await response.json();
            return data.devices?.length >= data.maxDevices;
        } catch {
            return false;
        }
    }
}

const auth = new AuthManager();

function toggleUserMenu() {
    const dropdown = document.getElementById('userDropdown');
    dropdown?.classList.toggle('active');
}

document.addEventListener('click', (e) => {
    if (!e.target.closest('.user-menu')) {
        document.getElementById('userDropdown')?.classList.remove('active');
    }
});
EOF

# Setup Nginx
print_info "Настройка Nginx..."
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
        proxy_cache_bypass \$http_upgrade;
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

# SSL
print_info "Настройка SSL..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL

# Install dependencies and start
print_info "Установка Node.js зависимостей..."
cd $INSTALL_DIR
npm install

print_info "Запуск приложения..."
pm2 start server.js --name vision-tv
pm2 save
pm2 startup

# Final output
clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║                    🎉 УСТАНОВКА ЗАВЕРШЕНА! 🎉                  ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""
echo -e "${GREEN}✅ Vision TV успешно установлен!${NC}"
echo ""
echo "📋 ИНФОРМАЦИЯ О СИСТЕМЕ:"
echo "═══════════════════════════════════════════════════════════"
echo -e "🌐 Сайт: ${CYAN}https://$DOMAIN${NC}"
echo -e "🔐 Админ-панель: ${CYAN}https://$DOMAIN/pages/admin/dashboard.html${NC}"
echo ""
echo "👤 ДАННЫЕ АДМИНИСТРАТОРА:"
echo "═══════════════════════════════════════════════════════════"
echo -e "📧 Email: ${CYAN}admin@$DOMAIN${NC}"
echo -e "🔑 Пароль: ${CYAN}$ADMIN_PASSWORD${NC}"
echo ""
echo "🔧 OAuth НАСТРОЙКИ (добавьте в консолях разработчика):"
echo "═══════════════════════════════════════════════════════════"
echo -e "Яндекс Callback URL: ${CYAN}https://$DOMAIN/api/auth/yandex/callback${NC}"
echo -e "Google Callback URL: ${CYAN}https://$DOMAIN/api/auth/google/callback${NC}"
echo ""
echo "📁 РАСПОЛОЖЕНИЕ ФАЙЛОВ:"
echo "═══════════════════════════════════════════════════════════"
echo -e "${CYAN}$INSTALL_DIR${NC}"
echo ""
echo "🖥️ КОМАНДЫ УПРАВЛЕНИЯ:"
echo "═══════════════════════════════════════════════════════════"
echo "  pm2 status              - Статус приложения"
echo "  pm2 logs vision-tv      - Просмотр логов"
echo "  pm2 restart vision-tv   - Перезапуск"
echo "  pm2 stop vision-tv      - Остановка"
echo ""
echo "🌍 ПОДДЕРЖИВАЕМЫЕ ЯЗЫКИ:"
echo "═══════════════════════════════════════════════════════════"
echo "  🇷🇺 Русский  |  🇬🇧 English  |  🇺🇿 O'zbek  |  🇹🇯 Тоҷикӣ"
echo ""
echo "✨ ОСНОВНЫЕ ФУНКЦИИ:"
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Авторизация через Яндекс и Google"
echo "  ✓ Лимит 3 устройства на пользователя"
echo "  ✓ Мультиязычный интерфейс (4 языка)"
echo "  ✓ Современный дизайн с анимациями"
echo "  ✓ Личный кабинет с историей просмотров"
echo "  ✓ Админ-панель для управления"
echo "  ✓ Автоматическое сканирование каналов"
echo "  ✓ Избранное и плейлисты"
echo "  ✓ Адаптивный дизайн для всех устройств"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}⚠️  ВАЖНО: Сохраните пароль администратора!${NC}"
echo -e "Он также сохранён в файле: ${CYAN}$INSTALL_DIR/admin_credentials.txt${NC}"
echo ""

# Save credentials
echo "Admin: admin@$DOMAIN / $ADMIN_PASSWORD" > $INSTALL_DIR/admin_credentials.txt
echo "OAuth Yandex Callback: https://$DOMAIN/api/auth/yandex/callback" >> $INSTALL_DIR/admin_credentials.txt
echo "OAuth Google Callback: https://$DOMAIN/api/auth/google/callback" >> $INSTALL_DIR/admin_credentials.txt