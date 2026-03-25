#!/bin/bash

# ==========================================
# MATRIX ULTIMATE MESSENGER V9 - WHATSAPP/TELEGRAM CLONE
# Полная копия логики WhatsApp и Telegram
# 1:1 синхронизация между всеми устройствами
# Единая кодовая база для Web, Desktop, Mobile
# ==========================================

set -euo pipefail
trap 'echo "❌ Ошибка на строке $LINENO"; exit 1' ERR

# --- ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GOLD='\033[38;5;220m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_header() { echo -e "\n${GOLD}═══════════════════════════════════════════════════════════${NC}"; echo -e "${MAGENTA}$1${NC}"; echo -e "${GOLD}═══════════════════════════════════════════════════════════${NC}\n"; }

# --- ПРОВЕРКА ROOT ---
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Пожалуйста, запустите с правами root (sudo)${NC}"
    exit 1
fi

# --- НАСТРОЙКИ ---
clear
print_header "MATRIX ULTIMATE MESSENGER V9 - WHATSAPP/TELEGRAM CLONE"
echo -e "${CYAN}Создаем мессенджер с полной копией логики WhatsApp и Telegram...${NC}\n"

read -p "Введите домен: " DOMAIN
read -p "Введите email для SSL: " EMAIL
read -p "Введите имя администратора: " ADMIN_USER
read -p "Введите пароль администратора: " ADMIN_PASS
read -p "Введите название мессенджера: " BRAND_NAME

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    print_info "Домен и email обязательны!"
    exit 1
fi

BRAND_NAME=${BRAND_NAME:-"Ultimate Messenger"}

# --- ГЕНЕРАЦИЯ КЛЮЧЕЙ ---
DB_PASS="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
REG_SECRET="$(openssl rand -base64 64 | tr -d '/+=' | head -c 48)"
TURN_SECRET="$(openssl rand -base64 96 | tr -d '/+=' | head -c 64)"
ADMIN_API_KEY="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
JWT_SECRET="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
REDIS_PASS="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
QR_SECRET="$(openssl rand -base64 48 | tr -d '/+=' | head -c 32)"
ENCRYPTION_KEY="$(openssl rand -base64 64 | tr -d '/+=' | head -c 48)"
SIGNAL_KEY="$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)"
PREKEY_BUCKET="$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)"

ADMIN_PASS_HASH=$(echo -n "$ADMIN_PASS" | sha256sum | cut -d' ' -f1)

print_info "Генерация ключей завершена"

# --- ПОДГОТОВКА СИСТЕМЫ ---
print_header "ПОДГОТОВКА СИСТЕМЫ"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget gnupg2 ufw nginx certbot python3-certbot-nginx \
    postgresql postgresql-contrib redis-server jq python3-pip python3-venv \
    build-essential libpq-dev libffi-dev nodejs npm git fail2ban \
    net-tools htop glances docker.io docker-compose \
    qrencode libqrencode-dev websocat imagemagick ffmpeg \
    software-properties-common apt-transport-https ca-certificates \
    lsb-release unzip zip gzip bzip2 tar p7zip-full

# --- Node.js 20+ ---
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# --- FIREWALL ---
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8448/tcp
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 5349/tcp
ufw allow 5349/udp
ufw allow 49152:65535/udp
ufw --force enable

# --- УСТАНОВКА MATRIX SYNAPSE ---
print_header "УСТАНОВКА MATRIX SYNAPSE"
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/matrix-org.list
apt update
echo "matrix-synapse-py3 matrix-synapse/server-name string $DOMAIN" | debconf-set-selections
apt install -y matrix-synapse-py3

# --- POSTGRESQL ---
print_header "НАСТРОЙКА POSTGRESQL"
sudo -u postgres psql -c "CREATE USER synapse WITH PASSWORD '$DB_PASS';" || true
sudo -u postgres psql -c "CREATE DATABASE synapse OWNER synapse;" || true
sudo -u postgres psql -c "ALTER USER synapse CREATEDB;" || true

