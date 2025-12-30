#!/bin/bash
# docker-install-debian-trixie.sh
# Повний скрипт встановлення Docker на Debian Trixie (Testing)

set -e  # Зупинитись при першій помилці
set -o pipefail  # Зупинитись при помилці в пайпах

# Кольори для виводу
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логування
LOG_FILE="/tmp/docker-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Функція перевірки прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Цей скрипт потрібно запускати з правами root або через sudo"
        exit 1
    fi
}

# Функція перевірки версії Debian
check_debian_version() {
    print_header "Перевірка версії Debian"
    
    if [ ! -f /etc/debian_version ]; then
        print_error "Це не Debian система!"
        exit 1
    fi
    
    DEBIAN_VERSION=$(cat /etc/debian_version)
    print_info "Версія Debian: $DEBIAN_VERSION"
    
    if [[ ! "$DEBIAN_VERSION" =~ "trixie" ]] && [[ ! "$DEBIAN_VERSION" =~ "12" ]]; then
        print_warning "Цей скрипт призначений для Debian Trixie (Testing) або Bookworm (12)"
        read -p "Продовжити? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Функція перевірки архітектури
check_architecture() {
    print_header "Перевірка архітектури системи"
    
    ARCH=$(uname -m)
    print_info "Архітектура: $ARCH"
    
    case $ARCH in
        x86_64|amd64)
            print_success "64-бітна архітектура підтримується"
            ;;
        aarch64|arm64)
            print_success "ARM64 архітектура підтримується"
            ;;
        armv7l)
            print_warning "ARMv7 архітектура має обмежену підтримку"
            ;;
        *)
            print_error "Архітектура $ARCH не підтримується Docker"
            exit 1
            ;;
    esac
}

# Функція перевірки підтримки віртуалізації
check_virtualization() {
    print_header "Перевірка підтримки віртуалізації"
    
    # Перевірка KVM
    if [[ -c /dev/kvm ]]; then
        print_success "KVM доступний (/dev/kvm)"
    else
        print_warning "KVM не знайдений. Docker буде використовувати QEMU емуляцію"
    fi
    
    # Перевірка апаратної віртуалізації
    if command -v lscpu &> /dev/null; then
        if lscpu | grep -q "Virtualization"; then
            VIRT_TYPE=$(lscpu | grep "Virtualization" | awk '{print $2}')
            print_info "Тип віртуалізації: $VIRT_TYPE"
        fi
    fi
    
    # Перевірка VT-x/AMD-V
    if [[ $ARCH == "x86_64" ]] || [[ $ARCH == "amd64" ]]; then
        if grep -Eq '(vmx|svm)' /proc/cpuinfo; then
            print_success "Апаратна віртуалізація (VT-x/AMD-V) доступна"
        else
            print_warning "Апаратна віртуалізація не знайдена. Можуть бути проблеми з продуктивністю"
        fi
    fi
}

# Функція перевірки доступності репозиторіїв
check_repositories() {
    print_header "Перевірка репозиторіїв Debian"
    
    # Оновлення списку пакетів
    print_info "Оновлення списку пакетів..."
    apt-get update
    
    # Перевірка наявності ключових пакетів
    REQUIRED_PACKAGES=("curl" "gnupg" "lsb-release" "ca-certificates")
    MISSING_PACKAGES=()
    
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done
    
    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        print_info "Встановлення необхідних пакетів: ${MISSING_PACKAGES[*]}"
        apt-get install -y "${MISSING_PACKAGES[@]}"
    fi
    
    print_success "Репозиторії та базові пакети готові"
}

# Функція видалення старих версій Docker
remove_old_docker() {
    print_header "Видалення старих версій Docker"
    
    # Список пакетів для видалення
    OLD_PACKAGES=(
        "docker"
        "docker.io"
        "docker-doc"
        "docker-compose"
        "docker-compose-v2"
        "podman-docker"
        "containerd"
        "runc"
    )
    
    for pkg in "${OLD_PACKAGES[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            print_info "Видалення $pkg..."
            apt-get remove -y --purge "$pkg" || true
        fi
    done
    
    # Видалення конфігураційних файлів
    print_info "Очищення залишкових файлів..."
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -rf /etc/docker
    rm -rf /etc/containerd
    
    print_success "Старі версії Docker видалені"
}

