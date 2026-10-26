#!/usr/bin/env bash
# Converge Bragi tras un arranque del appliance (RNF03, hallazgo H4).
#
# Dos motivos para no fiarse de `restart: unless-stopped`:
#   1. Docker no reaplica la politica a un contenedor que queda `exited` durante la restauracion
#      tras un apagado sucio (Yggdrasil, TA-13, 2026-09-08). midgard no tiene UPS.
#   2. Si el automount NFS de la biblioteca aun no responde, runc no puede hacer el bind de
#      /media y el contenedor no arranca. Por eso se espera al montaje antes de levantar nada.
#      Con la biblioteca repartida (ADR-0010: series en el NAS, peliculas en un disco local) se
#      espera a cada montaje de MEDIA_MONTAJES: sin el disco, Jellyfin veria las peliculas vacias.
#
# Solo levanta los servicios de larga duracion (Jellyfin y, si su perfil esta activo, el tunel):
# `sync` necesita GitHub y `config` ya dejo network.xml escrito en el ultimo despliegue.
set -euo pipefail

DIR=${BRAGI_DIR:-/srv/apps/bragi}
ESTADO=${BRAGI_ESTADO:-/var/lib/cd-receiver/bragi.json}
ESPERA_NFS=${ESPERA_NFS:-600}

leer_env() { sed -n "s/^$1=//p" "$DIR/deploy/.env" 2>/dev/null | tail -1 | tr -d '"'; }
MEDIA=${MEDIA_PATH:-$(leer_env MEDIA_PATH)}
MEDIA=${MEDIA:-/mnt/nas/media}
MONTAJES=${MEDIA_MONTAJES:-$(leer_env MEDIA_MONTAJES)}
MONTAJES=${MONTAJES:-$MEDIA}

TAG=$(jq -r '.current_tag // empty' "$ESTADO" 2>/dev/null || true)
[ -n "$TAG" ] || { echo "bragi-arranque: sin despliegue registrado en $ESTADO; nada que hacer"; exit 0; }

for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done

echo "bragi-arranque: esperando la biblioteca en $MONTAJES (hasta ${ESPERA_NFS} s)"
# `mountpoint` no sirve: el autofs ya es un punto de montaje aunque el NFS no haya montado.
# `ls` dispara el automount y findmnt confirma que hay algo montado que no es el propio autofs.
montado() { ls "$1" >/dev/null 2>&1 && findmnt -rn -o FSTYPE "$1" | grep -qvx autofs; }
t=0
for p in $MONTAJES; do
    until montado "$p"; do
        [ "$t" -ge "$ESPERA_NFS" ] && { echo "bragi-arranque: $p no monto; systemd reintentara"; exit 1; }
        sleep 10; t=$((t + 10))
    done
done
echo "bragi-arranque: biblioteca montada tras ${t} s"

cd "$DIR/deploy"
export IMAGE_TAG="$TAG"
mapfile -t servicios < <(docker compose -p bragi config --services | grep -vx -e sync -e config)
echo "bragi-arranque: IMAGE_TAG=$TAG, servicios: ${servicios[*]}"
docker compose -p bragi up -d --no-deps --no-build "${servicios[@]}"
docker compose -p bragi ps --format '{{.Name}} {{.State}}'
