#!/bin/bash
# Vision TV - Complete Installation Script (Fixed)
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
echo "Настройка OAuth авторизации (можно оставить пустым):"
echo "----------------------------------------------------"
read -p "Yandex Client ID: " YANDEX_CLIENT_ID
read -p "Yandex Client Secret: " YANDEX_CLIENT_SECRET
read -p "Google Client ID: " GOOGLE_CLIENT_ID
read -p "Google Client Secret: " GOOGLE_CLIENT_SECRET

read -sp "Пароль администратора (Enter для авто-генерации): " ADMIN_PASSWORD
echo ""
[ -z "$ADMIN_PASSWORD" ] && ADMIN_PASSWORD=$(openssl rand -base64 12)

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

# Install PM2 and update npm
npm install -g npm@latest
npm install -g pm2
print_success "Зависимости установлены"

# Create project structure
INSTALL_DIR="/var/www/vision-tv"
print_info "Создание структуры проекта в $INSTALL_DIR"
mkdir -p $INSTALL_DIR/{backend/{routes,models,middleware,database,config},frontend/{pages/{admin},css,js,locales,assets},data,nginx,logs}
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

# API
API_BASE=https://api.mediabay.tv/v2/channels/thread
SCAN_START=1
SCAN_END=800
EOF

# Create package.json with FIXED dependencies
cat > package.json <<'EOF'
{
  "name": "vision-tv",
  "version": "2.0.1",
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
    "passport-google-oauth20": "^2.0.0",
    "express-rate-limit": "^6.10.0",
    "compression": "^1.7.4",
    "morgan": "^1.10.0",
    "dotenv": "^16.3.1",
    "axios": "^1.5.0",
    "multer": "^1.4.5-lts.1",
    "socket.io": "^4.6.2",
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

// Serialize/deserialize
passport.serializeUser((user, done) => done(null, user.id));
passport.deserializeUser((id, done) => {
    const db = require('./backend/database/init').db;
    db.get('SELECT id, username, email, role, avatar FROM users WHERE id = ?', [id], 
        (err, user) => done(err, user));
});

// Google OAuth (if configured)
if (process.env.GOOGLE_CLIENT_ID) {
    const GoogleStrategy = require('passport-google-oauth20').Strategy;
    passport.use(new GoogleStrategy({
        clientID: process.env.GOOGLE_CLIENT_ID,
        clientSecret: process.env.GOOGLE_CLIENT_SECRET,
        callbackURL: process.env.GOOGLE_CALLBACK_URL
    }, (accessToken, refreshToken, profile, done) => {
        const db = require('./backend/database/init').db;
        const email = profile.emails?.[0]?.value;
        const username = profile.displayName || email?.split('@')[0];
        const avatar = profile.photos?.[0]?.value;
        
        db.get('SELECT * FROM users WHERE email = ?', [email], (err, user) => {
            if (err) return done(err);
            if (user) {
                db.run('UPDATE users SET last_login = CURRENT_TIMESTAMP, avatar = COALESCE(?, avatar) WHERE id = ?',
                    [avatar, user.id]);
                return done(null, user);
            }
            
            db.run(
                'INSERT INTO users (username, email, provider, provider_id, avatar, role) VALUES (?, ?, ?, ?, ?, ?)',
                [username, email, 'google', profile.id, avatar, 'user'],
                function(err) {
                    if (err) return done(err);
                    db.get('SELECT * FROM users WHERE id = ?', [this.lastID], done);
                }
            );
        });
    }));
}

// Static files
app.use(express.static(path.join(__dirname, 'frontend')));
app.use('/uploads', express.static(path.join(__dirname, 'data/uploads')));

// Initialize database
require('./backend/database/init')();

// Routes
app.use('/api/auth', require('./backend/routes/auth'));
app.use('/api/channels', require('./backend/routes/channels'));
app.use('/api/devices', require('./backend/routes/devices'));
app.use('/api/admin', require('./backend/routes/admin'));

// SPA fallback
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'frontend/index.html'));
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`🚀 Vision TV running on port ${PORT}`);
    console.log(`📍 Domain: ${process.env.DOMAIN}`);
});
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
            last_login DATETIME,
            is_active INTEGER DEFAULT 1
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
            status TEXT DEFAULT 'active',
            views INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
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
            'allow_registration': 'true',
            'max_devices': '3',
            'scan_enabled': 'true'
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