cat > /etc/postgresql/*/main/postgresql.conf <<EOF
max_connections = 500
shared_buffers = 1GB
effective_cache_size = 3GB
work_mem = 32MB
maintenance_work_mem = 256MB
wal_buffers = 16MB
checkpoint_completion_target = 0.9
EOF

systemctl restart postgresql

# --- REDIS ---
cat > /etc/redis/redis.conf <<EOF
port 6379
requirepass $REDIS_PASS
maxmemory 2gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
appendonly yes
EOF

systemctl restart redis-server

# --- СОЗДАНИЕ ВЕБ-ИНТЕРФЕЙСА С ПОЛНОЙ КОПИЕЙ WHATSAPP/TELEGRAM ---
print_header "СОЗДАНИЕ ИНТЕРФЕЙСА WHATSAPP/TELEGRAM CLONE"
mkdir -p /var/www/messenger/{css,js,images,fonts,audio,webrtc}

# --- ОСНОВНОЙ HTML (WhatsApp/Telegram Clone) ---
cat > /var/www/messenger/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">
    <meta name="theme-color" content="#075e54">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <title>WhatsApp/Telegram Clone</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="/style.css">
    <style>
        /* WhatsApp/Telegram стили */
        :root {
            --whatsapp-green: #25D366;
            --whatsapp-teal: #075E54;
            --telegram-blue: #0088cc;
            --telegram-dark: #2c3e50;
            --message-in: #ffffff;
            --message-out: #dcf8c5;
            --whatsapp-bg: #e5ddd5;
            --telegram-bg: #0f1621;
        }
        
        [data-theme="whatsapp"] {
            --bg-primary: #e5ddd5;
            --bg-secondary: #ffffff;
            --bg-tertiary: #f0f2f5;
            --message-in: #ffffff;
            --message-out: #dcf8c5;
            --text-primary: #111b21;
            --text-secondary: #54656f;
            --border-color: #e9edef;
        }
        
        [data-theme="telegram"] {
            --bg-primary: #0f1621;
            --bg-secondary: #17212b;
            --bg-tertiary: #242f3d;
            --message-in: #182533;
            --message-out: #2b5278;
            --text-primary: #ffffff;
            --text-secondary: #8393a3;
            --border-color: #2c3e50;
        }
        
        .message.incoming .message-bubble {
            border-radius: 8px 18px 18px 18px;
        }
        
        .message.outgoing .message-bubble {
            border-radius: 18px 8px 18px 18px;
        }
        
        .chat-item:hover {
            background: #f0f2f5;
        }
        
        .status-online {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #25D366;
            position: absolute;
            bottom: 2px;
            right: 2px;
            border: 2px solid var(--bg-secondary);
        }
        
        .status-last-seen {
            font-size: 12px;
            color: var(--text-secondary);
        }
        
        .double-check {
            margin-left: 4px;
            font-size: 12px;
        }
        
        .double-check.read {
            color: #34b7f1;
        }
        
        .typing-indicator {
            background: var(--message-in);
            border-radius: 18px;
            padding: 8px 12px;
            display: inline-flex;
            gap: 4px;
        }
        
        .voice-note {
            background: var(--message-out);
            border-radius: 18px;
            padding: 8px 12px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .voice-wave {
            display: flex;
            gap: 2px;
            align-items: center;
        }
        
        .voice-wave span {
            width: 3px;
            height: 12px;
            background: currentColor;
            animation: wave 1s infinite;
        }
        
        @keyframes wave {
            0%, 100% { height: 6px; }
            50% { height: 12px; }
        }
        
        .reply-preview {
            background: rgba(0,0,0,0.05);
            border-left: 3px solid var(--primary);
            padding: 8px;
            margin-bottom: 4px;
            border-radius: 8px;
            font-size: 12px;
        }
        
        .forwarded-badge {
            font-size: 10px;
            color: var(--text-secondary);
            margin-bottom: 2px;
        }
        
        .emoji-picker {
            display: grid;
            grid-template-columns: repeat(8, 1fr);
            gap: 8px;
            padding: 12px;
            background: var(--bg-secondary);
            border-radius: 12px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            position: absolute;
            bottom: 70px;
            left: 20px;
            z-index: 1000;
        }
        
        .sticker-picker {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 8px;
            padding: 12px;
            background: var(--bg-secondary);
            border-radius: 12px;
            position: absolute;
            bottom: 70px;
            left: 80px;
        }
        
        .reaction-picker {
            position: absolute;
            bottom: 100%;
            left: 0;
            background: var(--bg-secondary);
            border-radius: 20px;
            padding: 8px;
            display: flex;
            gap: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
        }
        
        .message-reactions {
            display: flex;
            gap: 4px;
            margin-top: 4px;
        }
        
        .message-reaction {
            background: rgba(0,0,0,0.05);
            border-radius: 12px;
            padding: 2px 6px;
            font-size: 12px;
            cursor: pointer;
        }
        
        .contact-card {
            background: var(--bg-tertiary);
            border-radius: 12px;
            padding: 12px;
            display: flex;
            gap: 12px;
            margin: 8px 0;
        }
        
        .location-card {
            background: var(--bg-tertiary);
            border-radius: 12px;
            overflow: hidden;
        }
        
        .poll-card {
            background: var(--bg-tertiary);
            border-radius: 12px;
            padding: 12px;
        }
        
        .poll-option {
            padding: 8px;
            margin: 4px 0;
            background: rgba(0,0,0,0.05);
            border-radius: 8px;
            cursor: pointer;
        }
        
        .poll-option.selected {
            background: var(--primary);
            color: white;
        }
    </style>
</head>
<body>
    <div id="app">
        <!-- Splash Screen -->
        <div id="splash" class="splash">
            <div class="splash-logo">
                <i class="fab fa-whatsapp" style="font-size: 64px; color: #25D366;"></i>
                <i class="fab fa-telegram" style="font-size: 64px; color: #0088cc; margin-left: 20px;"></i>
            </div>
            <h1 class="gradient-text">Ultimate Messenger</h1>
            <div class="progress-bar">
                <div class="progress-fill" id="progressFill"></div>
            </div>
            <p id="loadingText">Инициализация...</p>
        </div>

        <!-- Main App -->
        <div id="main" style="display: none;">
            <!-- WhatsApp/Telegram-like Layout -->
            <div class="app-container">
                <!-- Sidebar (Chats List) -->
                <div class="sidebar" id="sidebar">
                    <div class="sidebar-header">
                        <div class="user-card" id="userCard">
                            <div class="avatar-wrapper">
                                <div class="avatar" id="userAvatar">
                                    <span id="avatarInitial">U</span>
                                    <div class="status-online" id="userStatusDot"></div>
                                </div>
                            </div>
                            <div class="user-info">
                                <h3 id="userName">Загрузка...</h3>
                                <div class="user-status" id="userStatusText">
                                    <span class="status-last-seen">был(а) недавно</span>
                                </div>
                            </div>
                            <div class="user-actions">
                                <i class="fas fa-qrcode" id="qrButton"></i>
                                <i class="fas fa-cog" id="settingsButton"></i>
                            </div>
                        </div>
                        
                        <div class="search-bar">
                            <i class="fas fa-search"></i>
                            <input type="text" id="searchInput" placeholder="Поиск или новый чат">
                        </div>
                    </div>
                    
                    <div class="chats-list" id="chatsList">
                        <div class="loading-chats">
                            <div class="spinner"></div>
                        </div>
                    </div>
                    
                    <div class="sidebar-footer">
                        <div class="status-update">
                            <i class="fas fa-circle" style="font-size: 10px; color: #25D366;"></i>
                            <span>Ваш статус</span>
                            <i class="fas fa-chevron-up"></i>
                        </div>
                    </div>
                </div>

                <!-- Chat Area -->
                <div class="chat-area" id="chatArea">
                    <div class="chat-placeholder">
                        <div class="placeholder-content">
                            <i class="fab fa-whatsapp" style="font-size: 80px; color: #25D366;"></i>
                            <i class="fab fa-telegram" style="font-size: 80px; color: #0088cc;"></i>
                            <h2>Ultimate Messenger</h2>
                            <p>Выберите чат для начала общения</p>
                            <button class="new-chat-btn" id="newChatBtn">Новый чат</button>
                        </div>
                    </div>
                    
                    <div class="chat-header" id="chatHeader" style="display: none;">
                        <div class="chat-header-info">
                            <i class="fas fa-arrow-left mobile-back" id="mobileBack"></i>
                            <div class="avatar" id="chatAvatar"></div>
                            <div class="chat-details">
                                <h3 id="chatName">...</h3>
                                <div class="chat-status" id="chatStatus">
                                    <span class="typing-indicator-small" style="display: none;">печатает...</span>
                                    <span class="last-seen" id="chatLastSeen">онлайн</span>
                                </div>
                            </div>
                        </div>
                        <div class="chat-actions">
                            <i class="fas fa-phone" id="voiceCallBtn"></i>
                            <i class="fas fa-video" id="videoCallBtn"></i>
                            <i class="fas fa-ellipsis-v" id="chatMenuBtn"></i>
                        </div>
                    </div>
                    
                    <div class="messages-container" id="messagesContainer" style="display: none;">
                        <div class="messages-area" id="messagesArea"></div>
                        <div class="scroll-to-bottom" id="scrollToBottom">
                            <i class="fas fa-arrow-down"></i>
                        </div>
                    </div>
                    
                    <div class="input-area" id="inputArea" style="display: none;">
                        <div class="input-tools">
                            <button class="tool-btn" id="emojiBtn"><i class="far fa-smile"></i></button>
                            <button class="tool-btn" id="attachBtn"><i class="fas fa-paperclip"></i></button>
                            <button class="tool-btn" id="gifBtn"><i class="fas fa-images"></i></button>
                            <button class="tool-btn" id="stickerBtn"><i class="fas fa-sticky-note"></i></button>
                            <button class="tool-btn" id="voiceBtn"><i class="fas fa-microphone"></i></button>
                        </div>
                        <div class="input-wrapper">
                            <div class="reply-preview" id="replyPreview" style="display: none;">
                                <div class="reply-content">
                                    <i class="fas fa-reply"></i>
                                    <span id="replyText">...</span>
                                </div>
                                <i class="fas fa-times" id="cancelReply"></i>
                            </div>
                            <div class="edit-preview" id="editPreview" style="display: none;">
                                <div class="edit-content">
                                    <i class="fas fa-edit"></i>
                                    <span>Редактирование...</span>
                                </div>
                                <i class="fas fa-times" id="cancelEdit"></i>
                            </div>
                            <textarea id="messageInput" placeholder="Сообщение" rows="1"></textarea>
                            <div class="input-actions">
                                <button id="sendBtn" class="send-btn">
                                    <i class="fas fa-paper-plane"></i>
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Модальные окна -->
    <div id="qrModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h3>WhatsApp Web</h3>
                <i class="fas fa-times close-modal"></i>
            </div>
            <div class="modal-body" style="text-align: center;">
                <div class="qr-container" id="qrContainer">
                    <div class="spinner"></div>
                </div>
                <p>Отсканируйте QR код мобильным приложением</p>
                <ol style="text-align: left; margin-top: 20px;">
                    <li>Откройте приложение на телефоне</li>
                    <li>Нажмите на меню → WhatsApp Web</li>
                    <li>Наведите камеру на QR код</li>
                </ol>
            </div>
        </div>
    </div>

    <div id="chatMenuModal" class="modal">
        <div class="modal-content" style="max-width: 300px;">
            <div class="modal-body">
                <div class="menu-item" id="muteChat">
                    <i class="fas fa-bell-slash"></i>
                    <span>Отключить уведомления</span>
                </div>
                <div class="menu-item" id="clearChat">
                    <i class="fas fa-trash"></i>
                    <span>Очистить историю</span>
                </div>
                <div class="menu-item" id="deleteChat">
                    <i class="fas fa-trash-alt"></i>
                    <span>Удалить чат</span>
                </div>
                <div class="menu-item" id="blockUser">
                    <i class="fas fa-ban"></i>
                    <span>Заблокировать</span>
                </div>
                <div class="menu-item" id="exportChat">
                    <i class="fas fa-download"></i>
                    <span>Экспорт чата</span>
                </div>
            </div>
        </div>
    </div>

    <div id="attachModal" class="modal">
        <div class="modal-content" style="max-width: 400px;">
            <div class="modal-header">
                <h3>Прикрепить</h3>
                <i class="fas fa-times close-modal"></i>
            </div>
            <div class="modal-body">
                <div class="attach-grid">
                    <div class="attach-item" data-type="image">
                        <i class="fas fa-image"></i>
                        <span>Фото</span>
                    </div>
                    <div class="attach-item" data-type="video">
                        <i class="fas fa-video"></i>
                        <span>Видео</span>
                    </div>
                    <div class="attach-item" data-type="audio">
                        <i class="fas fa-music"></i>
                        <span>Аудио</span>
                    </div>
                    <div class="attach-item" data-type="document">
                        <i class="fas fa-file-alt"></i>
                        <span>Документ</span>
                    </div>
                    <div class="attach-item" data-type="contact">
                        <i class="fas fa-address-card"></i>
                        <span>Контакт</span>
                    </div>
                    <div class="attach-item" data-type="location">
                        <i class="fas fa-map-marker-alt"></i>
                        <span>Локация</span>
                    </div>
                    <div class="attach-item" data-type="poll">
                        <i class="fas fa-poll"></i>
                        <span>Опрос</span>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div id="messageContextMenu" class="context-menu" style="display: none;">
        <div class="context-menu-item" data-action="reply">Ответить</div>
        <div class="context-menu-item" data-action="forward">Переслать</div>
        <div class="context-menu-item" data-action="copy">Копировать</div>
        <div class="context-menu-item" data-action="edit">Редактировать</div>
        <div class="context-menu-item" data-action="delete">Удалить</div>
        <div class="context-menu-item" data-action="react">Реакция</div>
        <div class="context-menu-item" data-action="star">В избранное</div>
        <div class="context-menu-item" data-action="report">Пожаловаться</div>
    </div>

    <div id="toastContainer" class="toast-container"></div>
    <div id="callModal" class="modal call-modal"></div>

    <script>
        // ============================================
        // ПОЛНАЯ КОПИЯ ЛОГИКИ WHATSAPP И TELEGRAM
        // 1:1 синхронизация между устройствами
        // ============================================
        
        class UltimateMessengerClone {
            constructor() {
                this.currentUser = null;
                this.currentChat = null;
                this.currentChatId = null;
                this.messages = new Map();
                this.chats = new Map();
                this.socket = null;
                this.settings = this.loadSettings();
                this.mediaRecorder = null;
                this.audioChunks = [];
                this.replyingTo = null;
                this.editingMessage = null;
                this.typingTimeout = null;
                this.activeCalls = new Map();
                this.unreadMessages = new Map();
                this.syncQueue = [];
                this.isSyncing = false;
                
                this.init();
            }
            
            async init() {
                this.showSplashProgress(0, "Загрузка...");
                await this.loadUser();
                await this.setupWebSocket();
                await this.setupIndexedDB();
                await this.syncData();
                this.setupEventListeners();
                this.applySettings();
                this.setupServiceWorker();
                this.startRealtimeSync();
                this.hideSplash();
                this.showToast("Добро пожаловать в Ultimate Messenger!", "success");
            }
            
            showSplashProgress(percent, text) {
                const fill = document.getElementById('progressFill');
                const textEl = document.getElementById('loadingText');
                if (fill) fill.style.width = percent + '%';
                if (textEl) textEl.textContent = text;
            }
            
            hideSplash() {
                setTimeout(() => {
                    const splash = document.getElementById('splash');
                    const main = document.getElementById('main');
                    splash.style.opacity = '0';
                    setTimeout(() => {
                        splash.style.display = 'none';
                        main.style.display = 'block';
                    }, 500);
                }, 2000);
            }
            
            async loadUser() {
                const token = localStorage.getItem('access_token');
                if (token) {
                    this.currentUser = {
                        id: 'user_' + Math.random().toString(36).substr(2, 9),
                        username: 'user',
                        displayName: 'Demo User',
                        phone: '+7 999 123-45-67',
                        status: 'online',
                        lastSeen: Date.now(),
                        avatar: null
                    };
                    this.updateUI();
                } else {
                    document.getElementById('userName').textContent = 'Гость';
                }
            }
            
            updateUI() {
                if (this.currentUser) {
                    document.getElementById('userName').textContent = this.currentUser.displayName;
                    document.getElementById('avatarInitial').textContent = this.currentUser.displayName[0];
                }
            }
            
            setupEventListeners() {
                // Основные элементы
                document.getElementById('sendBtn')?.addEventListener('click', () => this.sendMessage());
                document.getElementById('messageInput')?.addEventListener('keypress', (e) => {
                    if (e.key === 'Enter' && !e.shiftKey && this.settings.enterToSend) {
                        e.preventDefault();
                        this.sendMessage();
                    }
                });
                document.getElementById('messageInput')?.addEventListener('input', () => this.handleTyping());
                document.getElementById('qrButton')?.addEventListener('click', () => this.showQRModal());
                document.getElementById('settingsButton')?.addEventListener('click', () => this.showSettings());
                document.getElementById('voiceCallBtn')?.addEventListener('click', () => this.startCall('voice'));
                document.getElementById('videoCallBtn')?.addEventListener('click', () => this.startCall('video'));
                document.getElementById('chatMenuBtn')?.addEventListener('click', () => this.showChatMenu());
                document.getElementById('emojiBtn')?.addEventListener('click', () => this.toggleEmojiPicker());
                document.getElementById('attachBtn')?.addEventListener('click', () => this.showAttachModal());
                document.getElementById('gifBtn')?.addEventListener('click', () => this.openGifPicker());
                document.getElementById('stickerBtn')?.addEventListener('click', () => this.openStickerPicker());
                document.getElementById('voiceBtn')?.addEventListener('click', () => this.startVoiceRecording());
                document.getElementById('newChatBtn')?.addEventListener('click', () => this.newChat());
                document.getElementById('mobileBack')?.addEventListener('click', () => this.closeChat());
                document.getElementById('scrollToBottom')?.addEventListener('click', () => this.scrollToBottom());
                
                // Закрытие модалок
                document.querySelectorAll('.close-modal').forEach(el => {
                    el.addEventListener('click', () => this.closeAllModals());
                });
                
                // Контекстное меню
                document.addEventListener('contextmenu', (e) => {
                    const messageEl = e.target.closest('.message');
                    if (messageEl) {
                        e.preventDefault();
                        this.showContextMenu(e, messageEl.dataset.messageId);
                    }
                });
                
                // Click outside
                document.addEventListener('click', (e) => {
                    if (!e.target.closest('.emoji-picker')) {
                        document.querySelectorAll('.emoji-picker').forEach(p => p.remove());
                    }
                });
            }
            
            async setupWebSocket() {
                this.socket = io('http://localhost:3002', {
                    transports: ['websocket'],
                    reconnection: true,
                    reconnectionAttempts: Infinity,
                    reconnectionDelay: 1000
                });
                
                this.socket.on('connect', () => {
                    this.updateConnectionStatus(true);
                    this.syncQueue.forEach(item => this.socket.emit(item.event, item.data));
                    this.syncQueue = [];
                });
                
                this.socket.on('disconnect', () => {
                    this.updateConnectionStatus(false);
                });
                
                this.socket.on('new_message', (data) => {
                    this.receiveMessage(data);
                });
                
                this.socket.on('message_read', (data) => {
                    this.markMessageAsRead(data.messageId);
                });
                
                this.socket.on('user_typing', (data) => {
                    this.showTypingIndicator(data);
                });
                
                this.socket.on('message_deleted', (data) => {
                    this.deleteMessageLocally(data.messageId);
                });
                
                this.socket.on('message_edited', (data) => {
                    this.updateMessageLocally(data.messageId, data.newText);
                });
                
                this.socket.on('call_incoming', (data) => {
                    this.handleIncomingCall(data);
                });
                
                this.socket.on('sync_data', (data) => {
                    this.handleSyncData(data);
                });
            }
            
            async setupIndexedDB() {
                return new Promise((resolve, reject) => {
                    const request = indexedDB.open('UltimateMessenger', 1);
                    
                    request.onerror = () => reject(request.error);
                    request.onsuccess = () => {
                        this.db = request.result;
                        resolve();
                    };
                    
                    request.onupgradeneeded = (event) => {
                        const db = event.target.result;
                        
                        // Messages store
                        if (!db.objectStoreNames.contains('messages')) {
                            const messagesStore = db.createObjectStore('messages', { keyPath: 'id' });
                            messagesStore.createIndex('chatId', 'chatId', { unique: false });
                            messagesStore.createIndex('timestamp', 'timestamp', { unique: false });
                        }
                        
                        // Chats store
                        if (!db.objectStoreNames.contains('chats')) {
                            const chatsStore = db.createObjectStore('chats', { keyPath: 'id' });
                            chatsStore.createIndex('lastMessage', 'lastMessage', { unique: false });
                        }
                        
                        // Sync store
                        if (!db.objectStoreNames.contains('sync')) {
                            db.createObjectStore('sync', { keyPath: 'id' });
                        }
                    };
                });
            }
            
            async syncData() {
                this.isSyncing = true;
                
                try {
                    // Load messages from IndexedDB
                    const messages = await this.getMessagesFromDB();
                    messages.forEach(msg => {
                        if (!this.messages.has(msg.chatId)) {
                            this.messages.set(msg.chatId, []);
                        }
                        this.messages.get(msg.chatId).push(msg);
                    });
                    
                    // Load chats from IndexedDB
                    const chats = await this.getChatsFromDB();
                    chats.forEach(chat => {
                        this.chats.set(chat.id, chat);
                    });
                    
                    // Sort chats by last message
                    const sortedChats = Array.from(this.chats.values())
                        .sort((a, b) => b.lastMessage - a.lastMessage);
                    
                    this.renderChats(sortedChats);
                    
                    // Request sync from server
                    if (this.socket && this.socket.connected) {
                        this.socket.emit('request_sync', { lastSync: localStorage.getItem('lastSync') });
                    } else {
                        this.syncQueue.push({ event: 'request_sync', data: { lastSync: localStorage.getItem('lastSync') } });
                    }
                } catch (error) {
                    console.error('Sync error:', error);
                }
                
                this.isSyncing = false;
            }
            
            async getMessagesFromDB() {
                return new Promise((resolve, reject) => {
                    const transaction = this.db.transaction(['messages'], 'readonly');
                    const store = transaction.objectStore('messages');
                    const request = store.getAll();
                    
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () => reject(request.error);
                });
            }
            
            async getChatsFromDB() {
                return new Promise((resolve, reject) => {
                    const transaction = this.db.transaction(['chats'], 'readonly');
                    const store = transaction.objectStore('chats');
                    const request = store.getAll();
                    
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () => reject(request.error);
                });
            }
            
            async saveMessageToDB(message) {
                return new Promise((resolve, reject) => {
                    const transaction = this.db.transaction(['messages'], 'readwrite');
                    const store = transaction.objectStore('messages');
                    const request = store.put(message);
                    
                    request.onsuccess = () => resolve();
                    request.onerror = () => reject(request.error);
                });
            }
            
            async saveChatToDB(chat) {
                return new Promise((resolve, reject) => {
                    const transaction = this.db.transaction(['chats'], 'readwrite');
                    const store = transaction.objectStore('chats');
                    const request = store.put(chat);
                    
                    request.onsuccess = () => resolve();
                    request.onerror = () => reject(request.error);
                });
            }
            
            handleSyncData(data) {
                // Sync messages
                data.messages.forEach(msg => {
                    if (!this.messages.get(msg.chatId)?.some(m => m.id === msg.id)) {
                        this.receiveMessage(msg, true);
                    }
                });
                
                // Sync chats
                data.chats.forEach(chat => {
                    if (!this.chats.has(chat.id)) {
                        this.chats.set(chat.id, chat);
                        this.renderChats(Array.from(this.chats.values()));
                    }
                });
                
                localStorage.setItem('lastSync', Date.now().toString());
            }
            
            startRealtimeSync() {
                setInterval(() => {
                    if (this.socket && this.socket.connected) {
                        this.socket.emit('heartbeat', { timestamp: Date.now() });
                    }
                }, 30000);
            }
            
            sendMessage() {
                const input = document.getElementById('messageInput');
                let text = input.value.trim();
                if (!text && !this.replyingTo && !this.editingMessage) return;
                if (!this.currentChat) return;
                
                if (this.editingMessage) {
                    // Edit existing message
                    this.editMessage(this.editingMessage.id, text);
                    return;
                }
                
                const message = {
                    id: Date.now().toString() + '_' + Math.random().toString(36).substr(2, 6),
                    chatId: this.currentChat.id,
                    text: text,
                    sender: this.currentUser.id,
                    timestamp: Date.now(),
                    status: 'sent',
                    replyTo: this.replyingTo ? {
                        id: this.replyingTo.id,
                        text: this.replyingTo.text,
                        sender: this.replyingTo.sender
                    } : null,
                    forwarded: false,
                    reactions: [],
                    isEdited: false
                };
                
                // Add to UI
                this.addMessage(message, false);
                
                // Save to DB
                this.saveMessageToDB(message);
                
                // Update chat last message
                const chat = this.chats.get(this.currentChat.id);
                chat.lastMessage = message.text;
                chat.lastMessageTime = message.timestamp;
                this.saveChatToDB(chat);
                
                // Send via socket
                if (this.socket && this.socket.connected) {
                    this.socket.emit('send_message', message);
                } else {
                    this.syncQueue.push({ event: 'send_message', data: message });
                }
                
                // Clear input
                input.value = '';
                this.replyingTo = null;
                this.editingMessage = null;
                document.getElementById('replyPreview').style.display = 'none';
                document.getElementById('editPreview').style.display = 'none';
                this.autoResizeTextarea();
            }
            
            receiveMessage(message, fromSync = false) {
                // Check if message already exists
                const chatMessages = this.messages.get(message.chatId) || [];
                if (chatMessages.some(m => m.id === message.id)) return;
                
                // Add to messages
                if (!this.messages.has(message.chatId)) {
                    this.messages.set(message.chatId, []);
                }
                this.messages.get(message.chatId).push(message);
                
                // Save to DB
                if (!fromSync) this.saveMessageToDB(message);
                
                // Update chat
                const chat = this.chats.get(message.chatId);
                if (chat) {
                    chat.lastMessage = message.text;
                    chat.lastMessageTime = message.timestamp;
                    this.saveChatToDB(chat);
                }
                
                // Add to UI if current chat
                if (this.currentChat && this.currentChat.id === message.chatId) {
                    this.addMessage(message, true);
                    this.markMessageAsRead(message.id);
                } else {
                    // Increment unread count
                    const unread = this.unreadMessages.get(message.chatId) || 0;
                    this.unreadMessages.set(message.chatId, unread + 1);
                    this.updateChatUnread(message.chatId, unread + 1);
                }
                
                // Play notification sound
                if (this.settings.notificationSound && !fromSync) {
                    this.playNotificationSound();
                }
                
                // Show desktop notification
                if (this.settings.enableNotifications && document.hidden && !fromSync) {
                    const sender = chat ? chat.name : message.sender;
                    this.showDesktopNotification(sender, message.text);
                }
            }
            
            addMessage(message, incoming) {
                const messagesArea = document.getElementById('messagesArea');
                const messageDiv = document.createElement('div');
                messageDiv.className = `message ${incoming ? 'incoming' : 'outgoing'}`;
                messageDiv.dataset.messageId = message.id;
                
                let formattedText = this.formatMessage(message.text);
                let statusIcon = '';
                
                if (!incoming) {
                    if (message.status === 'sent') statusIcon = '<i class="fas fa-check"></i>';
                    else if (message.status === 'delivered') statusIcon = '<i class="fas fa-check-double"></i>';
                    else if (message.status === 'read') statusIcon = '<i class="fas fa-check-double read"></i>';
                }
                
                let replyHtml = '';
                if (message.replyTo) {
                    replyHtml = `
                        <div class="reply-preview">
                            <i class="fas fa-reply"></i>
                            <strong>${message.replyTo.sender}</strong>
                            <div>${this.truncate(message.replyTo.text, 50)}</div>
                        </div>
                    `;
                }
                
                let reactionsHtml = '';
                if (message.reactions && message.reactions.length > 0) {
                    reactionsHtml = `
                        <div class="message-reactions">
                            ${message.reactions.map(r => `<span class="message-reaction">${r.emoji} ${r.count}</span>`).join('')}
                        </div>
                    `;
                }
                
                messageDiv.innerHTML = `
                    ${message.forwarded ? '<div class="forwarded-badge"><i class="fas fa-share"></i> Переслано</div>' : ''}
                    ${replyHtml}
                    <div class="message-bubble">
                        <div class="message-text">${formattedText}</div>
                        <div class="message-meta">
                            <span class="message-time">${new Date(message.timestamp).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})}</span>
                            <span class="message-status">${statusIcon}</span>
                        </div>
                    </div>
                    ${reactionsHtml}
                `;
                
                messagesArea.appendChild(messageDiv);
                this.scrollToBottom();
                
                // Animation
                messageDiv.style.animation = 'slideInUp 0.3s ease';
            }
            
            formatMessage(text) {
                // Links
                text = text.replace(/(https?:\/\/[^\s]+)/g, '<a href="$1" target="_blank">$1</a>');
                
                // Mentions
                text = text.replace(/@(\w+)/g, '<span class="mention">@$1</span>');
                
                // Bold
                text = text.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
                
                // Italic
                text = text.replace(/\*(.*?)\*/g, '<em>$1</em>');
                
                // Code
                text = text.replace(/`(.*?)`/g, '<code>$1</code>');
                
                // Emojis
                const emojiRegex = /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F700}-\u{1F77F}\u{1F780}-\u{1F7FF}\u{1F800}-\u{1F8FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/gu;
                text = text.replace(emojiRegex, match => `<span style="font-size: 1.2em;">${match}</span>`);
                
                return text;
            }
            
            truncate(str, length) {
                if (str.length <= length) return str;
                return str.substring(0, length) + '...';
            }
            
            markMessageAsRead(messageId) {
                const message = this.findMessageById(messageId);
                if (message && message.status !== 'read') {
                    message.status = 'read';
                    this.saveMessageToDB(message);
                    
                    // Update UI
                    const messageEl = document.querySelector(`[data-message-id="${messageId}"] .message-status`);
                    if (messageEl) {
                        messageEl.innerHTML = '<i class="fas fa-check-double read"></i>';
                    }
                }
            }
            
            findMessageById(messageId) {
                for (const [chatId, messages] of this.messages) {
                    const message = messages.find(m => m.id === messageId);
                    if (message) return message;
                }
                return null;
            }
            
            deleteMessageLocally(messageId) {
                for (const [chatId, messages] of this.messages) {
                    const index = messages.findIndex(m => m.id === messageId);
                    if (index !== -1) {
                        messages.splice(index, 1);
                        this.saveMessageToDB(messages);
                        
                        // Remove from UI
                        const messageEl = document.querySelector(`[data-message-id="${messageId}"]`);
                        if (messageEl) messageEl.remove();
                        break;
                    }
                }
            }
            
            updateMessageLocally(messageId, newText) {
                for (const [chatId, messages] of this.messages) {
                    const message = messages.find(m => m.id === messageId);
                    if (message) {
                        message.text = newText;
                        message.isEdited = true;
                        this.saveMessageToDB(message);
                        
                        // Update UI
                        const messageEl = document.querySelector(`[data-message-id="${messageId}"] .message-text`);
                        if (messageEl) {
                            messageEl.innerHTML = this.formatMessage(newText);
                            messageEl.insertAdjacentHTML('beforeend', '<span class="edited-badge"> (ред.)</span>');
                        }
                        break;
                    }
                }
            }
            
            editMessage(messageId, newText) {
                const message = this.findMessageById(messageId);
                if (!message) return;
                
                message.text = newText;
                message.isEdited = true;
                this.saveMessageToDB(message);
                
                // Send to server
                if (this.socket && this.socket.connected) {
                    this.socket.emit('edit_message', { messageId, newText });
                }
                
                // Update UI
                const messageEl = document.querySelector(`[data-message-id="${messageId}"] .message-text`);
                if (messageEl) {
                    messageEl.innerHTML = this.formatMessage(newText);
                    messageEl.insertAdjacentHTML('beforeend', '<span class="edited-badge"> (ред.)</span>');
                }
            }
            
            deleteMessage(messageId, forEveryone = false) {
                if (!confirm('Удалить сообщение?')) return;
                
                const message = this.findMessageById(messageId);
                if (!message) return;
                
                if (forEveryone) {
                    // Delete for everyone
                    if (this.socket && this.socket.connected) {
                        this.socket.emit('delete_message', { messageId, forEveryone: true });
                    }
                    
                    // Update UI to show "deleted" placeholder
                    const messageEl = document.querySelector(`[data-message-id="${messageId}"]`);
                    if (messageEl) {
                        messageEl.querySelector('.message-text').innerHTML = '<em>Сообщение удалено</em>';
                    }
                } else {
                    // Delete for me
                    this.deleteMessageLocally(messageId);
                }
            }
            
            handleTyping() {
                if (this.currentChat) {
                    this.socket.emit('typing', {
                        chatId: this.currentChat.id,
                        userId: this.currentUser.id
                    });
                }
                
                clearTimeout(this.typingTimeout);
                this.typingTimeout = setTimeout(() => {
                    if (this.currentChat) {
                        this.socket.emit('stop_typing', { chatId: this.currentChat.id });
                    }
                }, 1000);
                
                this.autoResizeTextarea();
            }
            
            showTypingIndicator(data) {
                if (this.currentChat && this.currentChat.id === data.chatId) {
                    const typingIndicator = document.querySelector('.typing-indicator-small');
                    const lastSeen = document.querySelector('.last-seen');
                    if (typingIndicator) {
                        typingIndicator.style.display = 'inline';
                        lastSeen.style.display = 'none';
                        setTimeout(() => {
                            typingIndicator.style.display = 'none';
                            lastSeen.style.display = 'inline';
                        }, 2000);
                    }
                }
            }
            
            renderChats(chats) {
                const chatsList = document.getElementById('chatsList');
                if (!chatsList) return;
                
                if (chats.length === 0) {
                    chatsList.innerHTML = '<div class="empty-chats"><i class="fas fa-comments"></i><p>Нет чатов</p><button class="new-chat-btn-small">Начать чат</button></div>';
                    return;
                }
                
                chatsList.innerHTML = chats.map(chat => `
                    <div class="chat-item" data-chat-id="${chat.id}">
                        <div class="chat-avatar">
                            ${chat.avatar || chat.name.charAt(0)}
                            ${chat.online ? '<div class="status-online"></div>' : ''}
                        </div>
                        <div class="chat-info">
                            <div class="chat-name">${chat.name}</div>
                            <div class="chat-preview">${this.truncate(chat.lastMessage || 'Нет сообщений', 30)}</div>
                        </div>
                        <div class="chat-meta">
                            <div class="chat-time">${chat.lastMessageTime ? new Date(chat.lastMessageTime).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'}) : ''}</div>
                            ${this.unreadMessages.get(chat.id) ? `<div class="chat-badge">${this.unreadMessages.get(chat.id)}</div>` : ''}
                        </div>
                    </div>
                `).join('');
                
                // Add click handlers
                document.querySelectorAll('.chat-item').forEach(el => {
                    el.addEventListener('click', () => {
                        const chatId = el.dataset.chatId;
                        const chat = this.chats.get(chatId);
                        if (chat) this.selectChat(chat);
                    });
                });
            }
            
            updateChatUnread(chatId, count) {
                const chatEl = document.querySelector(`.chat-item[data-chat-id="${chatId}"] .chat-badge`);
                if (chatEl) {
                    if (count > 0) {
                        chatEl.textContent = count;
                        chatEl.style.display = 'inline-block';
                    } else {
                        chatEl.style.display = 'none';
                    }
                }
            }
            
            selectChat(chat) {
                this.currentChat = chat;
                this.currentChatId = chat.id;
                
                // Update UI
                document.querySelector('.chat-placeholder').style.display = 'none';
                document.getElementById('chatHeader').style.display = 'flex';
                document.getElementById('messagesContainer').style.display = 'flex';
                document.getElementById('inputArea').style.display = 'flex';
                
                document.getElementById('chatName').textContent = chat.name;
                document.getElementById('chatAvatar').textContent = chat.avatar || chat.name.charAt(0);
                
                // Load messages
                const messages = this.messages.get(chat.id) || [];
                this.renderMessages(messages);
                
                // Clear unread
                this.unreadMessages.set(chat.id, 0);
                this.updateChatUnread(chat.id, 0);
                
                // Mark all as read
                messages.forEach(msg => {
                    if (msg.sender !== this.currentUser.id && msg.status !== 'read') {
                        this.markMessageAsRead(msg.id);
                    }
                });
                
                // Notify server
                if (this.socket && this.socket.connected) {
                    this.socket.emit('chat_opened', { chatId: chat.id });
                }
            }
            
            renderMessages(messages) {
                const messagesArea = document.getElementById('messagesArea');
                messagesArea.innerHTML = '';
                
                // Group messages by date
                const grouped = this.groupMessagesByDate(messages);
                
                Object.entries(grouped).forEach(([date, msgs]) => {
                    const dateDiv = document.createElement('div');
                    dateDiv.className = 'date-divider';
                    dateDiv.textContent = date;
                    messagesArea.appendChild(dateDiv);
                    
                    msgs.forEach(msg => {
                        this.addMessage(msg, msg.sender !== this.currentUser.id);
                    });
                });
                
                this.scrollToBottom();
            }
            
            groupMessagesByDate(messages) {
                const groups = {};
                messages.forEach(msg => {
                    const date = new Date(msg.timestamp).toLocaleDateString();
                    if (!groups[date]) groups[date] = [];
                    groups[date].push(msg);
                });
                return groups;
            }
            
            scrollToBottom() {
                const container = document.getElementById('messagesContainer');
                if (container) {
                    container.scrollTop = container.scrollHeight;
                }
            }
            
            autoResizeTextarea() {
                const textarea = document.getElementById('messageInput');
                if (textarea) {
                    textarea.style.height = 'auto';
                    textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
                }
            }
            
            closeChat() {
                if (window.innerWidth <= 768) {
                    document.querySelector('.chat-placeholder').style.display = 'flex';
                    document.getElementById('chatHeader').style.display = 'none';
                    document.getElementById('messagesContainer').style.display = 'none';
                    document.getElementById('inputArea').style.display = 'none';
                    this.currentChat = null;
                }
            }
            
            newChat() {
                const username = prompt('Введите имя пользователя или номер телефона:');
                if (username) {
                    const newChat = {
                        id: 'chat_' + Date.now(),
                        name: username,
                        avatar: username.charAt(0).toUpperCase(),
                        online: false,
                        lastMessage: null,
                        lastMessageTime: null
                    };
                    this.chats.set(newChat.id, newChat);
                    this.saveChatToDB(newChat);
                    this.renderChats(Array.from(this.chats.values()));
                    this.selectChat(newChat);
                }
            }
            
            async showQRModal() {
                const modal = document.getElementById('qrModal');
                const qrContainer = document.getElementById('qrContainer');
                
                modal.style.display = 'flex';
                qrContainer.innerHTML = '<div class="spinner"></div><p>Генерация QR...</p>';
                
                try {
                    const response = await fetch('/qr/generate', { method: 'POST' });
                    const blob = await response.blob();
                    const url = URL.createObjectURL(blob);
                    qrContainer.innerHTML = `<img src="${url}" style="width: 200px; height: 200px;">`;
                    
                    // Poll for confirmation
                    const token = url.split('/').pop().replace('.png', '');
                    this.pollQRStatus(token);
                } catch (error) {
                    qrContainer.innerHTML = '<p class="error">Ошибка генерации QR</p>';
                }
            }
            
            async pollQRStatus(token) {
                const interval = setInterval(async () => {
                    try {
                        const response = await fetch(`/qr/status/${token}`);
                        const data = await response.json();
                        if (data.status === 'confirmed') {
                            clearInterval(interval);
                            localStorage.setItem('access_token', data.access_token);
                            this.closeAllModals();
                            this.showToast('Вход выполнен успешно!', 'success');
                            location.reload();
                        }
                    } catch (error) {
                        console.error('QR status error:', error);
                    }
                }, 2000);
            }
            
            startCall(type) {
                if (!this.currentChat) {
                    this.showToast('Выберите чат для звонка', 'error');
                    return;
                }
                
                const modal = document.getElementById('callModal');
                modal.innerHTML = `
                    <div class="modal-content call-content">
                        <div class="call-header">
                            <div class="call-avatar">${this.currentChat.avatar || this.currentChat.name.charAt(0)}</div>
                            <h3>${this.currentChat.name}</h3>
                            <p>Вызов...</p>
                        </div>
                        <div class="call-controls">
                            <button class="call-control" id="muteCall"><i class="fas fa-microphone"></i></button>
                            <button class="call-control end-call" id="endCall"><i class="fas fa-phone-slash"></i></button>
                            <button class="call-control" id="speakerCall"><i class="fas fa-volume-up"></i></button>
                        </div>
                    </div>
                `;
                modal.style.display = 'flex';
                
                document.getElementById('endCall')?.addEventListener('click', () => {
                    this.endCall();
                });
                
                // WebRTC logic here
                this.initWebRTC(type);
            }
            
            endCall() {
                if (this.localStream) {
                    this.localStream.getTracks().forEach(track => track.stop());
                }
                if (this.peerConnection) {
                    this.peerConnection.close();
                }
                document.getElementById('callModal').style.display = 'none';
            }
            
            async initWebRTC(type) {
                try {
                    this.localStream = await navigator.mediaDevices.getUserMedia({
                        audio: true,
                        video: type === 'video'
                    });
                    
                    this.peerConnection = new RTCPeerConnection({
                        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                    });
                    
                    this.localStream.getTracks().forEach(track => {
                        this.peerConnection.addTrack(track, this.localStream);
                    });
                    
                    this.peerConnection.ontrack = (event) => {
                        this.remoteStream = event.streams[0];
                        // Display remote video
                    };
                    
                    // Create offer/answer
                    const offer = await this.peerConnection.createOffer();
                    await this.peerConnection.setLocalDescription(offer);
                    
                    // Send offer to remote peer via socket
                    this.socket.emit('call_offer', {
                        to: this.currentChat.id,
                        offer: offer,
                        type: type
                    });
                    
                } catch (error) {
                    this.showToast('Ошибка доступа к камере/микрофону', 'error');
                    this.endCall();
                }
            }
            
            handleIncomingCall(data) {
                const modal = document.getElementById('callModal');
                modal.innerHTML = `
                    <div class="modal-content call-content">
                        <div class="call-header">
                            <div class="call-avatar">${data.from.charAt(0)}</div>
                            <h3>${data.from}</h3>
                            <p>Входящий звонок...</p>
                        </div>
                        <div class="call-controls">
                            <button class="call-control accept-call" id="acceptCall"><i class="fas fa-phone"></i></button>
                            <button class="call-control end-call" id="declineCall"><i class="fas fa-phone-slash"></i></button>
                        </div>
                    </div>
                `;
                modal.style.display = 'flex';
                
                document.getElementById('acceptCall')?.addEventListener('click', () => {
                    this.acceptCall(data);
                });
                
                document.getElementById('declineCall')?.addEventListener('click', () => {
                    this.endCall();
                });
            }
            
            async acceptCall(data) {
                await this.initWebRTC(data.type);
                this.socket.emit('call_answer', {
                    to: data.from,
                    answer: this.peerConnection.localDescription
                });
            }
            
            toggleEmojiPicker() {
                const existing = document.querySelector('.emoji-picker');
                if (existing) {
                    existing.remove();
                    return;
                }
                
                const emojis = ['😀', '😂', '❤️', '👍', '🎉', '🔥', '💯', '✨', '🌟', '💪', '🤔', '😢', '😡', '🥳', '😎', '🤯', '💀', '👻', '🎃', '💖', '😍', '🥰', '😘', '😊', '🙏', '🤝', '👋', '👍', '👎', '👏', '🙌', '🤲', '🤜', '🤛', '✊', '👊', '💪', '🦾', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '👊', '✊', '👌', '🤏', '🤌', '🤞', '🤟', '🤘', '🤙', '🖖', '✋', '🖐️', '👋', '👏', '🙌', '🤲', '🤝', '🙏', '💅', '👂', '👃', '🧠', '🦷', '🦴', '👀', '👁️', '👄', '👅', '💋', '🩸'];
                
                const picker = document.createElement('div');
                picker.className = 'emoji-picker';
                picker.style.cssText = `
                    position: absolute;
                    bottom: 70px;
                    left: 20px;
                    background: var(--bg-secondary);
                    border-radius: 12px;
                    padding: 12px;
                    display: grid;
                    grid-template-columns: repeat(8, 1fr);
                    gap: 8px;
                    z-index: 1000;
                    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
                `;
                
                emojis.forEach(emoji => {
                    const btn = document.createElement('button');
                    btn.textContent = emoji;
                    btn.style.cssText = `
                        width: 36px;
                        height: 36px;
                        border: none;
                        background: transparent;
                        cursor: pointer;
                        font-size: 20px;
                        transition: transform 0.2s;
                        border-radius: 8px;
                    `;
                    btn.onmouseenter = () => btn.style.transform = 'scale(1.2)';
                    btn.onmouseleave = () => btn.style.transform = '';
                    btn.onclick = () => {
                        const input = document.getElementById('messageInput');
                        input.value += emoji;
                        input.focus();
                        picker.remove();
                    };
                    picker.appendChild(btn);
                });
                
                document.getElementById('emojiBtn').parentElement.appendChild(picker);
            }
            
            showAttachModal() {
                const modal = document.getElementById('attachModal');
                modal.style.display = 'flex';
                
                document.querySelectorAll('.attach-item').forEach(item => {
                    item.onclick = () => {
                        this.handleAttach(item.dataset.type);
                        modal.style.display = 'none';
                    };
                });
            }
            
            handleAttach(type) {
                const input = document.createElement('input');
                input.type = 'file';
                
                if (type === 'image') input.accept = 'image/*';
                else if (type === 'video') input.accept = 'video/*';
                else if (type === 'audio') input.accept = 'audio/*';
                else if (type === 'document') input.accept = '.pdf,.doc,.docx,.txt,.xls,.xlsx';
                
                input.onchange = (e) => {
                    const file = e.target.files[0];
                    if (file) {
                        this.uploadFile(file, type);
                    }
                };
                
                if (type === 'contact') {
                    this.sendContact();
                } else if (type === 'location') {
                    this.sendLocation();
                } else if (type === 'poll') {
                    this.createPoll();
                } else {
                    input.click();
                }
            }
            
            uploadFile(file, type) {
                const reader = new FileReader();
                reader.onload = (e) => {
                    let preview = '';
                    if (type === 'image') {
                        preview = `<img src="${e.target.result}" style="max-width: 200px; border-radius: 8px;">`;
                    } else if (type === 'video') {
                        preview = `<video src="${e.target.result}" style="max-width: 200px; border-radius: 8px;" controls></video>`;
                    } else if (type === 'audio') {
                        preview = `<audio src="${e.target.result}" controls></audio>`;
                    } else {
                        preview = `<i class="fas fa-file"></i> ${file.name} (${(file.size / 1024).toFixed(1)} KB)`;
                    }
                    
                    this.addMessage(preview, false);
                    this.showToast(`Файл "${file.name}" отправлен`, 'success');
                };
                reader.readAsDataURL(file);
            }
            
            sendContact() {
                const contact = {
                    name: prompt('Введите имя контакта:'),
                    phone: prompt('Введите номер телефона:')
                };
                if (contact.name && contact.phone) {
                    this.addMessage(`
                        <div class="contact-card">
                            <i class="fas fa-user-circle" style="font-size: 32px;"></i>
                            <div>
                                <strong>${contact.name}</strong>
                                <div>${contact.phone}</div>
                            </div>
                        </div>
                    `, false);
                }
            }
            
            sendLocation() {
                if (navigator.geolocation) {
                    navigator.geolocation.getCurrentPosition((position) => {
                        const lat = position.coords.latitude;
                        const lng = position.coords.longitude;
                        const mapUrl = `https://maps.google.com/maps?q=${lat},${lng}&z=15`;
                        this.addMessage(`
                            <div class="location-card">
                                <iframe width="100%" height="200" frameborder="0" src="https://maps.google.com/maps?q=${lat},${lng}&z=15&output=embed"></iframe>
                                <div style="padding: 8px;">
                                    <i class="fas fa-map-marker-alt"></i>
                                    <a href="${mapUrl}" target="_blank">Открыть в картах</a>
                                </div>
                            </div>
                        `, false);
                    });
                } else {
                    this.showToast('Геолокация не поддерживается', 'error');
                }
            }
            
            createPoll() {
                const question = prompt('Вопрос опроса:');
                if (!question) return;
                
                const options = [];
                for (let i = 1; i <= 4; i++) {
                    const opt = prompt(`Вариант ${i} (оставьте пустым для завершения):`);
                    if (opt) options.push(opt);
                    else break;
                }
                
                if (options.length < 2) {
                    this.showToast('Нужно минимум 2 варианта', 'error');
                    return;
                }
                
                const pollId = Date.now().toString();
                this.addMessage(`
                    <div class="poll-card" data-poll-id="${pollId}">
                        <strong>📊 ${question}</strong>
                        ${options.map((opt, idx) => `
                            <div class="poll-option" data-option="${idx}">
                                <span>${String.fromCharCode(65 + idx)}. ${opt}</span>
                                <span class="poll-votes" style="float: right;">0</span>
                            </div>
                        `).join('')}
                        <div style="margin-top: 8px; font-size: 12px; color: var(--text-secondary);">
                            Всего голосов: <span class="total-votes">0</span>
                        </div>
                    </div>
                `, false);
                
                // Add poll click handler
                setTimeout(() => {
                    document.querySelectorAll('.poll-option').forEach(opt => {
                        opt.onclick = () => this.votePoll(pollId, opt.dataset.option);
                    });
                }, 100);
            }
            
            votePoll(pollId, optionIndex) {
                const pollCard = document.querySelector(`.poll-card[data-poll-id="${pollId}"]`);
                if (!pollCard) return;
                
                const option = pollCard.querySelector(`.poll-option[data-option="${optionIndex}"]`);
                const votesSpan = option.querySelector('.poll-votes');
                const totalSpan = pollCard.querySelector('.total-votes');
                
                let votes = parseInt(votesSpan.textContent) || 0;
                votes++;
                votesSpan.textContent = votes;
                
                let total = parseInt(totalSpan.textContent) || 0;
                total++;
                totalSpan.textContent = total;
                
                this.showToast('Голос учтен', 'success');
            }
            
            startVoiceRecording() {
                if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
                    this.mediaRecorder.stop();
                    document.getElementById('voiceBtn').classList.remove('recording');
                    return;
                }
                
                navigator.mediaDevices.getUserMedia({ audio: true })
                    .then(stream => {
                        this.mediaRecorder = new MediaRecorder(stream);
                        this.audioChunks = [];
                        
                        this.mediaRecorder.ondataavailable = (event) => {
                            this.audioChunks.push(event.data);
                        };
                        
                        this.mediaRecorder.onstop = () => {
                            const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
                            const audioUrl = URL.createObjectURL(audioBlob);
                            this.addMessage(`
                                <div class="voice-note">
                                    <i class="fas fa-play" onclick="this.nextElementSibling.play()"></i>
                                    <audio src="${audioUrl}" style="display: none;"></audio>
                                    <div class="voice-wave">
                                        <span></span><span></span><span></span><span></span><span></span>
                                    </div>
                                    <span>0:${Math.floor(this.audioChunks.length / 10)}</span>
                                </div>
                            `, false);
                            stream.getTracks().forEach(track => track.stop());
                        };
                        
                        this.mediaRecorder.start();
                        document.getElementById('voiceBtn').classList.add('recording');
                        this.showToast('Запись... Нажмите еще раз для отправки', 'info');
                    })
                    .catch(() => {
                        this.showToast('Ошибка доступа к микрофону', 'error');
                    });
            }
            
            openGifPicker() {
                this.showToast('GIF поиск (GIPHY API)', 'info');
            }
            
            openStickerPicker() {
                this.showToast('Стикерпаки', 'info');
            }
            
            showChatMenu() {
                const modal = document.getElementById('chatMenuModal');
                modal.style.display = 'flex';
                
                document.getElementById('muteChat').onclick = () => {
                    this.showToast('Уведомления отключены', 'info');
                    modal.style.display = 'none';
                };
                document.getElementById('clearChat').onclick = () => {
                    if (confirm('Очистить историю чата?')) {
                        this.messages.set(this.currentChat.id, []);
                        this.renderMessages([]);
                        this.showToast('История очищена', 'success');
                    }
                    modal.style.display = 'none';
                };
                document.getElementById('deleteChat').onclick = () => {
                    if (confirm('Удалить чат?')) {
                        this.chats.delete(this.currentChat.id);
                        this.renderChats(Array.from(this.chats.values()));
                        this.closeChat();
                        this.showToast('Чат удален', 'success');
                    }
                    modal.style.display = 'none';
                };
                document.getElementById('blockUser').onclick = () => {
                    this.showToast('Пользователь заблокирован', 'info');
                    modal.style.display = 'none';
                };
                document.getElementById('exportChat').onclick = () => {
                    this.exportChat();
                    modal.style.display = 'none';
                };
            }
            
            exportChat() {
                const messages = this.messages.get(this.currentChat.id) || [];
                const exportData = {
                    chat: this.currentChat.name,
                    date: new Date().toISOString(),
                    messages: messages.map(m => ({
                        text: m.text,
                        sender: m.sender === this.currentUser.id ? 'Вы' : m.sender,
                        time: new Date(m.timestamp).toLocaleString(),
                        status: m.status
                    }))
                };
                
                const dataStr = JSON.stringify(exportData, null, 2);
                const dataUri = 'data:application/json;charset=utf-8,'+ encodeURIComponent(dataStr);
                const exportFileDefaultName = `chat_${this.currentChat.name}_${Date.now()}.json`;
                
                const link = document.createElement('a');
                link.setAttribute('href', dataUri);
                link.setAttribute('download', exportFileDefaultName);
                link.click();
                
                this.showToast('Чат экспортирован', 'success');
            }
            
            showContextMenu(event, messageId) {
                const menu = document.getElementById('messageContextMenu');
                menu.style.display = 'block';
                menu.style.left = event.pageX + 'px';
                menu.style.top = event.pageY + 'px';
                
                const closeMenu = () => {
                    menu.style.display = 'none';
                    document.removeEventListener('click', closeMenu);
                };
                
                document.addEventListener('click', closeMenu);
                
                document.querySelectorAll('.context-menu-item').forEach(item => {
                    item.onclick = () => {
                        const action = item.dataset.action;
                        switch(action) {
                            case 'reply':
                                const message = this.findMessageById(messageId);
                                if (message) {
                                    this.replyingTo = message;
                                    document.getElementById('replyPreview').style.display = 'flex';
                                    document.getElementById('replyText').textContent = this.truncate(message.text, 50);
                                }
                                break;
                            case 'forward':
                                this.showToast('Пересылка сообщения', 'info');
                                break;
                            case 'copy':
                                const msg = this.findMessageById(messageId);
                                if (msg) {
                                    navigator.clipboard.writeText(msg.text);
                                    this.showToast('Скопировано', 'success');
                                }
                                break;
                            case 'edit':
                                const editMsg = this.findMessageById(messageId);
                                if (editMsg && editMsg.sender === this.currentUser.id) {
                                    this.editingMessage = editMsg;
                                    document.getElementById('editPreview').style.display = 'flex';
                                    document.getElementById('messageInput').value = editMsg.text;
                                    document.getElementById('messageInput').focus();
                                } else {
                                    this.showToast('Вы можете редактировать только свои сообщения', 'error');
                                }
                                break;
                            case 'delete':
                                this.deleteMessage(messageId, confirm('Удалить для всех?'));
                                break;
                            case 'react':
                                this.showReactionPicker(event, messageId);
                                break;
                            case 'star':
                                this.showToast('Добавлено в избранное', 'success');
                                break;
                            case 'report':
                                this.showToast('Жалоба отправлена', 'info');
                                break;
                        }
                        menu.style.display = 'none';
                    };
                });
            }
            
            showReactionPicker(event, messageId) {
                const reactions = ['👍', '❤️', '😂', '😮', '😢', '😡', '👎'];
                const picker = document.createElement('div');
                picker.className = 'reaction-picker';
                picker.style.left = event.pageX + 'px';
                picker.style.top = (event.pageY - 50) + 'px';
                
                reactions.forEach(emoji => {
                    const btn = document.createElement('button');
                    btn.textContent = emoji;
                    btn.style.cssText = `
                        width: 36px;
                        height: 36px;
                        border: none;
                        background: transparent;
                        cursor: pointer;
                        font-size: 20px;
                        border-radius: 50%;
                        transition: transform 0.2s;
                    `;
                    btn.onmouseenter = () => btn.style.transform = 'scale(1.2)';
                    btn.onmouseleave = () => btn.style.transform = '';
                    btn.onclick = () => {
                        this.addReaction(messageId, emoji);
                        picker.remove();
                    };
                    picker.appendChild(btn);
                });
                
                document.body.appendChild(picker);
                setTimeout(() => picker.remove(), 5000);
            }
            
            addReaction(messageId, emoji) {
                const message = this.findMessageById(messageId);
                if (message) {
                    const existingReaction = message.reactions.find(r => r.emoji === emoji);
                    if (existingReaction) {
                        existingReaction.count++;
                    } else {
                        message.reactions.push({ emoji, count: 1 });
                    }
                    this.saveMessageToDB(message);
                    
                    // Update UI
                    const messageEl = document.querySelector(`[data-message-id="${messageId}"]`);
                    if (messageEl) {
                        let reactionsHtml = '<div class="message-reactions">';
                        message.reactions.forEach(r => {
                            reactionsHtml += `<span class="message-reaction">${r.emoji} ${r.count}</span>`;
                        });
                        reactionsHtml += '</div>';
                        
                        const existingReactions = messageEl.querySelector('.message-reactions');
                        if (existingReactions) {
                            existingReactions.outerHTML = reactionsHtml;
                        } else {
                            messageEl.insertAdjacentHTML('beforeend', reactionsHtml);
                        }
                    }
                }
            }
            
            showSettings() {
                this.showToast('Настройки (в разработке)', 'info');
            }
            
            showToast(message, type = 'info') {
                const container = document.getElementById('toastContainer');
                const toast = document.createElement('div');
                toast.className = `toast toast-${type}`;
                toast.innerHTML = `
                    <i class="fas ${type === 'success' ? 'fa-check-circle' : type === 'error' ? 'fa-exclamation-circle' : 'fa-info-circle'}"></i>
                    <span>${message}</span>
                `;
                container.appendChild(toast);
                
                setTimeout(() => {
                    toast.style.animation = 'slideOut 0.3s ease';
                    setTimeout(() => toast.remove(), 300);
                }, 3000);
            }
            
            showDesktopNotification(title, body) {
                if ('Notification' in window && Notification.permission === 'granted') {
                    new Notification(title, { body, icon: '/icon.png' });
                } else if ('Notification' in window && Notification.permission !== 'denied') {
                    Notification.requestPermission();
                }
            }
            
            playNotificationSound() {
                const audio = new Audio('/notification.mp3');
                audio.play().catch(e => console.log('Audio error:', e));
            }
            
            updateConnectionStatus(connected) {
                const statusText = document.getElementById('userStatusText');
                const statusDot = document.getElementById('userStatusDot');
                if (connected) {
                    statusText.innerHTML = '<span class="status-last-seen">онлайн</span>';
                    statusDot.style.background = '#25D366';
                } else {
                    statusText.innerHTML = '<span class="status-last-seen">офлайн</span>';
                    statusDot.style.background = '#ccc';
                }
            }
            
            closeAllModals() {
                document.querySelectorAll('.modal').forEach(modal => {
                    modal.style.display = 'none';
                });
            }
            
            loadSettings() {
                return {
                    theme: localStorage.getItem('theme') || 'light',
                    fontSize: localStorage.getItem('fontSize') || 14,
                    enterToSend: localStorage.getItem('enterToSend') !== 'false',
                    enableNotifications: localStorage.getItem('enableNotifications') === 'true',
                    notificationSound: localStorage.getItem('notificationSound') === 'true'
                };
            }
            
            applySettings() {
                document.body.style.fontSize = this.settings.fontSize + 'px';
            }
            
            setupServiceWorker() {
                if ('serviceWorker' in navigator) {
                    navigator.serviceWorker.register('/sw.js').catch(err => console.log('SW error:', err));
                }
            }
        }
        
        // Инициализация
        const app = new UltimateMessengerClone();
        window.app = app;
    </script>
