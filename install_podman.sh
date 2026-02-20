#!/bin/bash

IMAGE_NAME="repo2.ros.chat/roschat-lite:v3"
CONTAINER_NAME="roschat"
set -e

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Скрипт должен быть запущен с правами root (sudo)."
  exit 1
fi

# Функция определения пакетного менеджера и установки Podman
install_podman() {
    echo "----------------------------------------------------"
    echo "Определение ОС и установка Podman..."
    
    if command -v podman >/dev/null 2>&1; then
        echo "Podman уже установлен."
        podman --version
        return 0
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "Обнаружена ОС: $PRETTY_NAME"
        
        if command -v dnf >/dev/null 2>&1; then
            echo "Используется DNF. Установка podman..."
            dnf install -y podman
        elif command -v yum >/dev/null 2>&1; then
            echo "Используется YUM. Установка podman..."
            yum install -y podman
        elif command -v apt-get >/dev/null 2>&1; then
            echo "Используется APT. Установка podman..."
            apt-get update
            apt-get install -y podman
        elif command -v zypper >/dev/null 2>&1; then
            echo "Используется Zypper. Установка podman..."
            zypper install -y podman
        elif command -v pacman >/dev/null 2>&1; then
             echo "Используется Pacman. Установка podman..."
             pacman -Sy --noconfirm podman
        else
            echo "ОШИБКА: Не удалось определить пакетный менеджер. Установите Podman вручную."
            exit 1
        fi
    else
        echo "ОШИБКА: Файл /etc/os-release не найден. Неизвестная ОС."
        exit 1
    fi
    
    echo "Podman успешно установлен."
}

# Развертывание приложения
deploy_roschat() {
    echo "----------------------------------------------------"
    echo "Развертывание RosChat в Podman..."

    # Проверка, запущен ли уже контейнер с таким именем
    if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Контейнер ${CONTAINER_NAME} уже существует. Пересоздание..."
        podman rm -f "${CONTAINER_NAME}"
    fi

    # Разрешаем форвардинг пакетов (нужно для доступа извне в Podman на некоторых ОС)
    echo "Настройка сети (iptables FORWARD ACCEPT)..."
    iptables -P FORWARD ACCEPT || echo "Предупреждение: Не удалось настроить iptables. Проверьте настройки фаервола вручную."

    echo "Запуск контейнера..."
    
    # Формируем команду как массив аргументов (это защищает от ошибок с пробелами и переносами строк)
    PODMAN_CMD=(
        podman run -d
        --name "${CONTAINER_NAME}"
        --restart=always
        --systemd=always
        -p 80:80/tcp
        -p 443:443/tcp
        -p 1110:1110/tcp
        -p 3478:3478/tcp
        -p 3479:3479/tcp
        -p 3478:3478/udp
        -p 3479:3479/udp
        -p 49152-49182:49152-49182/udp
        -v "roschat_server:/opt/roschat-server:Z"
        -v "roschat_pgsql:/var/lib/pgsql:Z"
        -v "roschat_wlan:/var/db/wlan:Z"
        -v "roschat_email:/etc/roschat-email:Z"
        "${IMAGE_NAME}"
    )

    # Запускаем команду
    "${PODMAN_CMD[@]}"

    echo "----------------------------------------------------"
    echo "Готово! Статус контейнера:"
    podman ps --filter "name=${CONTAINER_NAME}"
    
    echo ""
    echo "Включение автозапуска контейнера..."
    systemctl enable --now podman-restart
    echo "Автозапуск включен"
    echo ""
    echo "Для просмотра логов используйте: podman logs ${CONTAINER_NAME}"
    echo "Для входа в контейнер: podman exec -it ${CONTAINER_NAME} /bin/bash"
    echo "Для управления сервисами внутри: podman exec -it ${CONTAINER_NAME} systemctl status"
}

# Main execution
install_podman
deploy_roschat