# Функція додавання офіційного репозиторію Docker
add_docker_repository() {
    print_header "Додавання офіційного репозиторію Docker"
    
    # Створення директорії для ключів
    install -m 0755 -d /etc/apt/keyrings
    
    # Завантаження ключа GPG
    print_info "Завантаження ключа GPG Docker..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Додавання репозиторію
    print_info "Додавання репозиторію Docker..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Оновлення списку пакетів
    print_info "Оновлення списку пакетів з Docker репозиторієм..."
    apt-get update
    
    print_success "Репозиторій Docker додано"
}

# Функція встановлення Docker
install_docker_packages() {
    print_header "Встановлення Docker"
    
    # Встановлення Docker
    print_info "Встановлення Docker CE, containerd та Docker Compose..."
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    # Встановлення Docker Compose v2 окремо (якщо потрібно)
    if ! command -v docker-compose &> /dev/null; then
        print_info "Встановлення Docker Compose v2..."
        apt-get install -y docker-compose-v2
    fi
    
    print_success "Docker встановлено"
}

# Функція налаштування Docker
configure_docker() {
    print_header "Налаштування Docker"
    
    # Створення групи docker та додавання користувача
    print_info "Створення групи docker..."
    groupadd -f docker
    
    # Додавання поточного користувача до групи docker
    CURRENT_USER=${SUDO_USER:-$USER}
    print_info "Додавання користувача $CURRENT_USER до групи docker..."
    usermod -aG docker "$CURRENT_USER"
    
    # Налаштування демона Docker
    print_info "Налаштування демона Docker..."
    
    # Створення конфігураційного файлу
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "ipv6": false,
  "dns": ["8.8.8.8", "8.8.4.4"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": [
    "https://registry.docker-cn.com"
  ],
  "insecure-registries": []
}
EOF
    
    print_success "Docker налаштовано"
}

# Функція налаштування systemd
configure_systemd() {
    print_header "Налаштування systemd"
    
    # Перезавантаження демона systemd
    print_info "Перезавантаження демона systemd..."
    systemctl daemon-reload
    
    # Включення автозапуску Docker
    print_info "Включення автозапуску Docker..."
    systemctl enable docker.service
    systemctl enable containerd.service
    
    # Запуск Docker
    print_info "Запуск Docker служби..."
    systemctl start docker.service
    
    print_success "Systemd налаштовано"
}

# Функція перевірки встановлення Docker
verify_docker_installation() {
    print_header "Перевірка встановлення Docker"
    
    # Перевірка версії Docker
    print_info "Перевірка версії Docker..."
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        print_success "Docker версія: $DOCKER_VERSION"
    else
        print_error "Docker не встановлений!"
        exit 1
    fi
    
    # Перевірка версії Docker Compose
    print_info "Перевірка версії Docker Compose..."
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version)
        print_success "Docker Compose версія: $COMPOSE_VERSION"
    elif docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        print_success "Docker Compose Plugin версія: $COMPOSE_VERSION"
    else
        print_warning "Docker Compose не знайдений"
    fi
    
    # Тест запуску контейнера
    print_info "Тест запуску контейнера hello-world..."
    if docker run --rm hello-world &> /dev/null; then
        print_success "Тестовий контейнер успішно запущено"
    else
        print_error "Не вдалося запустити тестовий контейнер"
        exit 1
    fi
    
    # Перевірка прав користувача
    print_info "Перевірка прав користувача для Docker..."
    if groups "$CURRENT_USER" | grep -q docker; then
        print_success "Користувач $CURRENT_USER доданий до групи docker"
    else
        print_warning "Користувач $CURRENT_USER не в групі docker. Може знадобитися вийти та увійти знову"
    fi
}

# Функція встановлення додаткових інструментів
install_additional_tools() {
    print_header "Встановлення додаткових інструментів"
    
    # Список корисних інструментів
    TOOLS=(
        "git"
        "htop"
        "jq"
        "vim"
        "nmap"
        "net-tools"
        "tree"
        "wget"
        "zip"
        "unzip"
    )
    
    print_info "Встановлення корисних інструментів..."
    apt-get install -y "${TOOLS[@]}"
    
    # Встановлення Docker completion
    print_info "Встановлення автодоповнення Docker..."
    apt-get install -y bash-completion
    
    # Завантаження completion скриптів
    if [ -d /usr/share/bash-completion/completions ]; then
        curl -fsSL https://raw.githubusercontent.com/docker/docker-ce/master/components/cli/contrib/completion/bash/docker \
            -o /usr/share/bash-completion/completions/docker
        curl -fsSL https://raw.githubusercontent.com/docker/compose/master/contrib/completion/bash/docker-compose \
            -o /usr/share/bash-completion/completions/docker-compose
    fi
    
    print_success "Додаткові інструменти встановлено"
}