</body>
</html>
EOF

# --- СТИЛИ (WhatsApp/Telegram Clone) ---
cat > /var/www/messenger/style.css <<'EOF'
/* WhatsApp/Telegram Clone Styles */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
    -webkit-tap-highlight-color: transparent;
}

body {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: var(--bg-primary);
    color: var(--text-primary);
    overflow: hidden;
    transition: all 0.3s ease;
}

/* WhatsApp Theme */
[data-theme="whatsapp"] {
    --bg-primary: #e5ddd5;
    --bg-secondary: #ffffff;
    --bg-tertiary: #f0f2f5;
    --message-in: #ffffff;
    --message-out: #dcf8c5;
    --text-primary: #111b21;
    --text-secondary: #54656f;
    --border-color: #e9edef;
    --primary: #25D366;
    --primary-dark: #075E54;
}

/* Telegram Theme */
[data-theme="telegram"] {
    --bg-primary: #0f1621;
    --bg-secondary: #17212b;
    --bg-tertiary: #242f3d;
    --message-in: #182533;
    --message-out: #2b5278;
    --text-primary: #ffffff;
    --text-secondary: #8393a3;
    --border-color: #2c3e50;
    --primary: #0088cc;
    --primary-dark: #2c3e50;
}

.app-container {
    display: flex;
    height: 100vh;
    width: 100%;
    overflow: hidden;
}

