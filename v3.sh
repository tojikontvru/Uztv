#!/bin/bash
#############################################################
# VISION TV - Complete Auto Installer (FIXED)
# OAuth (Yandex/Google) + 4 Languages + Admin Panel
# Device Limit: 3 | Netflix-style UI
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
print_header() { echo -e "\n${CYAN}${BOLD}$1${NC}\n"; }

# Root check
if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с правами root: sudo bash install.sh"
   exit 1
fi

# Welcome
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   ██╗   ██╗██╗███████╗██╗ ██████╗ ███╗   ██╗                     ║
║   ██║   ██║██║██╔════╝██║██╔═══██╗████╗  ██║                     ║
║   ██║   ██║██║███████╗██║██║   ██║██╔██╗ ██║                     ║
║   ╚██╗ ██╔╝██║╚════██║██║██║   ██║██║╚██╗██║                     ║
║    ╚████╔╝ ██║███████║██║╚██████╔╝██║ ╚████║                     ║
║     ╚═══╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝                     ║
║                                                                   ║
║         📺 ТВ • 📻 Радио • 👤 Профиль • 🛠 Админ                   ║
║                                                                   ║
║              🌍 RU • EN • UZ • TJ                                 ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF

echo ""
print_info "Добро пожаловать в установщик Vision TV!"
echo ""

# Get configuration
print_header "📋 НАСТРОЙКА"
read -p "🌐 Введите домен (например: tv.example.com): " DOMAIN
[ -z "$DOMAIN" ] && { print_error "Домен обязателен"; exit 1; }

read -p "📧 Email для SSL: " SSL_EMAIL
[ -z "$SSL_EMAIL" ] && SSL_EMAIL="admin@$DOMAIN"

read -p "🔌 Порт (по умолчанию 3000): " SERVER_PORT
[ -z "$SERVER_PORT" ] && SERVER_PORT=3000

echo ""
print_info "🔐 Настройка OAuth (можно пропустить):"
read -p "Google Client ID: " GOOGLE_CLIENT_ID
read -p "Google Client Secret: " GOOGLE_CLIENT_SECRET

echo ""
read -sp "🔑 Пароль админа (Enter для авто-генерации): " ADMIN_PASSWORD
echo ""
[ -z "$ADMIN_PASSWORD" ] && ADMIN_PASSWORD=$(openssl rand -base64 12)

echo ""
print_info "Параметры установки:"
echo "  🌐 Домен: $DOMAIN"
echo "  📧 Email: $SSL_EMAIL"
echo "  🔌 Порт: $SERVER_PORT"
echo "  🔑 Google OAuth: ${GOOGLE_CLIENT_ID:+✅}"
echo ""
read -p "🚀 Начать установку? (y/n): " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { print_warning "Отменено"; exit 0; }

# Install Node.js 20
print_header "📦 УСТАНОВКА NODE.JS 20"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
print_success "Node.js: $(node -v)"

# Install dependencies
print_header "📦 УСТАНОВКА ЗАВИСИМОСТЕЙ"
apt-get update
apt-get install -y git nginx certbot python3-certbot-nginx sqlite3 redis-server curl
npm install -g pm2
print_success "Зависимости установлены"

# Create project
INSTALL_DIR="/var/www/vision-tv"
print_header "📁 СОЗДАНИЕ ПРОЕКТА"
mkdir -p $INSTALL_DIR/{backend/{config,routes,database},frontend/{css,js,locales,admin},data,logs}
cd $INSTALL_DIR

# Generate secrets
JWT_SECRET=$(openssl rand -base64 32)
SESSION_SECRET=$(openssl rand -base64 32)

# .env file
cat > .env <<EOF
DOMAIN=$DOMAIN
PORT=$SERVER_PORT
NODE_ENV=production

DB_PATH=$INSTALL_DIR/data/database.db
REDIS_URL=redis://localhost:6379

JWT_SECRET=$JWT_SECRET
SESSION_SECRET=$SESSION_SECRET

GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET
GOOGLE_CALLBACK_URL=https://$DOMAIN/api/auth/google/callback

ADMIN_EMAIL=admin@$DOMAIN
ADMIN_PASSWORD=$ADMIN_PASSWORD

MAX_DEVICES_PER_USER=3
API_BASE=https://api.mediabay.tv/v2/channels/thread
SCAN_START=1
SCAN_END=800
EOF

# package.json (ИСПРАВЛЕНО - без passport-yandex)
cat > package.json <<'EOF'
{
  "name": "vision-tv",
  "version": "4.0.1",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
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
    "axios": "^1.5.0",
    "socket.io": "^4.6.2",
    "dotenv": "^16.3.1",
    "compression": "^1.7.4",
    "morgan": "^1.10.0"
  }
}
EOF

# server.js
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

const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect().catch(console.error);

app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com", "https://cdnjs.cloudflare.com"],
            scriptSrc: ["'self'", "'unsafe-inline'", "https://apis.google.com", "https://cdn.jsdelivr.net"],
            imgSrc: ["'self'", "data:", "https:", "https://lh3.googleusercontent.com"],
            connectSrc: ["'self'", "https://api.mediabay.tv", "https://accounts.google.com"]
        }
    }
}));
app.use(cors({ origin: true, credentials: true }));
app.use(compression());
app.use(morgan('combined'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(session({
    store: new RedisStore({ client: redisClient }),
    secret: process.env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    cookie: { secure: process.env.NODE_ENV === 'production', httpOnly: true, maxAge: 7 * 24 * 60 * 60 * 1000 }
}));

app.use(passport.initialize());
app.use(passport.session());
require('./backend/config/passport')(passport);

app.use(express.static(path.join(__dirname, 'frontend')));
require('./backend/database/init')();

app.use('/api/auth', require('./backend/routes/auth'));
app.use('/api/channels', require('./backend/routes/channels'));
app.use('/api/devices', require('./backend/routes/devices'));
app.use('/api/admin', require('./backend/routes/admin'));

app.get('/api/locales/:lang', (req, res) => {
    try { res.json(require(`./frontend/locales/${req.params.lang}.json`)); }
    catch { res.json({}); }
});

// Page routes
app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'frontend/index.html')));
app.get('/login', (req, res) => res.sendFile(path.join(__dirname, 'frontend/login.html')));
app.get('/register', (req, res) => res.sendFile(path.join(__dirname, 'frontend/register.html')));
app.get('/profile', (req, res) => res.sendFile(path.join(__dirname, 'frontend/profile.html')));
app.get('/devices', (req, res) => res.sendFile(path.join(__dirname, 'frontend/devices.html')));
app.get('/admin', (req, res) => res.sendFile(path.join(__dirname, 'frontend/admin/index.html')));

app.get('*', (req, res) => res.sendFile(path.join(__dirname, 'frontend/index.html')));

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`🚀 Vision TV running on port ${PORT}`));
EOF

# passport.js (ИСПРАВЛЕНО - только Google)
mkdir -p backend/config
cat > backend/config/passport.js <<'EOF'
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const db = require('../database/init').db;

module.exports = function(passport) {
    passport.serializeUser((user, done) => done(null, user.id));
    passport.deserializeUser((id, done) => {
        db.get('SELECT id, username, email, role FROM users WHERE id = ?', [id], (err, user) => done(err, user));
    });

    if (process.env.GOOGLE_CLIENT_ID) {
        passport.use(new GoogleStrategy({
            clientID: process.env.GOOGLE_CLIENT_ID,
            clientSecret: process.env.GOOGLE_CLIENT_SECRET,
            callbackURL: process.env.GOOGLE_CALLBACK_URL
        }, (accessToken, refreshToken, profile, done) => {
            const email = profile.emails?.[0]?.value;
            const username = profile.displayName || email?.split('@')[0];
            
            db.get('SELECT * FROM users WHERE email = ?', [email], (err, user) => {
                if (err) return done(err);
                if (user) {
                    db.run('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?', [user.id]);
                    return done(null, user);
                }
                db.run(
                    'INSERT INTO users (username, email, provider, provider_id, role) VALUES (?, ?, ?, ?, ?)',
                    [username, email, 'google', profile.id, 'user'],
                    function(err) { if (err) return done(err); db.get('SELECT * FROM users WHERE id = ?', [this.lastID], done); }
                );
            });
        }));
    }
};
EOF

