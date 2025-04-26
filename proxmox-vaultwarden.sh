#!/usr/bin/env bash

# ========================
# FUNCIONES LOCALES
# ========================
header_info() { echo -e "\n🧠 $1\n"; }
variables() { :; }
color() { :; }
catch_errors() { :; }
msg_ok() { echo -e "✅ $1"; }

# ========================
# CONFIGURACIÓN INICIAL
# ========================
APP="Vaultwarden (Bitwarden Self-Host)"
var_tags="docker vaultwarden bitwarden"
var_cpu="1"
var_ram="1024"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

# ========================
# CONFIGURACIÓN DE PREDIFINIDOS
# ========================
VAULTWARDEN_PASSWORD="your-admin-password"  # Reemplaza con tu contraseña de administración
VAULTWARDEN_PORT="8000"  # Puerto predeterminado
VAULTWARDEN_DOMAIN="vault.mydomain.com"  # Reemplaza con tu dominio

# Contraseña de root para el contenedor
read -rsp "🔐 Ingresa la contraseña que tendrá el usuario root del contenedor: " ROOT_PASSWORD
echo

# ========================
# CONFIGURACIÓN DE PLANTILLA Y ALMACENAMIENTO
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-lvm"

# Asegurar que la plantilla esté disponible
if [[ ! -f "/var/lib/pve/local/template/cache/${TEMPLATE}" ]]; then
  echo "⬇️ Descargando plantilla Debian 12..."
  pveam update
  pveam download $TEMPLATE_STORAGE $TEMPLATE
fi

# ========================
# CREAR CONTENEDOR
# ========================
CTID=$(pvesh get /cluster/nextid)
echo "📦 Creando contenedor LXC ID #$CTID..."

pct create $CTID ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE} \
  -rootfs ${ROOTFS_STORAGE}:${var_disk} \
  -hostname vaultwarden-stack \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

pct start $CTID
sleep 5

# ========================
# CONFIGURAR CONTRASEÑA ROOT
# ========================
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# INSTALAR DOCKER
# ========================
echo "🐳 Instalando Docker dentro del contenedor..."
lxc-attach -n $CTID -- bash -c "
apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# DESPLEGAR VAULTWARDEN
# ========================
echo "🚀 Desplegando Vaultwarden en Docker..."
lxc-attach -n $CTID -- bash -c "
  mkdir -p /opt/vaultwarden && cd /opt/vaultwarden
  cat <<EOF > docker-compose.yml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    restart: always
    environment:
      - WEBSOCKET_ENABLED=true
      - ADMIN_TOKEN=${VAULTWARDEN_PASSWORD}
    ports:
      - ${VAULTWARDEN_PORT}:${VAULTWARDEN_PORT}
    volumes:
      - ./vw-data:/data
EOF
  docker compose up -d
"

msg_ok "Vaultwarden desplegado correctamente en el puerto ${VAULTWARDEN_PORT}"

# ========================
# FINAL
# ========================
LXC_IP=$(pct exec $CTID -- ip a | grep inet | grep eth0 | awk '{print $2}' | cut -d'/' -f1)
msg_ok "🎉 Contenedor LXC #$CTID desplegado correctamente."
echo -e "La IP del contenedor es: ${LXC_IP}:${VAULTWARDEN_PORT}"
echo -e "\nPuedes acceder con: \e[1mpct enter $CTID\e[0m y usar la contraseña de root que proporcionaste."