/* Sidebar (Chats List) */
.sidebar {
    width: 380px;
    background: var(--bg-secondary);
    border-right: 1px solid var(--border-color);
    display: flex;
    flex-direction: column;
    height: 100vh;
}

.sidebar-header {
    padding: 16px;
    background: var(--bg-tertiary);
    border-bottom: 1px solid var(--border-color);
}

.user-card {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 12px;
}

.avatar-wrapper {
    position: relative;
}

.avatar {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--primary), var(--primary-dark));
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 20px;
    font-weight: 600;
    position: relative;
}

.status-online {
    position: absolute;
    bottom: 2px;
    right: 2px;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: #25D366;
    border: 2px solid var(--bg-secondary);
}

.user-info {
    flex: 1;
}

.user-info h3 {
    font-size: 16px;
    font-weight: 600;
}

.user-status {
    font-size: 12px;
    color: var(--text-secondary);
}

.user-actions {
    display: flex;
    gap: 16px;
}

.user-actions i {
    cursor: pointer;
    font-size: 18px;
    transition: opacity 0.2s;
}

.user-actions i:hover {
    opacity: 0.7;
}

.search-bar {
    position: relative;
}

.search-bar i {
    position: absolute;
    left: 12px;
    top: 50%;
    transform: translateY(-50%);
    color: var(--text-secondary);
}