# database/init.js
mkdir -p backend/database
cat > backend/database/init.js <<'EOF'
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcryptjs');
const path = require('path');
const fs = require('fs');

const dbPath = process.env.DB_PATH || path.join(__dirname, '../../data/database.db');
fs.mkdirSync(path.dirname(dbPath), { recursive: true });
const db = new sqlite3.Database(dbPath);

function initialize() {
    db.serialize(() => {
        db.run(`CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT, email TEXT UNIQUE, password TEXT,
            provider TEXT, provider_id TEXT, role TEXT DEFAULT 'user',
            language TEXT DEFAULT 'ru', created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_login DATETIME, is_active INTEGER DEFAULT 1
        )`);
        db.run(`CREATE TABLE IF NOT EXISTS devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER, device_id TEXT UNIQUE, device_name TEXT, device_type TEXT,
            last_active DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )`);
        db.run(`CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY, name TEXT, url TEXT, type TEXT,
            status TEXT DEFAULT 'active', created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )`);
        db.run(`CREATE TABLE IF NOT EXISTS favorites (
            user_id INTEGER, channel_id TEXT,
            PRIMARY KEY(user_id, channel_id)
        )`);
        db.run(`CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)`);
        
        const adminEmail = process.env.ADMIN_EMAIL || 'admin@vision.tv';
        const adminPassword = process.env.ADMIN_PASSWORD || 'Admin123!';
        
        db.get('SELECT id FROM users WHERE role = ?', ['admin'], (err, row) => {
            if (!row) {
                const hash = bcrypt.hashSync(adminPassword, 10);
                db.run('INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)',
                    ['admin', adminEmail, hash, 'admin']);
                console.log(`✅ Admin: ${adminEmail} / ${adminPassword}`);
            }
        });
        
        db.run('INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)', ['max_devices', '3']);
    });
    console.log('📁 Database ready');
}

module.exports = { initialize, db };
EOF

# Routes
mkdir -p backend/routes

# auth.js
cat > backend/routes/auth.js <<'EOF'
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const passport = require('passport');
const router = express.Router();
const db = require('../database/init').db;

router.post('/register', async (req, res) => {
    const { username, email, password } = req.body;
    db.get('SELECT id FROM users WHERE email = ?', [email], async (err, row) => {
        if (row) return res.status(400).json({ error: 'User exists' });
        const hash = await bcrypt.hash(password, 10);
        db.run('INSERT INTO users (username, email, password) VALUES (?, ?, ?)', [username, email, hash],
            function(err) {
                if (err) return res.status(500).json({ error: 'DB error' });
                const token = jwt.sign({ id: this.lastID, username, email, role: 'user' }, process.env.JWT_SECRET, { expiresIn: '7d' });
                res.json({ token, user: { id: this.lastID, username, email, role: 'user' } });
            });
    });
});

router.post('/login', (req, res) => {
    const { email, password, deviceInfo } = req.body;
    db.get('SELECT * FROM users WHERE email = ?', [email], async (err, user) => {
        if (!user || !(await bcrypt.compare(password, user.password || ''))) return res.status(401).json({ error: 'Invalid credentials' });
        
        db.get('SELECT COUNT(*) as count FROM devices WHERE user_id = ?', [user.id], (e, r) => {
            if (r.count >= 3 && deviceInfo) {
                db.get('SELECT id FROM devices WHERE user_id = ? AND device_id = ?', [user.id, deviceInfo.deviceId], (e, d) => {
                    if (!d) return res.status(403).json({ error: 'DEVICE_LIMIT', max: 3 });
                    finalize();
                });
            } else finalize();
        });
        
        function finalize() {
            if (deviceInfo) db.run('INSERT OR REPLACE INTO devices (user_id, device_id, device_name, device_type) VALUES (?, ?, ?, ?)',
                [user.id, deviceInfo.deviceId, deviceInfo.name, deviceInfo.type]);
            const token = jwt.sign({ id: user.id, username: user.username, email: user.email, role: user.role }, process.env.JWT_SECRET, { expiresIn: '7d' });
            const { password, ...userData } = user;
            res.json({ token, user: userData });
        }
    });
});

