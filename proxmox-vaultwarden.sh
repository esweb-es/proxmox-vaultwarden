#!/usr/bin/env bash

# ========================
# FUNCIONES LOCALES
# ========================
header_info() { echo -e "\n🧠 $1\n"; }
variables() { :; }
color() { :; }
catch_errors() { 
  if [ $? -ne 0 ]; then
    echo -e "❌ Se produjo un error. Saliendo..."
    exit 1
  fi
}
msg_ok() { echo -e "✅ $1"; }

# ========================
# CONFIGURACIÓN INICIAL
# ========================
APP="Vaultwarden"
var_tags="docker vaultwarden"
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

# ========================
# PREGUNTAS INTERACTIVAS
# ========================
read -rsp "🔐 Ingresa la contraseña que tendrá el usuario root del contenedor: " ROOT_PASSWORD
echo
read -rp "🌐 Ingresa el dominio donde vas a acceder a Bitwarden (ej: vault.midominio.com): " DOMAIN
read -rp "🔑 Ingresa el ADMIN_TOKEN para la administración web de Vaultwarden: " ADMIN_TOKEN

# Validar que las entradas no estén vacías
if [[ -z "$ROOT_PASSWORD" || -z "$DOMAIN" || -z "$ADMIN_TOKEN" ]]; then
  echo "❌ Todos los campos son obligatorios. Por favor, vuelve a ejecutar el script."
  exit 1
fi

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
  catch_errors
  pveam download $TEMPLATE_STORAGE $TEMPLATE
  catch_errors
fi

# ========================
# CREAR CONTENEDOR
# ========================
CTID=$(pvesh get /cluster/nextid)
echo "📦 Creando contenedor LXC ID #$CTID..."

pct create $CTID ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE} \
  -rootfs ${ROOTFS_STORAGE}:${var_disk} \
  -hostname vaultwarden \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1
catch_errors

pct start $CTID
sleep 5

# ========================
# CONFIGURAR CONTRASEÑA ROOT
# ========================
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"
catch_errors

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
catch_errors

# ========================
# DESPLEGAR BITWARDEN (VAULTWARDEN)
# ========================
echo "🚀 Desplegando Bitwarden (Vaultwarden)..."
lxc-attach -n $CTID -- bash -c '
mkdir -p /opt/bitwarden && cd /opt/bitwarden
cat <<EOF > docker-compose.yml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    environment:
      - DOMAIN='"${DOMAIN}"'
      - ADMIN_TOKEN='"${ADMIN_TOKEN}"'
      - SIGNUPS_ALLOWED=false
    ports:
      - 80:80
    volumes:
      - ./data:/data
EOF
docker compose up -d
'
catch_errors

msg_ok "Bitwarden (Vaultwarden) desplegado correctamente"

# ========================
# FINAL
# ========================
msg_ok "🎉 Contenedor LXC #$CTID desplegado correctamente."
echo -e "\nPuedes acceder con: \e[1mpct enter $CTID\e[0m y usar la contraseña de root que proporcionaste."