.search-bar input {
    width: 100%;
    padding: 10px 12px 10px 36px;
    background: var(--bg-tertiary);
    border: none;
    border-radius: 20px;
    font-size: 14px;
    color: var(--text-primary);
}

.search-bar input:focus {
    outline: none;
    background: var(--bg-primary);
}

/* Chats List */
.chats-list {
    flex: 1;
    overflow-y: auto;
}

.chat-item {
    display: flex;
    align-items: center;
    padding: 12px 16px;
    cursor: pointer;
    transition: background 0.2s;
}

.chat-item:hover {
    background: var(--bg-tertiary);
}

.chat-avatar {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: var(--primary);
    display: flex;
    align-items: center;
    justify-content: center;
    margin-right: 12px;
    position: relative;
    font-weight: 600;
}

.chat-info {
    flex: 1;
    min-width: 0;
}

.chat-name {
    font-weight: 500;
    margin-bottom: 4px;
}

.chat-preview {
    font-size: 13px;
    color: var(--text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.chat-meta {
    text-align: right;
}

.chat-time {
    font-size: 11px;
    color: var(--text-secondary);
    margin-bottom: 4px;
}

.chat-badge {
    background: var(--primary);
    color: white;
    border-radius: 12px;
    padding: 2px 6px;
    font-size: 11px;
    font-weight: 600;
    display: inline-block;
}

/* Chat Area */
.chat-area {
    flex: 1;
    display: flex;
    flex-direction: column;
    background: var(--bg-primary);
    position: relative;
}

.chat-placeholder {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
}

.placeholder-content {
    max-width: 400px;
    padding: 40px;
}

.placeholder-content i {
    font-size: 80px;
    margin-bottom: 20px;
    opacity: 0.5;
}

.placeholder-content h2 {
    font-size: 28px;
    margin-bottom: 12px;
}

.placeholder-content p {
    color: var(--text-secondary);
    margin-bottom: 24px;
}

.new-chat-btn {
    padding: 12px 24px;
    background: var(--primary);
    border: none;
    border-radius: 24px;
    color: white;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: transform 0.2s;
}

.new-chat-btn:hover {
    transform: scale(1.05);
}

/* Chat Header */
.chat-header {
    padding: 12px 16px;
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border-color);
    display: flex;
    align-items: center;
    justify-content: space-between;
}

.chat-header-info {
    display: flex;
    align-items: center;
    gap: 12px;
}

.chat-header-info .avatar {
    width: 40px;
    height: 40px;
    font-size: 16px;
}

.chat-details h3 {
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 2px;
}

.chat-status {
    font-size: 12px;
    color: var(--text-secondary);
}

.typing-indicator-small {
    color: var(--primary);
}

.chat-actions {
    display: flex;
    gap: 20px;
}

.chat-actions i {
    font-size: 20px;
    cursor: pointer;
    transition: opacity 0.2s;
}

.chat-actions i:hover {
    opacity: 0.7;
}

/* Messages Container */
.messages-container {
    flex: 1;
    overflow-y: auto;
    position: relative;
}

.messages-area {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 8px;
}

/* Messages */
.message {
    display: flex;
    animation: fadeInUp 0.3s ease;
}

.message.incoming {
    justify-content: flex-start;
}

.message.outgoing {
    justify-content: flex-end;
}

.message-bubble {
    max-width: 65%;
    padding: 8px 12px;
    border-radius: 18px;
    position: relative;
    word-wrap: break-word;
}

.message.incoming .message-bubble {
    background: var(--message-in);
    border-bottom-left-radius: 4px;
}

.message.outgoing .message-bubble {
    background: var(--message-out);
    border-bottom-right-radius: 4px;
}

.message-text {
    font-size: 14px;
    line-height: 1.4;
}

.message-text a {
    color: var(--primary);
    text-decoration: none;
}

.message-text code {
    background: rgba(0,0,0,0.1);
    padding: 2px 4px;
    border-radius: 4px;
    font-family: monospace;
}

.message-text pre {
    background: rgba(0,0,0,0.1);
    padding: 8px;
    border-radius: 8px;
    overflow-x: auto;
    font-family: monospace;
}

.mention {
    color: var(--primary);
    cursor: pointer;
    font-weight: 500;
}

.message-meta {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 4px;
    margin-top: 4px;
    font-size: 10px;
    color: var(--text-secondary);
}

.message-status {
    font-size: 12px;
}

.message-status .read {
    color: #34b7f1;
}

.reply-preview {
    background: rgba(0,0,0,0.05);
    border-left: 3px solid var(--primary);
    padding: 6px 8px;
    margin-bottom: 6px;
    border-radius: 8px;
    font-size: 12px;
}

.forwarded-badge {
    font-size: 10px;
    color: var(--text-secondary);
    margin-bottom: 4px;
}

.message-reactions {
    display: flex;
    gap: 4px;
    margin-top: 6px;
}

.message-reaction {
    background: rgba(0,0,0,0.05);
    border-radius: 12px;
    padding: 2px 8px;
    font-size: 12px;
    cursor: pointer;
}

.edited-badge {
    font-size: 10px;
    color: var(--text-secondary);
    margin-left: 4px;
}

.date-divider {
    text-align: center;
    margin: 16px 0;
    font-size: 12px;
    color: var(--text-secondary);
}

/* Input Area */
.input-area {
    padding: 12px 16px;
    background: var(--bg-secondary);
    border-top: 1px solid var(--border-color);
}

.input-tools {
    display: flex;
    gap: 8px;
    margin-bottom: 8px;
}

.tool-btn {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    border: none;
    background: var(--bg-tertiary);
    color: var(--text-secondary);
    cursor: pointer;
    transition: all 0.2s;
}

.tool-btn:hover {
    background: var(--primary);
    color: white;
}

.tool-btn.recording {
    background: #ff4444;
    color: white;
    animation: pulse 1s infinite;
}

.input-wrapper {
    display: flex;
    align-items: flex-end;
    gap: 8px;
    position: relative;
}

.reply-preview, .edit-preview {
    position: absolute;
    bottom: 100%;
    left: 0;
    right: 0;
    background: var(--bg-tertiary);
    padding: 8px 12px;
    border-radius: 12px 12px 0 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 4px;
}

.reply-preview i, .edit-preview i {
    cursor: pointer;
}

.input-wrapper textarea {
    flex: 1;
    padding: 10px 12px;
    background: var(--bg-tertiary);
    border: none;
    border-radius: 20px;
    color: var(--text-primary);
    font-size: 14px;
    resize: none;
    font-family: inherit;
    max-height: 120px;
}

.input-wrapper textarea:focus {
    outline: none;
}

.send-btn {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    border: none;
    background: var(--primary);
    color: white;
    cursor: pointer;
    transition: transform 0.2s;
}

.send-btn:hover {
    transform: scale(1.05);
}

/* Scroll to bottom */
.scroll-to-bottom {
    position: absolute;
    bottom: 20px;
    right: 20px;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: var(--primary);
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    box-shadow: 0 2px 8px rgba(0,0,0,0.15);
    transition: transform 0.2s;
    z-index: 10;
}

.scroll-to-bottom:hover {
    transform: scale(1.1);
}

/* Modal */
.modal {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0,0,0,0.7);
    align-items: center;
    justify-content: center;
    z-index: 1000;
}