# Функція оновлення системи
update_system() {
    print_header "Оновлення системи"
    
    print_info "Оновлення пакетів системи..."
    apt-get update
    apt-get upgrade -y
    apt-get autoremove -y
    apt-get autoclean
    
    print_success "Система оновлена"
}

# Функція налаштування фаєрвола
configure_firewall() {
    print_header "Налаштування фаєрвола"
    
    # Перевірка наявності UFW
    if command -v ufw &> /dev/null; then
        print_info "Налаштування UFW для Docker..."
        
        # Додавання правил для Docker
        ufw allow 2375/tcp comment "Docker Daemon" || true
        ufw allow 2376/tcp comment "Docker Daemon TLS" || true
        ufw reload
        
        print_success "UFW налаштовано"
    else
        print_info "UFW не встановлений, пропускаємо налаштування фаєрвола"
    fi
}

# Функція створення аліасів та налаштування середовища
setup_environment() {
    print_header "Налаштування середовища"
    
    # Додавання аліасів у .bashrc
    BASH_RC="/home/$CURRENT_USER/.bashrc"
    if [ -f "$BASH_RC" ]; then
        print_info "Додавання аліасів Docker у $BASH_RC..."
        
        cat >> "$BASH_RC" << 'EOF'

# Docker aliases
alias d='docker'
alias dc='docker-compose'
alias dcp='docker-compose'
alias dls='docker ps'
alias dlsa='docker ps -a'
alias dimg='docker images'
alias dlog='docker logs'
alias dexec='docker exec -it'
alias dstop='docker stop'
alias dstart='docker start'
alias drm='docker rm'
alias drmi='docker rmi'
alias dprune='docker system prune -af'
alias dstat='docker stats'
alias dvol='docker volume ls'
alias dnet='docker network ls'
alias dbuild='docker build'
alias drun='docker run'
alias dtop='docker top'

# Docker Compose aliases
alias dcup='docker-compose up -d'
alias dcdown='docker-compose down'
alias dcrestart='docker-compose restart'
alias dclogs='docker-compose logs -f'
alias dcbuild='docker-compose build'
alias dcexec='docker-compose exec'

# Kubernetes aliases (if installed)
alias k='kubectl'
alias kctl='kubectl'
alias kctx='kubectl ctx'
alias kns='kubectl ns'
EOF
        
        # Додавання автодоповнення
        cat >> "$BASH_RC" << 'EOF'

# Docker command completion
if [ -f /usr/share/bash-completion/completions/docker ]; then
    source /usr/share/bash-completion/completions/docker
    complete -F _docker d
fi

if [ -f /usr/share/bash-completion/completions/docker-compose ]; then
    source /usr/share/bash-completion/completions/docker-compose
    complete -F _docker_compose dc
fi
EOF
        
        print_success "Аліаси додано"
    fi
}

