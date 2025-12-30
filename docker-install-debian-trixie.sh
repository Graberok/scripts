#!/bin/bash
# check-docker-install.sh

echo "=== Перевірка встановлення Docker на Debian Trixie ==="
echo

# 1. Перевірка Docker
echo "1. Docker:"
if command -v docker &> /dev/null; then
    docker --version
else
    echo "Docker не встановлено"
fi
echo

# 2. Перевірка Docker Compose
echo "2. Docker Compose:"
if command -v docker-compose &> /dev/null; then
    docker-compose --version
elif docker compose version &> /dev/null; then
    docker compose version
else
    echo "Docker Compose не встановлено"
fi
echo

# 3. Перевірка служби
echo "3. Служба Docker:"
systemctl is-active docker
echo

# 4. Тест контейнера
echo "4. Тест контейнера:"
docker run --rm hello-world | grep -A1 "Hello"
echo

# 5. Права користувача
echo "5. Права користувача:"
if groups $USER | grep -q docker; then
    echo "Користувач $USER в групі docker"
else
    echo "Користувач $USER НЕ в групі docker"
fi
echo

echo "=== Перевірка завершена ==="