// Register
router.post('/register', async (req, res) => {
    try {
        const { username, email, password } = req.body;

        if (!username || !email || !password) {
            return res.status(400).json({ error: 'All fields required' });
        }

        db.get('SELECT id FROM users WHERE email = ?', [email], async (err, row) => {
            if (row) return res.status(400).json({ error: 'User already exists' });

            const hash = await bcrypt.hash(password, 10);
            db.run(
                'INSERT INTO users (username, email, password) VALUES (?, ?, ?)',
                [username, email, hash],
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
router.post('/login', (req, res) => {
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
            db.get('SELECT COUNT(*) as count FROM devices WHERE user_id = ?', [user.id], (err, result) => {
                if (result.count >= 3) {
                    db.get('SELECT id FROM devices WHERE user_id = ? AND device_id = ?',
                        [user.id, deviceInfo.deviceId], (err, existing) => {
                            if (!existing) {
                                return res.status(403).json({ 
                                    error: 'DEVICE_LIMIT',
                                    message: 'Maximum 3 devices allowed'
                                });
                            }
                            completeLogin();
                        });
                } else {
                    completeLogin();
                }
            });
        } else {
            completeLogin();
        }

        function completeLogin() {
            db.run('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?', [user.id]);

            if (deviceInfo) {
                db.run(
                    `INSERT OR REPLACE INTO devices 
                     (user_id, device_id, device_name, device_type, browser, os, last_ip)
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

// Google OAuth routes
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
            'SELECT id, username, email, role, avatar, created_at FROM users WHERE id = ?',
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

module.exports = router;
EOF

# Create channels routes
cat > backend/routes/channels.js <<'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const axios = require('axios');
const router = express.Router();
const db = require('../database/init').db;

// Get channels with scanning
router.get('/', async (req, res) => {
    const { type } = req.query;
    
    let query = 'SELECT * FROM channels WHERE status = ?';
    const params = ['active'];
    
    if (type) {
        query += ' AND type = ?';
        params.push(type);
    }
    
    query += ' ORDER BY name ASC';
    
    db.all(query, params, async (err, channels) => {
        if (err) return res.status(500).json({ error: 'Database error' });
        
        // If no channels, trigger scan
        if (channels.length === 0) {
            try {
                await scanChannels();
                db.all(query, params, (err, newChannels) => {
                    res.json({ channels: newChannels });
                });
            } catch (e) {
                res.json({ channels: [] });
            }
        } else {
            res.json({ channels });
        }
    });
});

// Scan channels from API
async function scanChannels() {
    const API_BASE = process.env.API_BASE;
    const SCAN_START = parseInt(process.env.SCAN_START) || 1;
    const SCAN_END = parseInt(process.env.SCAN_END) || 100;
    
    for (let i = SCAN_START; i <= SCAN_END; i++) {
        try {
            const response = await axios.get(`${API_BASE}/${i}`, { timeout: 3000 });
            if (response.data?.status === 'ok' && response.data.data?.[0]?.threadAddress) {
                const url = response.data.data[0].threadAddress;
                if (url?.includes('.m3u8')) {
                    const name = formatChannelName(url);
                    const type = detectChannelType(name, url);
                    
                    db.run(
                        'INSERT OR IGNORE INTO channels (id, name, url, type) VALUES (?, ?, ?, ?)',
                        [String(i), name, url, type]
                    );
                }
            }
        } catch (e) {
            // Skip failed requests
        }
        
        if (i % 10 === 0) {
            await new Promise(r => setTimeout(r, 100));
        }
    }
}

function formatChannelName(url) {
    try {
        const match = url.match(/\/([^\/]+?)\/playlist\.m3u8/i);
        if (match?.[1]) {
            return decodeURIComponent(match[1]).replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()).trim();
        }
    } catch (e) {}
    return 'Channel';
}

function detectChannelType(name, url) {
    const lower = (name + url).toLowerCase();
    const radioKeywords = ['radio', 'fm', 'music', 'audio'];
    return radioKeywords.some(kw => lower.includes(kw)) ? 'radio' : 'tv';
}

// Toggle favorite
router.post('/favorites/:channelId', (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Auth required' });
    
    try {
        const user = jwt.verify(token, process.env.JWT_SECRET);
        db.run(
            'INSERT OR IGNORE INTO favorites (user_id, channel_id) VALUES (?, ?)',
            [user.id, req.params.channelId],
            (err) => {
                if (err) return res.status(500).json({ error: 'Database error' });
                res.json({ success: true });
            }
        );
    } catch {
        res.status(401).json({ error: 'Invalid token' });
    }
});

router.delete('/favorites/:channelId', (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Auth required' });
    
    try {
        const user = jwt.verify(token, process.env.JWT_SECRET);
        db.run(
            'DELETE FROM favorites WHERE user_id = ? AND channel_id = ?',
            [user.id, req.params.channelId],
            (err) => {
                if (err) return res.status(500).json({ error: 'Database error' });
                res.json({ success: true });
            }
        );
    } catch {
        res.status(401).json({ error: 'Invalid token' });
    }
});

module.exports = router;
EOF

# Create devices routes
cat > backend/routes/devices.js <<'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const db = require('../database/init').db;

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

router.delete('/:deviceId', authMiddleware, (req, res) => {
    db.run(
        'DELETE FROM devices WHERE user_id = ? AND device_id = ?',
        [req.user.id, req.params.deviceId],
        (err) => {
            if (err) return res.status(500).json({ error: 'Database error' });
            res.json({ success: true });
        }
    );
});

module.exports = router;
EOF

# Create admin routes
cat > backend/routes/admin.js <<'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const db = require('../database/init').db;

const adminMiddleware = (req, res, next) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Auth required' });
    
    try {
        const user = jwt.verify(token, process.env.JWT_SECRET);
        if (user.role !== 'admin') return res.status(403).json({ error: 'Admin only' });
        req.user = user;
        next();
    } catch {
        res.status(401).json({ error: 'Invalid token' });
    }
};

router.get('/stats', adminMiddleware, (req, res) => {
    const stats = {};
    
    db.get('SELECT COUNT(*) as count FROM users', (err, row) => {
        stats.users = row?.count || 0;
        db.get('SELECT COUNT(*) as count FROM channels', (err, row) => {
            stats.channels = row?.count || 0;
            db.get('SELECT COUNT(*) as count FROM favorites', (err, row) => {
                stats.favorites = row?.count || 0;
                res.json(stats);
            });
        });
    });
});

router.get('/users', adminMiddleware, (req, res) => {
    db.all(
        'SELECT id, username, email, role, created_at, last_login FROM users ORDER BY created_at DESC',
        (err, users) => {
            if (err) return res.status(500).json({ error: 'Database error' });
            res.json({ users });
        }
    );
});

router.delete('/users/:id', adminMiddleware, (req, res) => {
    db.run('DELETE FROM users WHERE id = ? AND role != ?', [req.params.id, 'admin'], (err) => {
        if (err) return res.status(500).json({ error: 'Database error' });
        res.json({ success: true });
    });
});

module.exports = router;
EOF

# Create simple frontend
cat > frontend/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vision TV</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Inter', sans-serif; background: #0f0f0f; color: #fff; min-height: 100vh; }
        .header { background: #1a1a1a; padding: 16px 24px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #333; }
        .logo { font-size: 24px; font-weight: 700; background: linear-gradient(135deg, #ff3366, #6366f1); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .container { max-width: 1400px; margin: 0 auto; padding: 24px; }
        .auth-section { display: flex; gap: 12px; }
        .btn { padding: 10px 20px; border-radius: 30px; border: none; cursor: pointer; font-weight: 600; text-decoration: none; display: inline-block; }
        .btn-primary { background: linear-gradient(135deg, #ff3366, #e61e4d); color: white; }
        .btn-outline { background: transparent; border: 1px solid #444; color: white; }
        .channel-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 20px; margin-top: 24px; }
        .channel-card { background: #1a1a1a; border: 1px solid #333; border-radius: 16px; padding: 20px; cursor: pointer; transition: all 0.2s; }
        .channel-card:hover { transform: translateY(-4px); border-color: #ff3366; }
        .channel-logo { width: 60px; height: 60px; background: #252525; border-radius: 12px; display: flex; align-items: center; justify-content: center; margin-bottom: 16px; font-size: 24px; }
        .channel-name { font-weight: 600; margin-bottom: 8px; }
        .channel-type { font-size: 12px; color: #888; }
        .loading { text-align: center; padding: 40px; color: #888; }
        #playerSection { margin-bottom: 24px; display: none; }
        #videoPlayer { width: 100%; max-height: 500px; background: #000; border-radius: 16px; }
    </style>
</head>
<body>
    <header class="header">
        <div class="logo">📺 Vision TV</div>
        <div class="auth-section" id="authSection">
            <a href="/login" class="btn btn-outline">Войти</a>
            <a href="/register" class="btn btn-primary">Регистрация</a>
        </div>
    </header>
    
    <div class="container">
        <div id="playerSection">
            <video id="videoPlayer" controls playsinline></video>
        </div>
        
        <h2>Доступные каналы</h2>
        <div class="channel-grid" id="channelGrid">
            <div class="loading">Загрузка каналов...</div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js"></script>
    <script>
        const API = '/api';
        let currentChannel = null;
        let hls = null;
        
        async function loadChannels() {
            try {
                const res = await fetch(API + '/channels');
                const data = await res.json();
                renderChannels(data.channels || []);
            } catch (e) {
                document.getElementById('channelGrid').innerHTML = '<div class="loading">Ошибка загрузки</div>';
            }
        }
        
        function renderChannels(channels) {
            const grid = document.getElementById('channelGrid');
            if (!channels.length) {
                grid.innerHTML = '<div class="loading">Каналы не найдены</div>';
                return;
            }
            
            grid.innerHTML = channels.map(c => `
                <div class="channel-card" onclick="playChannel('${c.id}', '${c.url}', '${c.type}')">
                    <div class="channel-logo">${c.type === 'tv' ? '📺' : '📻'}</div>
                    <div class="channel-name">${c.name}</div>
                    <div class="channel-type">${c.type === 'tv' ? 'Телеканал' : 'Радио'}</div>
                </div>
            `).join('');
        }
        
        function playChannel(id, url, type) {
            const player = document.getElementById('videoPlayer');
            const section = document.getElementById('playerSection');
            
            section.style.display = 'block';
            
            if (hls) hls.destroy();
            
            if (Hls.isSupported()) {
                hls = new Hls();
                hls.loadSource(url);
                hls.attachMedia(player);
                hls.on(Hls.Events.MANIFEST_PARSED, () => player.play());
            } else if (player.canPlayType('application/vnd.apple.mpegurl')) {
                player.src = url;
                player.play();
            }
            
            player.scrollIntoView({ behavior: 'smooth' });
        }
        
        // Check auth
        const token = localStorage.getItem('token');
        if (token) {
            document.getElementById('authSection').innerHTML = `
                <button class="btn btn-outline" onclick="logout()">Выйти</button>
            `;
        }
        
        function logout() {
            localStorage.removeItem('token');
            location.reload();
        }
        
        loadChannels();
    </script>
</body>
</html>
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
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL 2>/dev/null || print_warning "SSL не настроен (проверьте домен)"

# Install dependencies and start
print_info "Установка Node.js зависимостей..."
cd $INSTALL_DIR
npm install --legacy-peer-deps

# Initialize database
node -e "require('./backend/database/init').initialize()"

print_info "Запуск приложения..."
pm2 start server.js --name vision-tv
pm2 save
pm2 startup systemd 2>/dev/null || true

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
echo "📋 ИНФОРМАЦИЯ:"
echo "═══════════════════════════════════════════════════════════"
echo -e "🌐 Сайт: ${CYAN}https://$DOMAIN${NC}"
echo ""
echo "👤 АДМИНИСТРАТОР:"
echo "═══════════════════════════════════════════════════════════"
echo -e "📧 Email: ${CYAN}admin@$DOMAIN${NC}"
echo -e "🔑 Пароль: ${CYAN}$ADMIN_PASSWORD${NC}"
echo ""
echo "🖥️ КОМАНДЫ УПРАВЛЕНИЯ:"
echo "═══════════════════════════════════════════════════════════"
echo "  pm2 status              - Статус"
echo "  pm2 logs vision-tv      - Логи"
echo "  pm2 restart vision-tv   - Перезапуск"
echo ""

# Save credentials
echo "Admin: admin@$DOMAIN / $ADMIN_PASSWORD" > $INSTALL_DIR/admin_credentials.txt
echo "Site: https://$DOMAIN" >> $INSTALL_DIR/admin_credentials.txt