# Функція створення тестового проекту
create_test_project() {
    print_header "Створення тестового проекту"
    
    TEST_DIR="/home/$CURRENT_USER/docker-test"
    
    print_info "Створення тестової директорії: $TEST_DIR"
    mkdir -p "$TEST_DIR"
    
    # Створення Dockerfile
    cat > "$TEST_DIR/Dockerfile" << 'EOF'
FROM alpine:latest

RUN apk add --no-cache curl

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

CMD ["sh", "-c", "echo 'Docker is working correctly!' && sleep infinity"]
EOF
    
    # Створення docker-compose.yml
    cat > "$TEST_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  test-app:
    build: .
    container_name: docker-test-app
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./data:/data
    environment:
      - TEST_ENV=docker-test
    networks:
      - test-network

  nginx:
    image: nginx:alpine
    container_name: docker-test-nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - test-app
    networks:
      - test-network

networks:
  test-network:
    driver: bridge

volumes:
  data:
EOF
    
    # Створення nginx.conf
    cat > "$TEST_DIR/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        
        location / {
            return 200 'Docker test successful!';
            add_header Content-Type text/plain;
        }
        
        location /health {
            access_log off;
            return 200 'healthy\n';
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    # Створення скрипту для тестування
    cat > "$TEST_DIR/test-docker.sh" << 'EOF'
#!/bin/bash
echo "=== Docker Installation Test ==="
echo

# Test 1: Docker version
echo "1. Docker Version:"
docker --version
echo

# Test 2: Docker Compose version
echo "2. Docker Compose Version:"
docker-compose --version || docker compose version
echo

# Test 3: Docker daemon status
echo "3. Docker Daemon Status:"
systemctl is-active docker
echo

# Test 4: Test container
echo "4. Running test container:"
docker run --rm hello-world | grep -A1 "Hello from Docker"
echo

# Test 5: Build test image
echo "5. Building test image:"
docker build -t docker-test-image .
echo

# Test 6: Run test container
echo "6. Running test container:"
docker run -d --name test-container docker-test-image
sleep 2
docker ps | grep test-container
echo

# Test 7: Docker Compose test
echo "7. Docker Compose test:"
docker-compose up -d
sleep 5
docker-compose ps
echo

# Test 8: Cleanup
echo "8. Cleaning up:"
docker stop test-container && docker rm test-container
docker rmi docker-test-image
docker-compose down
echo

echo "=== All tests completed ==="
EOF
    
    chmod +x "$TEST_DIR/test-docker.sh"
    chown -R "$CURRENT_USER:$CURRENT_USER" "$TEST_DIR"
    
    print_success "Тестовий проект створено в $TEST_DIR"
    print_info "Для тестування виконайте: cd $TEST_DIR && ./test-docker.sh"
}

# Функція вирішення поширених проблем
troubleshooting_tips() {
    print_header "Поради з вирішення проблем"
    
    cat << EOF
${YELLOW}Поширені проблеми та їх вирішення:${NC}

1. ${BLUE}Проблема:${NC} "Got permission denied while trying to connect to the Docker daemon socket"
   ${GREEN}Рішення:${NC} Додайте користувача до групи docker та перезайдіть в систему:
   sudo usermod -aG docker \$USER && newgrp docker

2. ${BLUE}Проблема:${NC} Docker не запускається
   ${GREEN}Рішення:${NC} Перевірте статус та логи:
   sudo systemctl status docker
   sudo journalctl -xu docker

3. ${BLUE}Проблема:${NC} Немає доступу до інтернету з контейнерів
   ${GREEN}Рішення:${NC} Перевірте налаштування мережі:
   docker network ls
   docker network inspect bridge

4. ${BLUE}Проблема:${NC} Помилка з overlay2 storage driver
   ${GREEN}Рішення:${NC} Очистіть дані Docker:
   sudo systemctl stop docker
   sudo rm -rf /var/lib/docker
   sudo systemctl start docker

5. ${BLUE}Проблема:${NC} Контейнери не запускаються через cgroup v2
   ${GREEN}Рішення:${NC} Додайте параметр до ядра:
   Добавьте в /etc/default/grub: systemd.unified_cgroup_hierarchy=0
   sudo update-grub && sudo reboot

${YELLOW}Корисні команди:${NC}
• Переглянути логи Docker: ${GREEN}sudo journalctl -fu docker${NC}
• Інформація про систему Docker: ${GREEN}docker info${NC}
• Видалити всі невикористовувані ресурси: ${GREEN}docker system prune -af${NC}
• Моніторинг контейнерів: ${GREEN}docker stats${NC}
• Переглянути дискове споживання: ${GREEN}docker system df${NC}
EOF
}

# Функція перевірки доступності портів
check_ports() {
    print_header "Перевірка зайнятих портів"
    
    # Список портів, які використовує Docker
    DOCKER_PORTS=(2375 2376 2377 5000 7946 4789)
    
    print_info "Перевірка портів, які може використовувати Docker..."
    
    for port in "${DOCKER_PORTS[@]}"; do
        if ss -tuln | grep ":$port " > /dev/null; then
            SERVICE=$(ss -tulnp | grep ":$port " | awk '{print $7}')
            print_warning "Порт $port зайнятий: $SERVICE"
        else
            print_success "Порт $port вільний"
        fi
    done
}

# Функція перевірки ресурсів системи
check_system_resources() {
    print_header "Перевірка ресурсів системи"
    
    # Перевірка оперативної пам'яті
    TOTAL_MEM=$(free -h | awk '/^Mem:/ {print $2}')
    AVAILABLE_MEM=$(free -h | awk '/^Mem:/ {print $7}')
    print_info "Загальна пам'ять: $TOTAL_MEM"
    print_info "Доступна пам'ять: $AVAILABLE_MEM"
    
    # Перевірка дискового простору
    DISK_SPACE=$(df -h / | awk 'NR==2 {print $4}')
    print_info "Вільне місце на диску: $DISK_SPACE"
    
    # Перевірка процесора
    CPU_CORES=$(nproc)
    print_info "Кількість ядер CPU: $CPU_CORES"
    
    # Рекомендації
    if [[ $(echo $AVAILABLE_MEM | sed 's/[^0-9]*//g') -lt 2 ]]; then
        print_warning "Мало оперативної пам'яті. Docker потребує мінімум 2GB для комфортної роботи"
    fi
    
    if [[ $(echo $DISK_SPACE | sed 's/[^0-9]*//g') -lt 10 ]]; then
        print_warning "Мало дискового простору. Рекомендується щонайменше 10GB для Docker"
    fi
}

# Функція створення резервної копії налаштувань
backup_configuration() {
    print_header "Створення резервної копії налаштувань"
    
    BACKUP_DIR="/tmp/docker-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Копіювання важливих файлів
    FILES_TO_BACKUP=(
        "/etc/docker/daemon.json"
        "/etc/systemd/system/docker.service.d/"
        "/etc/apt/sources.list.d/docker.list"
        "/etc/apt/keyrings/docker.gpg"
    )
    
    for file in "${FILES_TO_BACKUP[@]}"; do
        if [ -e "$file" ]; then
            cp -r "$file" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    done
    
    # Створення архіву
    tar -czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_DIR" .
    rm -rf "$BACKUP_DIR"
    
    print_success "Резервна копія створена: $BACKUP_DIR.tar.gz"
}

# Головна функція
main() {
    clear
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}    Docker Installer for Debian Trixie         ${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${YELLOW}Лог файл: $LOG_FILE${NC}"
    echo
    
    # Запит на підтвердження
    print_warning "Цей скрипт встановить Docker на Debian Trixie"
    print_warning "Будуть внесені зміни в систему"
    echo
    read -p "Продовжити встановлення? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Встановлення скасовано"
        exit 0
    fi
    
    # Виконання всіх функцій
    check_root
    check_debian_version
    check_architecture
    check_virtualization
    check_system_resources
    check_ports
    backup_configuration
    update_system
    check_repositories
    remove_old_docker
    add_docker_repository
    install_docker_packages
    configure_docker
    configure_systemd
    configure_firewall
    verify_docker_installation
    install_additional_tools
    setup_environment
    create_test_project
    
    # Фінальне повідомлення
    print_header "Встановлення завершено успішно!"
    
    cat << EOF
    
${GREEN}🎉 Docker успішно встановлено на Debian Trixie!${NC}

${YELLOW}Наступні кроки:${NC}
1. ${BLUE}Вийдіть та знову увійдіть в систему${NC} для застосування груп
2. ${BLUE}Протестуйте встановлення:${NC}
   cd ~/docker-test && ./test-docker.sh
3. ${BLUE}Перевірте інсталяцію:${NC}
   docker --version
   docker run hello-world

${YELLOW}Корисні посилання:${NC}
• Docker документація: https://docs.docker.com/
• Docker Hub: https://hub.docker.com/
• Docker Compose документація: https://docs.docker.com/compose/

${YELLOW}Для перегляду логу встановлення:${NC}
   less $LOG_FILE

${RED}Увага!${NC} Не забудьте вийти та увійти знову для застосування змін груп!
EOF
    
    troubleshooting_tips
    
    # Запит на перезавантаження
    echo
    read -p "Бажаєте перезавантажити систему зараз? (рекомендується) (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Перезавантаження системи..."
        reboot
    else
        print_warning "Для повної роботи Docker необхідно перезавантажити систему або вийти/увійти"
    fi
}

# Обробка помилок
handle_error() {
    local exit_code=$?
    local line_no=$1
    
    print_error "Помилка в рядку $line_no (код: $exit_code)"
    print_error "Детальніше в лог-файлі: $LOG_FILE"
    
    # Запис останніх 20 рядків логу
    print_header "Останні рядки логу:"
    tail -20 "$LOG_FILE"
    
    exit $exit_code
}

# Встановлення обробника помилок
trap 'handle_error $LINENO' ERR

# Запуск головної функції
main "$@"
