#!/bin/bash
set -e # Salir inmediatamente si un comando falla

# ================================
# Script para crear un contenedor LXC en Proxmox y desplegar Vaultwarden en Docker
# ================================

# --- Configuración de Proxmox (Valores por defecto) ---
DEFAULT_TEMPLATE="debian-11-standard_11.0-1_amd64.tar.gz" # Ajusta tu plantilla por defecto
DEFAULT_BRIDGE="vmbr0"
DEFAULT_VLAN_TAG="" # Poner un número si usas VLAN, ej "100"
DEFAULT_STORAGE="local-lvm"
DEFAULT_ROOTFS_SIZE="8" # GB
DEFAULT_MEMORY="1024" # MB
DEFAULT_CORES="2"
DEFAULT_HOST_DATA_DIR_BASE="/mnt/data/vaultwarden" # Directorio base en el HOST para los datos
DEFAULT_CONTAINER_APP_DIR="/opt/vaultwarden" # Directorio dentro del LXC para docker-compose.yml
DEFAULT_CONTAINER_DATA_DIR="/data" # Directorio de datos dentro del contenedor Docker de Vaultwarden

# --- Entradas del Usuario ---
read -p "Ingresa el ID del contenedor LXC en Proxmox (ej. 101): " LXC_ID
read -p "Ingresa la plantilla LXC a usar [$DEFAULT_TEMPLATE]: " LXC_TEMPLATE
LXC_TEMPLATE=${LXC_TEMPLATE:-$DEFAULT_TEMPLATE}
read -sp "Ingresa la contraseña para el usuario root del contenedor LXC: " LXC_PASSWORD
echo
read -p "Ingresa el bridge de red Proxmox [$DEFAULT_BRIDGE]: " BRIDGE
BRIDGE=${BRIDGE:-$DEFAULT_BRIDGE}
read -p "Ingresa la etiqueta VLAN (dejar vacío si no se usa) [$DEFAULT_VLAN_TAG]: " VLAN_TAG
VLAN_TAG=${VLAN_TAG:-$DEFAULT_VLAN_TAG}
read -p "Ingresa el almacenamiento Proxmox para el disco root [$DEFAULT_STORAGE]: " STORAGE
STORAGE=${STORAGE:-$DEFAULT_STORAGE}
read -p "Ingresa el tamaño del disco root en GB [$DEFAULT_ROOTFS_SIZE]: " ROOTFS_SIZE
ROOTFS_SIZE=${ROOTFS_SIZE:-$DEFAULT_ROOTFS_SIZE}
read -p "Ingresa la memoria en MB [$DEFAULT_MEMORY]: " MEMORY
MEMORY=${MEMORY:-$DEFAULT_MEMORY}
read -p "Ingresa el número de cores [$DEFAULT_CORES]: " CORES
CORES=${CORES:-$DEFAULT_CORES}

