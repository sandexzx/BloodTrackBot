#!/bin/bash

# BloodTrackBot Automated Deploy Script
# Скрипт для автоматизированного деплоя телеграм-бота на Ubuntu 24.04
# Поддерживает как первоначальную установку, так и обновление

set -e  # Остановка при ошибке

# Конфигурация
PROJECT_NAME="bloodtrackbot"
REPO_URL="https://github.com/sandexzx/BloodTrackBot.git"
APP_USER="botuser"
APP_DIR="/opt/$PROJECT_NAME"
VENV_DIR="$APP_DIR/venv"
SERVICE_NAME="$PROJECT_NAME"
PYTHON_VERSION="3.12"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Запрос токена бота
get_bot_token() {
    local current_token=""
    
    # Проверяем, есть ли уже токен в .env файле
    if [[ -f "$APP_DIR/.env" ]]; then
        current_token=$(grep "BOT_TOKEN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
        if [[ -n "$current_token" && "$current_token" != "your_bot_token_here" ]]; then
            echo
            log "Найден существующий токен бота: ${current_token:0:10}..."
            read -p "Хотите использовать существующий токен? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                BOT_TOKEN="$current_token"
                return
            fi
        fi
    fi
    
    echo
    log "Необходимо указать токен Telegram бота"
    echo "Получить токен можно у @BotFather в Telegram"
    echo
    
    while true; do
        read -p "Введите токен бота: " BOT_TOKEN
        
        # Базовая валидация токена (должен содержать цифры и содержать ':')
        if [[ $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            error "Неверный формат токена. Токен должен иметь вид: 123456789:AAABBBCCC..."
            echo "Попробуйте еще раз."
        fi
    done
    
    success "Токен принят"
}
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен от имени root"
        exit 1
    fi
}

# Обновление системы и установка зависимостей
install_system_dependencies() {
    log "Обновление системы и установка зависимостей..."
    
    apt update
    apt install -y \
        python$PYTHON_VERSION \
        python$PYTHON_VERSION-venv \
        python$PYTHON_VERSION-dev \
        python3-pip \
        git \
        curl \
        wget \
        nano \
        htop \
        sqlite3 \
        supervisor
    
    success "Системные зависимости установлены"
}

# Создание пользователя для приложения
create_app_user() {
    if id "$APP_USER" &>/dev/null; then
        warning "Пользователь $APP_USER уже существует"
    else
        log "Создание пользователя $APP_USER..."
        useradd -r -s /bin/false -d $APP_DIR $APP_USER
        success "Пользователь $APP_USER создан"
    fi
}

# Настройка директорий проекта
setup_directories() {
    log "Настройка директорий проекта..."
    
    # Создание директорий
    mkdir -p $APP_DIR
    mkdir -p $APP_DIR/logs
    
    # Установка прав доступа
    chown -R $APP_USER:$APP_USER $APP_DIR
    chmod 755 $APP_DIR
    
    success "Директории настроены"
}

# Определение режима работы (установка/обновление)
check_deployment_mode() {
    if [[ -d "$APP_DIR/.git" ]]; then
        echo "update"
    else
        echo "install"
    fi
}

# Клонирование или обновление репозитория
setup_repository() {
    local mode=$1
    
    if [[ "$mode" == "update" ]]; then
        log "Обновление репозитория..."
        cd $APP_DIR
        sudo -u $APP_USER git fetch origin
        sudo -u $APP_USER git reset --hard origin/main
        success "Репозиторий обновлен"
    else
        log "Клонирование репозитория..."
        if [[ -d "$APP_DIR" ]]; then
            rm -rf $APP_DIR/*
        fi
        sudo -u $APP_USER git clone $REPO_URL $APP_DIR
        success "Репозиторий склонирован"
    fi
}

# Настройка виртуального окружения Python
setup_python_environment() {
    local mode=$1
    
    log "Настройка Python окружения..."
    
    cd $APP_DIR
    
    if [[ "$mode" == "update" && -d "$VENV_DIR" ]]; then
        log "Обновление виртуального окружения..."
        sudo -u $APP_USER $VENV_DIR/bin/pip install --upgrade pip
        sudo -u $APP_USER $VENV_DIR/bin/pip install -r requirements.txt --upgrade
    else
        log "Создание нового виртуального окружения..."
        # Удаление старого venv если существует
        [[ -d "$VENV_DIR" ]] && rm -rf $VENV_DIR
        
        # Создание нового виртуального окружения
        sudo -u $APP_USER python$PYTHON_VERSION -m venv $VENV_DIR
        
        # Обновление pip
        sudo -u $APP_USER $VENV_DIR/bin/pip install --upgrade pip
        
        # Установка зависимостей
        sudo -u $APP_USER $VENV_DIR/bin/pip install -r requirements.txt
    fi
    
    success "Python окружение настроено"
}

# Настройка конфигурации (.env файл)
setup_configuration() {
    log "Настройка конфигурации..."
    
    # Создание или обновление .env файла
    cat > $APP_DIR/.env << EOF
# Telegram Bot Configuration
BOT_TOKEN=$BOT_TOKEN

# Database Configuration (SQLite используется по умолчанию)
# Путь к базе данных будет: $APP_DIR/blood_pressure.db

# Logging Configuration
LOG_LEVEL=INFO
EOF
    
    chown $APP_USER:$APP_USER $APP_DIR/.env
    chmod 600 $APP_DIR/.env
    
    success "Конфигурация настроена с токеном бота"
}

# Инициализация базы данных
setup_database() {
    log "Настройка базы данных..."
    
    cd $APP_DIR
    
    # База данных SQLite будет создана автоматически при первом запуске
    # Убеждаемся, что у пользователя есть права на запись в директорию
    chown $APP_USER:$APP_USER $APP_DIR
    chmod 755 $APP_DIR
    
    success "База данных настроена"
}

# Создание systemd сервиса
create_systemd_service() {
    log "Создание systemd сервиса..."
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=BloodTrack Telegram Bot
After=network.target
Wants=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
Environment=PATH=$VENV_DIR/bin
ExecStart=$VENV_DIR/bin/python bot.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Безопасность
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$APP_DIR

# Ограничения ресурсов
LimitNOFILE=65536
MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF

    # Перезагрузка systemd и включение автозапуска
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    success "Systemd сервис создан и настроен"
}

# Управление сервисом
manage_service() {
    local mode=$1
    
    if [[ "$mode" == "update" ]]; then
        log "Перезапуск сервиса..."
        if systemctl is-active --quiet $SERVICE_NAME; then
            systemctl restart $SERVICE_NAME
        else
            systemctl start $SERVICE_NAME
        fi
    else
        log "Запуск сервиса..."
        systemctl start $SERVICE_NAME
    fi
    
    # Проверка статуса
    sleep 3
    if systemctl is-active --quiet $SERVICE_NAME; then
        success "Сервис $SERVICE_NAME успешно запущен"
    else
        error "Не удалось запустить сервис $SERVICE_NAME"
        systemctl status $SERVICE_NAME --no-pager
        exit 1
    fi
}

# Настройка логирования
setup_logging() {
    log "Настройка логирования..."
    
    # Создание директории для логов
    mkdir -p /var/log/$SERVICE_NAME
    chown $APP_USER:$APP_USER /var/log/$SERVICE_NAME
    
    # Настройка logrotate
    cat > /etc/logrotate.d/$SERVICE_NAME << EOF
/var/log/$SERVICE_NAME/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $APP_USER $APP_USER
    postrotate
        systemctl reload $SERVICE_NAME
    endscript
}
EOF
    
    success "Логирование настроено"
}

# Вывод справки по управлению
show_management_info() {
    echo
    echo "=================================="
    echo "🚀 ДЕПЛОЙ ЗАВЕРШЕН УСПЕШНО!"
    echo "=================================="
    echo
    echo "📋 УПРАВЛЕНИЕ БОТОМ:"
    echo "├── Статус:           systemctl status $SERVICE_NAME"
    echo "├── Запуск:           systemctl start $SERVICE_NAME"  
    echo "├── Остановка:        systemctl stop $SERVICE_NAME"
    echo "├── Перезапуск:       systemctl restart $SERVICE_NAME"
    echo "├── Автозапуск ВКЛ:   systemctl enable $SERVICE_NAME"
    echo "└── Автозапуск ВЫКЛ:  systemctl disable $SERVICE_NAME"
    echo
    echo "📊 ЛОГИ И МОНИТОРИНГ:"
    echo "├── Просмотр логов:   journalctl -u $SERVICE_NAME -f"
    echo "├── Логи за сегодня:  journalctl -u $SERVICE_NAME --since today"
    echo "└── Последние логи:   journalctl -u $SERVICE_NAME -n 50"
    echo
    echo "📁 ФАЙЛЫ ПРОЕКТА:"
    echo "├── Код бота:         $APP_DIR"
    echo "├── Конфигурация:     $APP_DIR/.env"
    echo "├── База данных:      $APP_DIR/blood_pressure.db"
    echo "└── Виртуальное окр.: $VENV_DIR"
    echo
    echo "⚠️  ВАЖНЫЕ НАПОМИНАНИЯ:"
    echo "├── Токен бота уже настроен и сохранен в: $APP_DIR/.env"
    echo "├── Для изменения токена: запустите скрипт повторно"
    echo "└── После изменения .env: systemctl restart $SERVICE_NAME"
    echo
    echo "🔄 ДЛЯ ОБНОВЛЕНИЯ БОТА:"
    echo "└── Просто запустите этот скрипт повторно"
    echo
}

# Основная функция
main() {
    echo "🚀 BloodTrackBot Deploy Script"
    echo "=============================="
    
    # Проверка прав root
    check_root
    
    # Определение режима работы
    local deployment_mode=$(check_deployment_mode)
    
    if [[ "$deployment_mode" == "update" ]]; then
        log "Режим: ОБНОВЛЕНИЕ существующей установки"
    else
        log "Режим: ПЕРВОНАЧАЛЬНАЯ УСТАНОВКА"
    fi
    
    # Запрос токена бота
    get_bot_token
    
    # Выполнение шагов деплоя
    if [[ "$deployment_mode" == "install" ]]; then
        install_system_dependencies
        create_app_user
        setup_directories
    fi
    
    setup_repository $deployment_mode
    setup_python_environment $deployment_mode
    setup_configuration
    setup_database
    
    if [[ "$deployment_mode" == "install" ]]; then
        create_systemd_service
        setup_logging
    fi
    
    manage_service $deployment_mode
    
    # Финальная проверка
    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        show_management_info
    else
        error "Что-то пошло не так. Проверьте логи:"
        echo "journalctl -u $SERVICE_NAME -n 20"
        exit 1
    fi
}

# Обработка прерывания
trap 'error "Скрипт прерван пользователем"; exit 1' INT

# Запуск основной функции
main "$@"