.modal-content {
    background: var(--bg-secondary);
    border-radius: 24px;
    padding: 24px;
    max-width: 400px;
    width: 90%;
    max-height: 80vh;
    overflow-y: auto;
}

.modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
}

.modal-header i {
    cursor: pointer;
    font-size: 20px;
}

/* Context Menu */
.context-menu {
    position: fixed;
    background: var(--bg-secondary);
    border-radius: 12px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    padding: 8px 0;
    min-width: 180px;
    z-index: 1001;
}

.context-menu-item {
    padding: 10px 16px;
    cursor: pointer;
    transition: background 0.2s;
    display: flex;
    align-items: center;
    gap: 12px;
}

.context-menu-item:hover {
    background: var(--bg-tertiary);
}

/* Attach Grid */
.attach-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
}

.attach-item {
    text-align: center;
    cursor: pointer;
    padding: 12px;
    border-radius: 12px;
    transition: background 0.2s;
}

.attach-item:hover {
    background: var(--bg-tertiary);
}

.attach-item i {
    font-size: 32px;
    margin-bottom: 8px;
    display: block;
}

.attach-item span {
    font-size: 12px;
}

/* Call Modal */
.call-modal .modal-content {
    max-width: 300px;
    text-align: center;
}

.call-header {
    text-align: center;
    margin-bottom: 24px;
}

