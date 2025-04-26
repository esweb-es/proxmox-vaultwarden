#!/bin/bash
# ================================================
# Script: proxmox-vaultwarden.sh
# Despliegue de Vaultwarden en un contenedor LXC
# ================================================

set -euo pipefail

# Variables
TEMPLATE="debian-12-standard_12.2-1_amd64.tar.zst"
STORAGE="local"
HOSTNAME="vaultwarden"
PASSWORD="vaultwarden"
MEMORY="512"
CORE="1"
DISK="4"
NET="name=eth0,bridge=vmbr0,ip=dhcp"
CTID=$(pvesh get /cluster/nextid)

echo "🛠️ Creando contenedor LXC..."

# Descargar plantilla si no existe
if ! pveam available | grep -q "$TEMPLATE"; then
  echo "Descargando plantilla Debian 12..."
  pveam update
  pveam download $STORAGE $TEMPLATE
fi

# Crear contenedor
pct create $CTID $STORAGE:vztmpl/$TEMPLATE \
  --hostname $HOSTNAME \
  --cores $CORE \
  --memory $MEMORY \
  --rootfs $STORAGE:$DISK \
  --net0 $NET \
  --password $PASSWORD \
  --unprivileged 1 \
  --features nesting=1

echo "✅ Contenedor LXC $CTID creado."

# Iniciar contenedor
pct start $CTID
sleep 5

echo "🚀 Instalando Docker dentro del contenedor..."

# Comandos dentro del contenedor
pct exec $CTID -- bash -c "
  apt update &&
  apt install -y ca-certificates curl gnupg lsb-release &&
  mkdir -p /etc/apt/keyrings &&
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null &&
  apt update &&
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

echo "✅ Docker instalado."

echo "📂 Preparando estructura de Vaultwarden..."

pct exec $CTID -- bash -c "
  mkdir -p /opt/vaultwarden &&
  bash -c 'cat > /opt/vaultwarden/docker-compose.yml' <<EOF
version: \"3.8\"

services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    network_mode: bridge

    ports:
      - 8100:80

    volumes:
      - /opt/vaultwarden:/data

    environment:
      - TZ=Europe/Madrid
      - INVITATIONS_ALLOWED=false
      - SHOW_PASSWORD_HINT=false
      - SIGNUPS_ALLOWED=false
      - ICON_CACHE_TTL=0
      - ICON_CACHE_NEGTTL=0
EOF
"

echo "📦 Lanzando Vaultwarden con Docker Compose..."

pct exec $CTID -- bash -c "
  cd /opt/vaultwarden &&
  docker compose up -d
"

echo "🎉 Vaultwarden desplegado exitosamente en el contenedor LXC ID: $CTID."
echo "🌐 Accede a tu Vaultwarden en: http://IP-DEL-CONTENEDOR:8100"
