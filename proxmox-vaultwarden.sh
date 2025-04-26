#!/bin/bash

# ================================
# Script para crear un contenedor LXC en Proxmox y desplegar Vaultwarden en Docker
# ================================

# Preguntar por el ID del contenedor LXC
read -p "Ingresa el ID del contenedor LXC en Proxmox (ej. 101): " LXC_ID

# Preguntar por la plantilla LXC a usar (por ejemplo, Debian 11)
read -p "Ingresa la plantilla LXC a usar (ej. debian-11-standard_11.0-1_amd64.tar.gz): " LXC_TEMPLATE

# Preguntar por la contraseña del contenedor LXC
read -sp "Ingresa la contraseña para el contenedor LXC: " LXC_PASSWORD
echo

# Crear el contenedor LXC en Proxmox
echo "Creando contenedor LXC en Proxmox con ID $LXC_ID usando la plantilla $LXC_TEMPLATE..."
pct create $LXC_ID /var/lib/vz/template/cache/$LXC_TEMPLATE --hostname vaultwarden --memory 1024 --cores 2 --rootfs local-lvm:8 --net0 name=eth0,bridge=vmbr0,ip=dhcp,tag=100 --password $LXC_PASSWORD

# Iniciar el contenedor LXC
echo "Iniciando el contenedor LXC..."
pct start $LXC_ID

# Obtener la IP del contenedor LXC
LXC_IP=$(pct exec $LXC_ID -- ip a | grep inet | grep eth0 | awk '{print $2}' | cut -d'/' -f1)

# Mostrar IP del contenedor
echo "La IP del contenedor LXC es: $LXC_IP"

# Acceder al contenedor LXC e instalar Docker
echo "Instalando Docker en el contenedor LXC..."
pct exec $LXC_ID -- bash -c "apt update && apt install -y docker.io"

# Instalar Docker Compose
echo "Instalando Docker Compose en el contenedor LXC..."
pct exec $LXC_ID -- bash -c "curl -L \"https://github.com/docker/compose/releases/download/1.29.2/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
pct exec $LXC_ID -- bash -c "chmod +x /usr/local/bin/docker-compose"

# Preguntar por el dominio con protocolo (http:// o https://)
read -p "Ingresa el dominio con protocolo (ej. https://bw.example.com): " DOMAIN
if [[ ! "$DOMAIN" =~ ^https?:// ]]; then
    echo "Error: El dominio debe incluir el protocolo (http:// o https://)."
    exit 1
fi

# Preguntar por la ruta de datos donde se almacenarán los archivos de Vaultwarden
read -p "Ingresa la ruta completa para almacenar los datos de Vaultwarden (ej. /path/to/vaultwarden/data): " DATA_DIR
pct exec $LXC_ID -- mkdir -p "$DATA_DIR"

# Preguntar por el archivo docker-compose.yml
read -p "Ingresa la ruta del archivo docker-compose.yml (ej. ./docker-compose.yml): " DOCKER_COMPOSE_FILE

# Crear el archivo docker-compose.yml dentro del contenedor
echo "Creando archivo docker-compose.yml dentro del contenedor LXC..."
pct exec $LXC_ID -- bash -c "cat > $DOCKER_COMPOSE_FILE <<EOL
version: '3'
services:
  vaultwarden:
    image: vaultwarden/server:1.33.2
    environment:
      - DOMAIN=$DOMAIN
    ports:
      - '80:80'
      - '443:443'
    volumes:
      - '$DATA_DIR:/data'
    restart: always
EOL"

# Iniciar el contenedor con Docker Compose
echo "Iniciando Vaultwarden con Docker Compose dentro del contenedor..."
pct exec $LXC_ID -- docker-compose -f $DOCKER_COMPOSE_FILE up -d

echo "Vaultwarden desplegado exitosamente en el contenedor LXC con ID $LXC_ID."