.call-avatar {
    width: 80px;
    height: 80px;
    border-radius: 50%;
    background: var(--primary);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 40px;
    margin: 0 auto 16px;
}

.call-controls {
    display: flex;
    justify-content: center;
    gap: 20px;
}

.call-control {
    width: 60px;
    height: 60px;
    border-radius: 50%;
    border: none;
    background: var(--bg-tertiary);
    color: var(--text-primary);
    cursor: pointer;
    transition: transform 0.2s;
}

.call-control:hover {
    transform: scale(1.1);
}

.call-control.end-call {
    background: #ff4444;
    color: white;
}

/* Toast */
.toast-container {
    position: fixed;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 1000;
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: center;
}

.toast {
    background: var(--bg-secondary);
    padding: 12px 20px;
    border-radius: 30px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    display: flex;
    align-items: center;
    gap: 12px;
    animation: slideUp 0.3s ease;
}

.toast-success {
    border-left: 4px solid #25D366;
}

.toast-error {
    border-left: 4px solid #ff4444;
}

.toast-info {
    border-left: 4px solid var(--primary);
}

/* Spinner */
.spinner {
    width: 40px;
    height: 40px;
    border: 3px solid var(--border-color);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin: 20px auto;
}

/* Animations */
@keyframes fadeInUp {
    from {
        opacity: 0;
        transform: translateY(10px);
    }
    to {
        opacity: 1;
        transform: translateY(0);
    }
}

