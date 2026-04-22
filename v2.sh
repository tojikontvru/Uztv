#!/bin/bash
#############################################################
# VISION TV - Complete Auto Installer
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
read -p "Yandex Client ID: " YANDEX_CLIENT_ID
read -p "Yandex Client Secret: " YANDEX_CLIENT_SECRET
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
echo "  🔑 Яндекс: ${YANDEX_CLIENT_ID:+✅}"
echo "  🔑 Google: ${GOOGLE_CLIENT_ID:+✅}"
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

YANDEX_CLIENT_ID=$YANDEX_CLIENT_ID
YANDEX_CLIENT_SECRET=$YANDEX_CLIENT_SECRET
YANDEX_CALLBACK_URL=https://$DOMAIN/api/auth/yandex/callback

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

# package.json
cat > package.json <<'EOF'
{
  "name": "vision-tv",
  "version": "4.0.0",
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
    "passport-yandex": "^1.0.4",
    "axios": "^1.5.0",
    "socket.io": "^4.6.2",
    "dotenv": "^16.3.1",
    "compression": "^1.7.4",
    "morgan": "^1.10.0",
    "hls.js": "^1.4.12",
    "plyr": "^3.7.8"
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
            scriptSrc: ["'self'", "'unsafe-inline'", "https://apis.google.com", "https://cdn.jsdelivr.net", "https://yastatic.net"],
            imgSrc: ["'self'", "data:", "https:", "https://avatars.yandex.net", "https://lh3.googleusercontent.com"],
            connectSrc: ["'self'", "https://api.mediabay.tv", "https://accounts.google.com", "https://oauth.yandex.ru"]
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
app.use('/node_modules', express.static(path.join(__dirname, 'node_modules')));
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

io.on('connection', (socket) => console.log('User connected:', socket.id));

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`🚀 Vision TV running on port ${PORT}`));
EOF

# passport.js
mkdir -p backend/config
cat > backend/config/passport.js <<'EOF'
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const YandexStrategy = require('passport-yandex').Strategy;
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
    
    db.get('SELECT * FROM users WHERE email = ?', [email], (err, user) => {
        if (err) return done(err);
        if (user) {
            db.run('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?', [user.id]);
            return done(null, user);
        }
        db.run(
            'INSERT INTO users (username, email, provider, provider_id, role) VALUES (?, ?, ?, ?, ?)',
            [username, email, provider, profile.id, 'user'],
            function(err) { if (err) return done(err); db.get('SELECT * FROM users WHERE id = ?', [this.lastID], done); }
        );
    });
}
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
router.get('/yandex', passport.authenticate('yandex'));
router.get('/yandex/callback', passport.authenticate('yandex', { failureRedirect: '/login' }), (req, res) => res.redirect('/'));
router.post('/logout', (req, res) => { req.logout(() => res.json({ success: true })); });

module.exports = router;
EOF

# channels.js (with background scan)
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

# Frontend files
mkdir -p frontend/locales frontend/admin

# Locales
echo '{"home":"Главная","tv":"ТВ","radio":"Радио","favorites":"Избранное","profile":"Профиль","devices":"Устройства","admin":"Админ","login":"Войти","register":"Регистрация","logout":"Выйти"}' > frontend/locales/ru.json
echo '{"home":"Home","tv":"TV","radio":"Radio","favorites":"Favorites","profile":"Profile","devices":"Devices","admin":"Admin","login":"Login","register":"Register","logout":"Logout"}' > frontend/locales/en.json
echo '{"home":"Bosh sahifa","tv":"TV","radio":"Radio","favorites":"Sevimlilar","profile":"Profil","devices":"Qurilmalar","admin":"Admin","login":"Kirish","register":"Roʻyxatdan oʻtish","logout":"Chiqish"}' > frontend/locales/uz.json
echo '{"home":"Асосӣ","tv":"ТВ","radio":"Радио","favorites":"Интихобшуда","profile":"Профил","devices":"Дастгоҳҳо","admin":"Админ","login":"Ворид","register":"Сабти ном","logout":"Баромад"}' > frontend/locales/tj.json

# Create a simple admin page
cat > frontend/admin/index.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Admin - Vision TV</title><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"></head>
<body style="font-family:Inter,sans-serif;background:#0a0a0a;color:#fff;padding:40px">
<h1><i class="fas fa-shield-alt"></i> Админ-панель</h1>
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:20px;margin:30px 0">
<div style="background:#141414;padding:30px;border-radius:16px;text-align:center"><div style="font-size:48px;color:#e50914" id="totalChannels">-</div>Всего каналов</div>
<div style="background:#141414;padding:30px;border-radius:16px;text-align:center"><div style="font-size:48px;color:#e50914" id="tvChannels">-</div>ТВ Каналов</div>
<div style="background:#141414;padding:30px;border-radius:16px;text-align:center"><div style="font-size:48px;color:#e50914" id="radioChannels">-</div>Радиостанций</div>
</div>
<button onclick="scan()" style="background:#e50914;color:#fff;border:none;padding:12px 24px;border-radius:30px;cursor:pointer"><i class="fas fa-search"></i> Сканировать</button>
<a href="/" style="color:#aaa;margin-left:20px">← На главную</a>
<script>
const token = localStorage.getItem('token');
fetch('/api/channels/status').then(r=>r.json()).then(d=>{
    document.getElementById('totalChannels').textContent = d.dbTotal||0;
    document.getElementById('tvChannels').textContent = d.dbTv||0;
    document.getElementById('radioChannels').textContent = d.dbRadio||0;
});
function scan(){ fetch('/api/channels/scan', {method:'POST'}).then(()=>alert('Сканирование запущено')).then(()=>location.reload()); }
</script>
</body></html>
EOF

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
npm install --legacy-peer-deps

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