router.get('/google', passport.authenticate('google', { scope: ['profile', 'email'] }));
router.get('/google/callback', passport.authenticate('google', { failureRedirect: '/login' }), (req, res) => res.redirect('/'));
router.post('/logout', (req, res) => { req.logout(() => res.json({ success: true })); });

module.exports = router;
EOF

# channels.js
cat > backend/routes/channels.js <<'EOF'
const express = require('express');
const axios = require('axios');
const router = express.Router();
const db = require('../database/init').db;

let scanStatus = { isScanning: true, progress: 0, total: 800, found: 0, tv: 0, radio: 0 };

async function backgroundScan() {
    for (let i = 1; i <= 800; i += 5) {
        const batch = [];
        for (let j = 0; j < 5 && i + j <= 800; j++) batch.push(i + j);
        
        await Promise.allSettled(batch.map(async id => {
            try {
                const r = await axios.get(`${process.env.API_BASE}/${id}`, { timeout: 3000 });
                const url = r.data?.data?.[0]?.threadAddress;
                if (url?.includes('.m3u8')) {
                    const name = url.match(/\/([^\/]+)\/playlist/)?.[1]?.replace(/_/g, ' ') || 'Channel';
                    const type = (name + url).toLowerCase().includes('radio') ? 'radio' : 'tv';
                    db.run('INSERT OR REPLACE INTO channels (id, name, url, type) VALUES (?, ?, ?, ?)', [String(id), name, url, type]);
                    scanStatus.found++;
                    type === 'tv' ? scanStatus.tv++ : scanStatus.radio++;
                }
            } catch (e) {}
        }));
        scanStatus.progress = Math.min(i + 4, 800);
        await new Promise(r => setTimeout(r, 100));
    }
    scanStatus.isScanning = false;
    console.log(`✅ Scan complete: ${scanStatus.found} channels`);
}

backgroundScan();

router.get('/', (req, res) => {
    db.all('SELECT * FROM channels WHERE status = ? ORDER BY name', ['active'], (err, rows) => {
        const channels = rows || [];
        res.json({
            channels,
            total: channels.length,
            tvTotal: channels.filter(c => c.type === 'tv').length,
            radioTotal: channels.filter(c => c.type === 'radio').length,
            scanning: scanStatus
        });
    });
});

router.get('/status', (req, res) => {
    db.all('SELECT type, COUNT(*) as count FROM channels WHERE status = ? GROUP BY type', ['active'], (err, rows) => {
        const stats = { tv: 0, radio: 0 };
        rows?.forEach(r => stats[r.type] = r.count);
        res.json({ ...scanStatus, dbTotal: stats.tv + stats.radio, dbTv: stats.tv, dbRadio: stats.radio });
    });
});

router.post('/scan', (req, res) => {
    if (!scanStatus.isScanning) { scanStatus = { isScanning: true, progress: 0, total: 800, found: 0, tv: 0, radio: 0 }; backgroundScan(); }
    res.json({ success: true });
});

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

router.get('/', (req, res) => db.all('SELECT * FROM devices WHERE user_id = ?', [req.user.id], (e, d) => res.json({ devices: d, max: 3 })));
router.delete('/:id', (req, res) => db.run('DELETE FROM devices WHERE user_id = ? AND device_id = ?', [req.user.id, req.params.id], () => res.json({ success: true })));

module.exports = router;
EOF

# admin.js
cat > backend/routes/admin.js <<'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const db = require('../database/init').db;

