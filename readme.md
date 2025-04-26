# 🛡️ Bitwarden Self-Hosted en Proxmox

Este proyecto despliega en **Proxmox** un contenedor **LXC Debian minimalista** con **Docker** preinstalado y el servicio de **Bitwarden**:

- [`vaultwarden/server`](https://hub.docker.com/r/vaultwarden/server): una implementación ligera de Bitwarden escrita en Rust, ideal para servidores autoalojados.

---

# 🔐 1. ¿Qué es Vaultwarden?

Vaultwarden es una alternativa liviana al servidor oficial de Bitwarden. Permite gestionar contraseñas, notas, tarjetas y más, en un entorno seguro y privado.

Características:

- Sincronización entre dispositivos.
- Acceso web, móvil y extensiones de navegador.
- Soporte de 2FA (Autenticación de dos factores).
- API compatible con clientes oficiales de Bitwarden.

---

# ⚙️ 2. Requisitos

- Nodo Proxmox con acceso a Internet.
- Al menos **2 GB de RAM** (recomendado).
- Al menos **2 GB** de espacio libre en el almacenamiento `local`.

---

# 🧪 3. Instalación automática

Ejecuta el siguiente comando desde la **shell del nodo Proxmox**:

```bash
bash <(curl -s https://github.com/esweb-es/proxmox-vaultwarden/blob/main/proxmox-vaultwarden.sh)
```

Este script:

- Crea un contenedor LXC Debian liviano.
- Instala Docker y el plugin docker-compose.
- Despliega automáticamente el servidor Vaultwarden.
- Asigna IP por DHCP al contenedor.
- Solicita la contraseña de root para el contenedor al momento de instalación.

---

# 📂 4. Estructura esperada en el contenedor

```bash
/opt/bitwarden/docker-compose.yml   # Configuración de Vaultwarden (Bitwarden ligero)
```

---

# 🌐 5. Acceso a tu Bitwarden

Una vez desplegado, podrás acceder a Bitwarden desde:

```bash
http://<IP-del-Contenedor>:8000
```

> ☝️ Nota: si quieres asegurar el acceso (HTTPS), puedes integrar un proxy inverso como Nginx Proxy Manager o usar un Cloudflare Tunnel más adelante.

---

# 🧾 Créditos y Licencia

- Proyecto mantenido por [@esweb-es](https://github.com/esweb-es)
- Basado en:
  - [Vaultwarden Server en Docker Hub](https://hub.docker.com/r/vaultwarden/server)
  - [Documentación de Vaultwarden](https://github.com/dani-garcia/vaultwarden)