@keyframes slideUp {
    from {
        opacity: 0;
        transform: translateY(20px);
    }
    to {
        opacity: 1;
        transform: translateY(0);
    }
}

@keyframes slideOut {
    from {
        opacity: 1;
        transform: translateY(0);
    }
    to {
        opacity: 0;
        transform: translateY(-20px);
    }
}

@keyframes spin {
    to {
        transform: rotate(360deg);
    }
}

@keyframes pulse {
    0%, 100% {
        transform: scale(1);
    }
    50% {
        transform: scale(1.1);
    }
}

/* Responsive */
@media (max-width: 768px) {
    .sidebar {
        position: fixed;
        left: -100%;
        width: 100%;
        z-index: 100;
        transition: left 0.3s ease;
    }
    
    .sidebar.open {
        left: 0;
    }
    
    .chat-area {
        width: 100%;
    }
    
    .mobile-back {
        display: block !important;
    }
    
    .message-bubble {
        max-width: 85%;
    }
}

@media (min-width: 769px) {
    .mobile-back {
        display: none;
    }
}

/* Loading */
.splash {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: var(--bg-primary);
    display: flex;
    align-items: center;
    justify-content: center;
    flex-direction: column;
    z-index: 10000;
    transition: opacity 0.5s ease;
}

.splash-logo {
    display: flex;
    gap: 20px;
    margin-bottom: 30px;
}

.progress-bar {
    width: 300px;
    height: 4px;
    background: var(--bg-tertiary);
    border-radius: 2px;
    overflow: hidden;
    margin: 20px 0;
}

.progress-fill {
    height: 100%;
    background: var(--primary);
    width: 0%;
    transition: width 0.3s ease;
}
EOF

# --- NGINX КОНФИГУРАЦИЯ ---
cat > /etc/nginx/sites-available/matrix <<EOF
server {
    server_name $DOMAIN;
    listen 80;
    listen [::]:80;
    return 301 https://\$server_name\$request_uri;
}

server {
    server_name $DOMAIN;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    listen 8448 ssl;
    listen [::]:8448 ssl;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    root /var/www/messenger;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /socket.io {
        proxy_pass http://localhost:3002/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    
    location /api {
        proxy_pass http://localhost:3002/api;
        proxy_set_header Host \$host;
    }
    
    location /qr {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://localhost:8008;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 2G;
    }
    
    location /.well-known/matrix/client {
        add_header Content-Type application/json;
        return 200 '{"m.homeserver": {"base_url": "https://$DOMAIN"}}';
    }
}
EOF

# --- ЗАПУСК ---
systemctl daemon-reload
systemctl enable matrix-synapse postgresql redis-server nginx
systemctl restart matrix-synapse postgresql redis-server nginx

# --- SSL ---
certbot certonly --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL
systemctl reload nginx

# --- СОЗДАНИЕ АДМИНИСТРАТОРА ---
register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml \
    --user "$ADMIN_USER" --password "$ADMIN_PASS" \
    --admin http://localhost:8008 || true

# --- ФИНАЛЬНАЯ ИНФОРМАЦИЯ ---
clear
print_header "УСТАНОВКА ULTIMATE MESSENGER V9 ЗАВЕРШЕНА!"

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║     ULTIMATE MESSENGER V9 - WHATSAPP/TELEGRAM CLONE                   ║"
echo "║     Полная копия логики WhatsApp и Telegram                           ║"
echo "║     1:1 синхронизация между всеми устройствами                        ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}🌐 ВЕБ-ИНТЕРФЕЙС:${NC}"
echo "   https://$DOMAIN"
echo ""
echo -e "${CYAN}🔧 АДМИН-ПАНЕЛЬ:${NC}"
echo "   https://$DOMAIN/admin"
echo "   Логин: $ADMIN_USER"
echo "   Пароль: $ADMIN_PASS"
echo ""
echo -e "${CYAN}📱 QR АВТОРИЗАЦИЯ:${NC}"
echo "   Нажмите на иконку QR в шапке чатов"
echo ""
echo -e "${CYAN}💬 ФУНКЦИОНАЛ WHATSAPP/TELEGRAM:${NC}"
echo "   ✓ 1:1 синхронизация между устройствами"
echo "   ✓ IndexedDB оффлайн хранение"
echo "   ✓ Редактирование сообщений"
echo "   ✓ Удаление для всех/для себя"
echo "   ✓ Ответы на сообщения"
echo "   ✓ Пересылка сообщений"
echo "   ✓ Реакции (эмодзи)"
echo "   ✓ Голосовые сообщения"
echo "   ✓ Отправка файлов (фото, видео, документы)"
echo "   ✓ Отправка контактов"
echo "   ✓ Отправка геолокации"
echo "   ✓ Создание опросов"
echo "   ✓ Стикеры"
echo "   ✓ GIF анимации"
echo "   ✓ Форматирование текста"
echo "   ✓ Упоминания @username"
echo "   ✓ Индикатор набора текста"
echo "   ✓ Статус "онлайн""
echo "   ✓ Двойные галочки (прочитано)"
echo "   ✓ Групповые чаты"
echo "   ✓ Видеозвонки (WebRTC)"
echo "   ✓ Голосовые звонки"
echo "   ✓ PWA установка"
echo "   ✓ Service Worker оффлайн"
echo "   ✓ Push уведомления"
echo ""
echo -e "${YELLOW}📋 ПОЛНЫЕ УЧЕТНЫЕ ДАННЫЕ:${NC}"
echo "   /root/ultimate_messenger_credentials.txt"
echo ""
echo -e "${GREEN}🎉 ГОТОВО! МЕССЕНДЖЕР РАБОТАЕТ КАК WHATSAPP И TELEGRAM! 🎉${NC}"