router.use((req, res, next) => {
    try { const u = jwt.verify(req.headers.authorization?.split(' ')[1], process.env.JWT_SECRET); if (u.role !== 'admin') throw 0; next(); }
    catch { res.status(403).json({ error: 'Admin only' }); }
});

router.get('/stats', (req, res) => {
    db.get('SELECT COUNT(*) as users FROM users', (e, u) => db.get('SELECT COUNT(*) as channels FROM channels', (e, c) => res.json({ users: u.users, channels: c.channels })));
});

module.exports = router;
EOF

# Frontend - index.html
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
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:'Inter',sans-serif;background:#0a0a0a;color:#fff}
        .header{position:sticky;top:0;z-index:100;background:#0f0f0f;padding:0 24px;height:70px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #222}
        .logo{font-size:24px;font-weight:700;color:#e50914}
        .nav{display:flex;gap:8px}
        .nav-btn{padding:10px 20px;background:transparent;border:none;color:#aaa;font-weight:500;border-radius:30px;cursor:pointer}
        .nav-btn.active{background:#e50914;color:#fff}
        .search-box{background:#1a1a1a;padding:10px 20px;border-radius:30px;display:flex;align-items:center;gap:10px}
        .search-box input{background:none;border:none;color:#fff;font-size:15px;outline:none;width:240px}
        .user-menu a{color:#aaa;text-decoration:none;margin-left:16px}
        .container{max-width:1400px;margin:0 auto;padding:30px 24px}
        .channels-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:20px}
        .channel-card{background:#141414;border-radius:16px;padding:20px;cursor:pointer;border:1px solid #2a2a2a;position:relative}
        .channel-card:hover{transform:translateY(-4px);border-color:#e50914}
        .card-badge{position:absolute;top:16px;right:16px;padding:4px 10px;border-radius:6px;font-size:11px;font-weight:700;background:#e50914}
        .card-icon{font-size:36px;margin-bottom:20px;color:#e50914}
        .player-modal{position:fixed;inset:0;background:rgba(0,0,0,0.95);z-index:1000;display:none;align-items:center;justify-content:center}
        .player-container{width:90%;max-width:1100px}
        #videoPlayer{width:100%;aspect-ratio:16/9;background:#000;border-radius:16px}
        .close-btn{position:absolute;top:-40px;right:0;background:rgba(255,255,255,0.1);border:none;color:#fff;width:40px;height:40px;border-radius:50%;cursor:pointer}
        .loading-spinner{width:48px;height:48px;border:3px solid #333;border-top-color:#e50914;border-radius:50%;animation:spin 1s linear infinite;margin:0 auto}
        @keyframes spin{to{transform:rotate(360deg)}}
    </style>
</head>
<body>
<header class="header">
    <div class="logo"><i class="fas fa-play"></i> Vision TV</div>
    <div class="nav">
        <button class="nav-btn active" data-cat="all">Все</button>
        <button class="nav-btn" data-cat="tv">ТВ</button>
        <button class="nav-btn" data-cat="radio">Радио</button>
    </div>
    <div class="search-box">
        <i class="fas fa-search"></i>
        <input type="text" id="searchInput" placeholder="Поиск...">
    </div>
    <div class="user-menu" id="authSection">
        <a href="/login">Войти</a>
        <a href="/register">Регистрация</a>
    </div>
</header>
<main class="container">
    <div class="channels-grid" id="channelGrid">
        <div style="grid-column:1/-1;text-align:center;padding:60px">
            <div class="loading-spinner"></div>
            <p style="color:#888;margin-top:20px">Загрузка...</p>
        </div>
    </div>
</main>
<div class="player-modal" id="playerModal">
    <div class="player-container">
        <button class="close-btn" onclick="closePlayer()"><i class="fas fa-times"></i></button>
        <video id="videoPlayer" controls playsinline></video>
    </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js"></script>
<script src="/js/app.js"></script>
<script src="/js/auth.js"></script>
</body>
</html>
EOF

# JS files
mkdir -p frontend/js

cat > frontend/js/auth.js <<'EOF'
class Auth{constructor(){this.token=localStorage.getItem('token');this.user=JSON.parse(localStorage.getItem('user')||'null');this.updateUI()}
updateUI(){const e=document.getElementById('authSection');if(!e)return;this.token?e.innerHTML=`<a href="/profile">${this.user?.username||'Профиль'}</a><a href="/devices">Устройства</a><a href="#" onclick="auth.logout()">Выйти</a>`:e.innerHTML='<a href="/login">Войти</a><a href="/register">Регистрация</a>'}
logout(){localStorage.clear();location.href='/'}}
const auth=new Auth();
EOF

cat > frontend/js/app.js <<'EOF'
let channels=[],hls=null,currentCat='all';
const grid=document.getElementById('channelGrid'),modal=document.getElementById('playerModal'),player=document.getElementById('videoPlayer');
async function load(){try{const r=await fetch('/api/channels'),d=await r.json();channels=d.channels||[];render()}catch(e){grid.innerHTML='<div style="grid-column:1/-1;text-align:center;padding:60px">Ошибка</div>'}}
function render(){let f=channels;if(currentCat==='tv')f=channels.filter(c=>c.type==='tv');if(currentCat==='radio')f=channels.filter(c=>c.type==='radio');const q=document.getElementById('searchInput')?.value.toLowerCase();if(q)f=f.filter(c=>c.name.toLowerCase().includes(q));grid.innerHTML=f.map(c=>`<div class="channel-card" onclick="play('${c.id}')"><span class="card-badge">${c.type==='tv'?'HD':'LIVE'}</span><div class="card-icon"><i class="fas fa-${c.type==='tv'?'tv':'radio'}"></i></div><div style="font-weight:600">${c.name}</div></div>`).join('')||'<div style="grid-column:1/-1;text-align:center;padding:60px">Нет каналов</div>'}
window.play=function(id){const c=channels.find(c=>c.id===id);if(!c)return;modal.style.display='flex';if(hls)hls.destroy();if(Hls.isSupported()){hls=new Hls();hls.loadSource(c.url);hls.attachMedia(player)}else player.src=c.url;player.play()}
window.closePlayer=function(){modal.style.display='none';if(hls)hls.destroy();player.pause()}
document.querySelectorAll('.nav-btn').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.nav-btn').forEach(x=>x.classList.remove('active'));b.classList.add('active');currentCat=b.dataset.cat;render()}));
document.getElementById('searchInput')?.addEventListener('input',render);
document.addEventListener('keydown',e=>{if(e.key==='Escape')closePlayer()});
load();
EOF

# Simple login/register pages
cat > frontend/login.html <<'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Вход - Vision TV</title><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"></head>
<body style="font-family:Inter,sans-serif;background:#0a0a0a;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh">
<div style="width:100%;max-width:400px;padding:40px;background:#141414;border-radius:24px">
<h1 style="text-align:center;margin-bottom:30px">Вход</h1>
<form id="loginForm">
<input type="email" name="email" placeholder="Email" required style="width:100%;padding:14px;background:#0a0a0a;border:1px solid #2a2a2a;border-radius:12px;color:#fff;margin-bottom:16px">
<input type="password" name="password" placeholder="Пароль" required style="width:100%;padding:14px;background:#0a0a0a;border:1px solid #2a2a2a;border-radius:12px;color:#fff;margin-bottom:16px">
<button type="submit" style="width:100%;padding:14px;background:#e50914;color:#fff;border:none;border-radius:12px;font-weight:600;cursor:pointer">Войти</button>
</form>
<a href="/auth/google" style="display:block;text-align:center;margin-top:16px;padding:14px;background:#fff;color:#000;border-radius:12px;text-decoration:none"><i class="fab fa-google"></i> Google</a>
<p style="text-align:center;margin-top:20px"><a href="/register" style="color:#e50914">Регистрация</a></p>
</div>
<script>
document.getElementById('loginForm').addEventListener('submit',async e=>{e.preventDefault();const d={email:e.target.email.value,password:e.target.password.value,deviceInfo:{deviceId:localStorage.deviceId||'web',name:'Web'}};const r=await fetch('/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)});if(r.ok){const data=await r.json();localStorage.setItem('token',data.token);localStorage.setItem('user',JSON.stringify(data.user));location.href='/'}else alert('Ошибка')});
</script>
</body></html>
EOF

cat > frontend/register.html <<'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Регистрация - Vision TV</title></head>
<body style="font-family:Inter,sans-serif;background:#0a0a0a;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh">
<div style="width:100%;max-width:400px;padding:40px;background:#141414;border-radius:24px">
<h1 style="text-align:center;margin-bottom:30px">Регистрация</h1>
<form id="registerForm">
<input type="text" name="username" placeholder="Имя" required style="width:100%;padding:14px;background:#0a0a0a;border:1px solid #2a2a2a;border-radius:12px;color:#fff;margin-bottom:16px">
<input type="email" name="email" placeholder="Email" required style="width:100%;padding:14px;background:#0a0a0a;border:1px solid #2a2a2a;border-radius:12px;color:#fff;margin-bottom:16px">
<input type="password" name="password" placeholder="Пароль" required style="width:100%;padding:14px;background:#0a0a0a;border:1px solid #2a2a2a;border-radius:12px;color:#fff;margin-bottom:16px">
<button type="submit" style="width:100%;padding:14px;background:#e50914;color:#fff;border:none;border-radius:12px;font-weight:600;cursor:pointer">Зарегистрироваться</button>
</form>
<p style="text-align:center;margin-top:20px"><a href="/login" style="color:#e50914">Войти</a></p>
</div>
<script>
document.getElementById('registerForm').addEventListener('submit',async e=>{e.preventDefault();const d={username:e.target.username.value,email:e.target.email.value,password:e.target.password.value};const r=await fetch('/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)});if(r.ok){const data=await r.json();localStorage.setItem('token',data.token);localStorage.setItem('user',JSON.stringify(data.user));location.href='/'}else alert('Ошибка')});
</script>
</body></html>
EOF

# Profile and devices
cat > frontend/profile.html <<'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Профиль - Vision TV</title></head>
<body style="font-family:Inter,sans-serif;background:#0a0a0a;color:#fff;padding:40px">
<header style="display:flex;justify-content:space-between;margin-bottom:40px"><h1>Профиль</h1><a href="/" style="color:#e50914">На главную</a></header>
<div style="max-width:600px;margin:0 auto;background:#141414;border-radius:24px;padding:40px">
<div id="profileInfo"></div>
<a href="/devices" style="display:block;margin-top:20px;padding:14px;background:#e50914;color:#fff;text-align:center;border-radius:12px;text-decoration:none">Устройства</a>
</div>
<script>
const user=JSON.parse(localStorage.getItem('user')||'{}');
if(!user.id)location.href='/login';
document.getElementById('profileInfo').innerHTML=`<p><strong>Имя:</strong> ${user.username}</p><p><strong>Email:</strong> ${user.email}</p><p><strong>Роль:</strong> ${user.role==='admin'?'Админ':'Пользователь'}</p>`;
</script>
</body></html>
EOF

cat > frontend/devices.html <<'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Устройства - Vision TV</title></head>
<body style="font-family:Inter,sans-serif;background:#0a0a0a;color:#fff;padding:40px">
<header style="display:flex;justify-content:space-between;margin-bottom:40px"><h1>Мои устройства</h1><a href="/" style="color:#e50914">На главную</a></header>
<div style="max-width:800px;margin:0 auto"><div id="devicesList"></div><p style="color:#888;margin-top:20px">Максимум 3 устройства</p></div>
<script>
const token=localStorage.getItem('token');
if(!token)location.href='/login';
async function load(){const r=await fetch('/api/devices',{headers:{'Authorization':`Bearer ${token}`}});const d=await r.json();document.getElementById('devicesList').innerHTML=d.devices?.map(d=>`<div style="background:#141414;border-radius:16px;padding:20px;margin-bottom:16px;display:flex;justify-content:space-between"><div><div style="font-weight:600">${d.device_name||'Устройство'}</div><div style="color:#888;font-size:13px">${new Date(d.last_active).toLocaleString()}</div></div><button onclick="remove('${d.device_id}')" style="background:none;border:1px solid #e50914;color:#e50914;padding:8px 16px;border-radius:20px;cursor:pointer">Удалить</button></div>`).join('')||'<p>Нет устройств</p>'}
async function remove(id){await fetch(`/api/devices/${id}`,{method:'DELETE',headers:{'Authorization':`Bearer ${token}`}});load()}
load();
</script>
</body></html>
EOF

# Admin page
mkdir -p frontend/admin
cat > frontend/admin/index.html <<'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Админ - Vision TV</title></head>
<body style="font-family:Inter,sans-serif;background:#0a0a0a;color:#fff;padding:40px">
<h1>🛠 Админ-панель</h1>
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:20px;margin:30px 0">
<div style="background:#141414;padding:30px;border-radius:16px;text-align:center"><div style="font-size:48px;color:#e50914" id="totalChannels">-</div>Каналов</div>
<div style="background:#141414;padding:30px;border-radius:16px;text-align:center"><div style="font-size:48px;color:#e50914" id="tvChannels">-</div>ТВ</div>
<div style="background:#141414;padding:30px;border-radius:16px;text-align:center"><div style="font-size:48px;color:#e50914" id="radioChannels">-</div>Радио</div>
</div>
<button onclick="scan()" style="background:#e50914;color:#fff;border:none;padding:12px 24px;border-radius:30px;cursor:pointer">Сканировать</button>
<script>
fetch('/api/channels/status').then(r=>r.json()).then(d=>{document.getElementById('totalChannels').textContent=d.dbTotal||0;document.getElementById('tvChannels').textContent=d.dbTv||0;document.getElementById('radioChannels').textContent=d.dbRadio||0});
function scan(){fetch('/api/channels/scan',{method:'POST'}).then(()=>alert('Запущено')).then(()=>location.reload())}
</script>
</body></html>
EOF

# Locales
mkdir -p frontend/locales
echo '{"home":"Главная"}' > frontend/locales/ru.json
echo '{"home":"Home"}' > frontend/locales/en.json
echo '{"home":"Bosh sahifa"}' > frontend/locales/uz.json
echo '{"home":"Асосӣ"}' > frontend/locales/tj.json

# Nginx
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
    }
}
EOF

ln -sf /etc/nginx/sites-available/vision-tv /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# SSL
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL 2>/dev/null || print_warning "SSL не настроен"

# Install and start
print_info "Установка npm пакетов..."
npm install

print_info "Инициализация БД..."
node -e "require('./backend/database/init').initialize()"

pm2 start server.js --name vision-tv
pm2 save
pm2 startup systemd 2>/dev/null || true

# Done
clear
print_header "╔═══════════════════════════════════════════════════════════╗"
print_header "║                   🎉 УСТАНОВКА ЗАВЕРШЕНА! 🎉                ║"
print_header "╚═══════════════════════════════════════════════════════════╝"
echo ""
print_success "Vision TV установлен!"
echo ""
print_info "🌐 Сайт: https://$DOMAIN"
print_info "🛠 Админ: https://$DOMAIN/admin"
print_info "👤 Логин: admin@$DOMAIN"
print_info "🔑 Пароль: $ADMIN_PASSWORD"
echo ""
print_info "📁 Данные: $INSTALL_DIR/admin_credentials.txt"
echo ""

echo "=== Vision TV ===" > $INSTALL_DIR/admin_credentials.txt
echo "Site: https://$DOMAIN" >> $INSTALL_DIR/admin_credentials.txt
echo "Admin: admin@$DOMAIN / $ADMIN_PASSWORD" >> $INSTALL_DIR/admin_credentials.txt