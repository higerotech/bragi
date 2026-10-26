#!/usr/bin/env bash
# Prepara un host para desplegar Bragi con el receptor de despliegue-continuo (ADR-0003).
# Idempotente y sin secretos. Ejecutar como root. En nidavellir (ADR-0010: series en el NAS,
# peliculas en el disco WD):
#   sudo BRANCH=main TZ_HOGAR=America/Caracas LAN_IF=enp3s0 NAS=<ip del NAS> \
#        PELICULAS_ORIGEN=/srv/medios/wd/peliculas bash deploy/cd/bootstrap.sh
# Con la biblioteca entera en el NAS (el caso de midgard hasta la ADR-0010), sin PELICULAS_ORIGEN
# y con BIBLIOTECA=/mnt/nas/media.
#
# NO migra datos ni para nada: la mudanza va en la ventana de corte (docs/05-deployment/deployment.md).
set -euo pipefail

APP_DIR=${APP_DIR:-/srv/apps/bragi}
REPO=${REPO:-https://github.com/higerotech/bragi.git}
BRANCH=${BRANCH:-main}
LAN_IF=${LAN_IF:-lan}
DATOS=${BRAGI_DATA:-/var/lib/bragi}
APPS_YML=/etc/cd-receiver/apps.yml
BIBLIOTECA=${BIBLIOTECA:-/srv/medios/bragi}   # el contenedor la ve como /media
PELICULAS_ORIGEN=${PELICULAS_ORIGEN:-}         # vacio: la biblioteca entera viene del NAS
NAS=${NAS:-}

[ "$(id -u)" = 0 ] || { echo "ejecutar con sudo"; exit 1; }
[ -z "$PELICULAS_ORIGEN" ] || [ -n "$NAS" ] || { echo "con PELICULAS_ORIGEN hace falta NAS (las series)"; exit 1; }
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
    fijar MEDIA_PATH "$BIBLIOTECA"
    if [ -n "$PELICULAS_ORIGEN" ]; then
        fijar MEDIA_MONTAJES "\"$BIBLIOTECA/TV $BIBLIOTECA/movies\""
    else
        sed -i '/^MEDIA_MONTAJES=/d' "$ENV_FILE"
    fi
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
    sed "s|http://192.0.2.2:8096|http://$LAN_IP:8096|" "$APP_DIR/deploy/cd/apps.bragi.yml" >> "$APPS_YML"
    curl -fsS -X POST http://127.0.0.1:9000/reload >/dev/null && echo "   anadido y receptor recargado"
else
    echo "   ya declarado"
fi

echo "== 6. Unidad de arranque (H4: vuelve tras un apagon aunque el NFS tarde)"
install -m 0755 "$APP_DIR/deploy/cd/bragi-arranque.sh" /usr/local/sbin/bragi-arranque.sh
install -m 0644 "$APP_DIR/deploy/cd/bragi-arranque.service" /etc/systemd/system/bragi-arranque.service
systemctl daemon-reload
systemctl enable bragi-arranque.service >/dev/null 2>&1 && echo "   bragi-arranque.service habilitada"

echo "== 7. Biblioteca repartida en $BIBLIOTECA (ADR-0010)"
if [ -n "$PELICULAS_ORIGEN" ]; then
    [ -d "$PELICULAS_ORIGEN" ] || { echo "   no existe $PELICULAS_ORIGEN"; exit 1; }
    install -d -m 0755 "$BIBLIOTECA" "$BIBLIOTECA/TV" "$BIBLIOTECA/movies"
    nuevas=()
    # Series: un automount propio del subdirectorio del export, como el resto de shares del NAS.
    # Asi el autofs queda en $BIBLIOTECA/TV y el rslave de compose lo propaga igual que en midgard.
    grep -q "[[:space:]]$BIBLIOTECA/TV[[:space:]]" /etc/fstab || nuevas+=(
        "$NAS:/nfs/media/TV  $BIBLIOTECA/TV  nfs  ro,vers=3,hard,noatime,rsize=1048576,x-systemd.automount,x-systemd.idle-timeout=600,_netdev  0  0")
    # Peliculas: bind de solo lectura del disco local. nofail: si el disco no monta, el bind falla,
    # el directorio queda vacio y bragi-arranque no levanta Jellyfin (no veria las peliculas borradas).
    grep -q "[[:space:]]$BIBLIOTECA/movies[[:space:]]" /etc/fstab || nuevas+=(
        "$PELICULAS_ORIGEN  $BIBLIOTECA/movies  none  bind,ro,nofail,x-systemd.requires-mounts-for=$PELICULAS_ORIGEN  0  0")
    if [ "${#nuevas[@]}" -gt 0 ]; then
        cp -a /etc/fstab "/etc/fstab.bak-$(date +%Y%m%d-%H%M%S)"
        printf '%s\n' "${nuevas[@]}" >> /etc/fstab
        systemctl daemon-reload
        echo "   ${#nuevas[@]} entrada(s) en /etc/fstab"
    fi
    systemctl start "$(systemd-escape --path --suffix=automount "$BIBLIOTECA/TV")" \
        "$(systemd-escape --path --suffix=mount "$BIBLIOTECA/movies")"
    echo "   TV: $(ls "$BIBLIOTECA/TV" | wc -l) entradas; movies: $(ls "$BIBLIOTECA/movies" | wc -l) entradas"
else
    echo "   biblioteca entera en el NAS ($BIBLIOTECA)"
fi

echo "== Listo. Siguiente: ventana de corte (docs/05-deployment/deployment.md)."
