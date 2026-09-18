#!/usr/bin/env bash
# Prepara el appliance para desplegar Bragi con el receptor de despliegue-continuo (ADR-0003).
# Idempotente y sin secretos. Ejecutar como root:
#   sudo BRANCH=main TZ_HOGAR=America/Caracas bash deploy/cd/bootstrap-midgard.sh
#
# NO migra datos ni para nada: eso es deploy/cd/migrar-desde-manual.sh, en la ventana de corte.
# Despues: webhook en GitHub (docs/05-deployment/deployment.md, paso 3).
set -euo pipefail

APP_DIR=${APP_DIR:-/srv/apps/bragi}
REPO=${REPO:-https://github.com/higerotech/bragi.git}
BRANCH=${BRANCH:-main}
LAN_IF=${LAN_IF:-lan}
DATOS=${BRAGI_DATA:-/var/lib/bragi}
APPS_YML=/etc/cd-receiver/apps.yml

[ "$(id -u)" = 0 ] || { echo "ejecutar con sudo"; exit 1; }
id deploy >/dev/null 2>&1 || { echo "no existe el usuario deploy: instalar despliegue-continuo primero"; exit 1; }

echo "== 1. Usuario de sistema bragi (ADR-0007)"
if ! id bragi >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir "$DATOS" --shell /usr/sbin/nologin bragi
    echo "   creado: $(id bragi)"
fi
for g in render video; do
    getent group "$g" >/dev/null && usermod -aG "$g" bragi
done
echo "   $(id bragi)"

echo "== 2. Datos persistentes en $DATOS (fuera del clon, disco local)"
install -d -o bragi -g bragi -m 0750 "$DATOS" "$DATOS/config" "$DATOS/cache"
echo "   $(stat -c '%a %U:%G %n' "$DATOS")"

echo "== 3. Clon del repositorio en $APP_DIR (dueno: deploy)"
if [ ! -d "$APP_DIR/.git" ]; then
    install -d -o deploy -g deploy -m 0750 "$APP_DIR"
    sudo -u deploy git clone --quiet "$REPO" "$APP_DIR"
fi
sudo -u deploy git -C "$APP_DIR" fetch --quiet origin "$BRANCH"
sudo -u deploy git -C "$APP_DIR" checkout --quiet --detach "origin/$BRANCH"
echo "   $(sudo -u deploy git -C "$APP_DIR" log -1 --format='%h %s')"

echo "== 4. deploy/.env (solo si no existe; nunca se sobrescribe)"
ENV_FILE="$APP_DIR/deploy/.env"
LAN_IP=$(ip -4 -o addr show "$LAN_IF" | awk '{print $4}' | cut -d/ -f1)
LAN_SUBNET=$(ip -4 route show dev "$LAN_IF" proto kernel scope link | awk '{print $1}' | head -1)
[ -n "$LAN_IP" ] && [ -n "$LAN_SUBNET" ] || { echo "   no pude leer la IP o la subred de $LAN_IF"; exit 1; }
if [ ! -f "$ENV_FILE" ]; then
    sudo -u deploy install -m 0600 "$APP_DIR/deploy/.env.example" "$ENV_FILE"
    fijar() { sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"; }
    fijar HOST_LAN_IP "$LAN_IP"
    fijar LAN_SUBNET "$LAN_SUBNET"
    fijar BRAGI_DATA "$DATOS"
    fijar PUID "$(id -u bragi)"
    fijar PGID "$(id -g bragi)"
    fijar RENDER_GID "$(getent group render | cut -d: -f3)"
    fijar VIDEO_GID "$(getent group video | cut -d: -f3)"
    # La zona de la CASA, no la del host: el appliance suele ir en UTC, y la ventana de tareas
    # pesadas (01:00-06:00, hora del contenedor) caeria en plena noche. Pasar TZ_HOGAR.
    tz_host="$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)"
    fijar TZ "${TZ_HOGAR:-$tz_host}"
    case "${TZ_HOGAR:-$tz_host}" in
        UTC|Etc/UTC) echo "   AVISO: TZ=UTC; define TZ_HOGAR (p. ej. America/Caracas) o corrige deploy/.env" ;;
    esac
    fijar DEPLOY_UID "$(id -u deploy)"
    fijar DEPLOY_GID "$(id -g deploy)"
    echo "   creado (LAN $LAN_SUBNET, IP $LAN_IP, PUID $(id -u bragi))"
else
    echo "   ya existe; se conservan los valores actuales"
fi

echo "== 5. Inventario del receptor ($APPS_YML)"
if ! grep -q 'repo: higerotech/bragi' "$APPS_YML"; then
    cp -a "$APPS_YML" "/root/apps.yml.bak-$(date +%Y%m%d-%H%M%S)"   # fuera de /etc/cd-receiver
    sed "s|http://192.0.2.1:8096|http://$LAN_IP:8096|" "$APP_DIR/deploy/cd/apps.bragi.yml" >> "$APPS_YML"
    curl -fsS -X POST http://127.0.0.1:9000/reload >/dev/null && echo "   anadido y receptor recargado"
else
    echo "   ya declarado"
fi

echo "== 6. Unidad de arranque (H4: vuelve tras un apagon aunque el NFS tarde)"
install -m 0755 "$APP_DIR/deploy/cd/bragi-arranque.sh" /usr/local/sbin/bragi-arranque.sh
install -m 0644 "$APP_DIR/deploy/cd/bragi-arranque.service" /etc/systemd/system/bragi-arranque.service
systemctl daemon-reload
systemctl enable bragi-arranque.service >/dev/null 2>&1 && echo "   bragi-arranque.service habilitada"

echo "== Listo. Siguiente: webhook en GitHub y ventana de corte (docs/05-deployment/deployment.md)."
