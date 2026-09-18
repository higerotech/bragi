#!/usr/bin/env bash
# Converge Bragi tras un arranque del appliance (RNF03, hallazgo H4).
#
# Dos motivos para no fiarse de `restart: unless-stopped`:
#   1. Docker no reaplica la politica a un contenedor que queda `exited` durante la restauracion
#      tras un apagado sucio (Yggdrasil, TA-13, 2026-09-08). midgard no tiene UPS.
#   2. Si el automount NFS de la biblioteca aun no responde, runc no puede hacer el bind de
#      /media y el contenedor no arranca. Por eso se espera al montaje antes de levantar nada.
#
# Solo levanta los servicios de larga duracion (Jellyfin y, si su perfil esta activo, el tunel):
# `sync` necesita GitHub y `config` ya dejo network.xml escrito en el ultimo despliegue.
set -euo pipefail

DIR=${BRAGI_DIR:-/srv/apps/bragi}
ESTADO=${BRAGI_ESTADO:-/var/lib/cd-receiver/bragi.json}
MEDIA=${MEDIA_PATH:-/mnt/nas/media}
ESPERA_NFS=${ESPERA_NFS:-600}

TAG=$(jq -r '.current_tag // empty' "$ESTADO" 2>/dev/null || true)
[ -n "$TAG" ] || { echo "bragi-arranque: sin despliegue registrado en $ESTADO; nada que hacer"; exit 0; }

for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done

echo "bragi-arranque: esperando la biblioteca en $MEDIA (hasta ${ESPERA_NFS} s)"
t=0
# `mountpoint` no sirve: el autofs ya es un punto de montaje aunque el NFS no haya montado.
# `ls` dispara el automount y findmnt confirma que lo que hay debajo es NFS.
until ls "$MEDIA" >/dev/null 2>&1 && findmnt -rn -t nfs,nfs4 "$MEDIA" >/dev/null; do
    [ "$t" -ge "$ESPERA_NFS" ] && { echo "bragi-arranque: $MEDIA no monto; systemd reintentara"; exit 1; }
    sleep 10; t=$((t + 10))
done
echo "bragi-arranque: biblioteca montada tras ${t} s"

cd "$DIR/deploy"
export IMAGE_TAG="$TAG"
mapfile -t servicios < <(docker compose -p bragi config --services | grep -vx -e sync -e config)
echo "bragi-arranque: IMAGE_TAG=$TAG, servicios: ${servicios[*]}"
docker compose -p bragi up -d --no-deps --no-build "${servicios[@]}"
docker compose -p bragi ps --format '{{.Name}} {{.State}}'