# Validar ID
if ! [[ "$LXC_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: El ID del contenedor debe ser un número."
    exit 1
fi
# Validar que la plantilla exista (básico)
if [ ! -f "/var/lib/vz/template/cache/$LXC_TEMPLATE" ]; then
    echo "Error: La plantilla $LXC_TEMPLATE no se encuentra en /var/lib/vz/template/cache/"
    echo "Asegúrate de haberla descargado en Proxmox."
    exit 1
fi

# --- Crear Ruta de Datos en el Host ---
HOST_DATA_DIR="${DEFAULT_HOST_DATA_DIR_BASE}/data_${LXC_ID}"
echo "Se usarán los siguientes directorios:"
echo " - Directorio de datos en el HOST Proxmox: $HOST_DATA_DIR"
echo " - Directorio de la app dentro del LXC: $DEFAULT_CONTAINER_APP_DIR"
echo " - Directorio de datos dentro del contenedor Docker: $DEFAULT_CONTAINER_DATA_DIR"
read -p "¿Continuar? (s/N): " CONFIRM_PATHS
if [[ ! "$CONFIRM_PATHS" =~ ^[sS]$ ]]; then
    echo "Operación cancelada."
    exit 0
fi

# Intentar crear el directorio en el host (requiere permisos)
if [ ! -d "$HOST_DATA_DIR" ]; then
    echo "Intentando crear el directorio de datos en el host: $HOST_DATA_DIR"
    if mkdir -p "$HOST_DATA_DIR"; then
        echo "Directorio creado exitosamente."
    else
        echo "Error: No se pudo crear $HOST_DATA_DIR. Créalo manualmente y asegúrate de que tenga permisos adecuados."
        exit 1
    fi
fi


# --- Crear Contenedor LXC ---
# Construir opción de red
NET_OPTS="name=eth0,bridge=$BRIDGE,ip=dhcp"
if [ -n "$VLAN_TAG" ]; then
    if [[ "$VLAN_TAG" =~ ^[0-9]+$ ]]; then
        NET_OPTS+=",tag=$VLAN_TAG"
    else
        echo "Advertencia: La etiqueta VLAN '$VLAN_TAG' no es un número válido. Se ignorará."
    fi
fi

echo "Creando contenedor LXC $LXC_ID usando $LXC_TEMPLATE..."
pct create $LXC_ID "/var/lib/vz/template/cache/$LXC_TEMPLATE" \
    --hostname vaultwarden-${LXC_ID} \
    --memory $MEMORY \
    --cores $CORES \
    --rootfs $STORAGE:$ROOTFS_SIZE \
    --net0 $NET_OPTS \
    --password $LXC_PASSWORD \
    --features nesting=1 # Habilitar nesting para Docker

echo "Contenedor LXC creado."

# --- Iniciar Contenedor y Obtener IP ---
echo "Iniciando el contenedor LXC..."
pct start $LXC_ID

echo "Esperando a que el contenedor obtenga una IP (máx. 30 segundos)..."
LXC_IP=""
attempts=0
max_attempts=10
while [ -z "$LXC_IP" ] && [ $attempts -lt $max_attempts ]; do
    sleep 3
    LXC_IP=$(pct exec $LXC_ID -- hostname -I | awk '{print $1}' 2>/dev/null)
    if [ -z "$LXC_IP" ]; then
         # Fallback por si hostname -I no funciona al principio
         LXC_IP=$(pct exec $LXC_ID -- ip a show eth0 | grep "inet\b" | awk '{print $2}' | cut -d'/' -f1 2>/dev/null)
    fi
    attempts=$((attempts + 1))
    echo -n "." # Indicador de progreso
done
echo # Nueva línea después de los puntos

if [ -z "$LXC_IP" ]; then
    echo "Error: No se pudo obtener la IP del contenedor LXC $LXC_ID."
    # Opcional: Limpiar
    # echo "Deteniendo y eliminando el contenedor..."
    # pct stop $LXC_ID || true
    # pct destroy $LXC_ID --purge || true
    exit 1
fi
echo "La IP del contenedor LXC es: $LXC_IP"

# --- Instalar Docker y Docker Compose V1 ---
echo "Actualizando paquetes e instalando dependencias en el contenedor LXC..."
pct exec $LXC_ID -- bash -c "apt-get update && apt-get install -y curl docker.io"

# Obtener la última versión de Docker Compose V1 (o usar una fija)
COMPOSE_VERSION="1.29.2" # Puedes cambiar esto o usar el método de detección de la sugerencia anterior
echo "Instalando Docker Compose v$COMPOSE_VERSION en el contenedor LXC..."
pct exec $LXC_ID -- bash -c "curl -L \"https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
pct exec $LXC_ID -- bash -c "chmod +x /usr/local/bin/docker-compose"
echo "Verificando instalación de Docker Compose..."
pct exec $LXC_ID -- docker-compose --version

# --- Configurar Vaultwarden ---
# Preguntar por el dominio (sin protocolo ahora, ya que manejaremos HTTP)
read -p "Ingresa el dominio que USARÁS para acceder a Vaultwarden (ej. bw.example.com): " VW_DOMAIN
# Validar que no esté vacío (puedes añadir más validaciones si quieres)
if [ -z "$VW_DOMAIN" ]; then
    echo "Error: El dominio no puede estar vacío."
    exit 1
fi
# El DOMAIN para Vaultwarden necesita el protocolo, asumimos HTTPS porque es lo ideal con reverse proxy
DOMAIN_URL="https://$VW_DOMAIN"

# Crear directorio para docker-compose.yml dentro del LXC
pct exec $LXC_ID -- mkdir -p "$DEFAULT_CONTAINER_APP_DIR"

# Crear archivo docker-compose.yml
COMPOSE_FILE_PATH="$DEFAULT_CONTAINER_APP_DIR/docker-compose.yml"
echo "Creando archivo $COMPOSE_FILE_PATH dentro del contenedor LXC..."

pct exec $LXC_ID -- bash -c "cat > '$COMPOSE_FILE_PATH' <<EOL
version: '3.7' # Usar una versión más reciente si es compatible con tu docker-compose
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden_${LXC_ID} # Nombre único del contenedor Docker
    restart: always
    environment:
      - DOMAIN=$DOMAIN_URL # Importante para URLs correctas, incluso si se accede por HTTP inicialmente
      # - ADMIN_TOKEN= # Descomenta y añade un token seguro si quieres la página de admin
      # - SMTP_HOST= # Configura SMTP para invitar usuarios, etc.
      # - SMTP_PORT=
      # - SMTP_FROM=
      # - SMTP_SECURITY= # starttls, force_tls, o off
      # - SMTP_USERNAME=
      # - SMTP_PASSWORD=
    volumes:
      - '$HOST_DATA_DIR:$DEFAULT_CONTAINER_DATA_DIR' # Mapeo persistente Host -> Contenedor Docker
    ports:
      - '80:80' # Escucha en puerto 80 para el reverse proxy
EOL"

# --- Iniciar Vaultwarden ---
echo "Iniciando Vaultwarden con Docker Compose dentro del contenedor..."
pct exec $LXC_ID -- bash -c "cd '$DEFAULT_CONTAINER_APP_DIR' && docker-compose up -d"

# --- Mensajes Finales ---
echo "========================================================================"
echo " Despliegue de Vaultwarden completado en el Contenedor LXC ID $LXC_ID"
echo "========================================================================"
echo " - IP del Contenedor LXC: $LXC_IP"
echo " - Acceso HTTP inicial (si el DNS aún no apunta): http://$LXC_IP"
echo " - Dominio configurado en Vaultwarden: $DOMAIN_URL"
echo " - Datos de Vaultwarden almacenados en el HOST Proxmox en: $HOST_DATA_DIR"
echo ""
echo " === PASOS SIGUIENTES RECOMENDADOS ==="
echo " 1. Configura tu DNS para que '$VW_DOMAIN' apunte a la IP '$LXC_IP'."
echo " 2. Configura un REVERSE PROXY (como Nginx Proxy Manager, Caddy o Traefik)"
echo "    para gestionar HTTPS/SSL para '$VW_DOMAIN' y redirigir el tráfico a http://$LXC_IP:80."
echo " 3. Considera configurar el ADMIN_TOKEN y SMTP en '$COMPOSE_FILE_PATH' dentro del LXC"
echo "    (después de editar, reinicia con: pct exec $LXC_ID -- bash -c \"cd '$DEFAULT_CONTAINER_APP_DIR' && docker-compose down && docker-compose up -d\")"
echo "========================================================================"

exit 0
