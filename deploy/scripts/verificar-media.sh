#!/usr/bin/env bash
# verificar-media.sh — comprueba que la biblioteca del NAS esta lista ANTES de (re)crear Bragi.
#
# Por que existe: /mnt/nas/media es un autofs. Si el NFS no monta, runc revienta el bind y el
# contenedor NO ARRANCA ("error mounting /mnt/nas/media to rootfs at /media: no such device").
# Paso 0 del runbook y primera comprobacion ante un Bragi que no levanta. Solo lee.
#
#   NAS=192.0.2.30 ./verificar-media.sh
set -uo pipefail

NAS="${NAS:?define NAS con la IP del NAS}"
PUNTO="${MEDIA_PATH:-/mnt/nas/media}"
UNIDAD="$(systemd-escape --path "$PUNTO").mount"
rc=0

echo "== 1. El NAS exporta el share de media? =="
if showmount -e "$NAS" 2>/dev/null | grep -qi 'media'; then
    showmount -e "$NAS" 2>/dev/null | grep -i media | sed 's/^/  /'
    # Un export a '*' deja montar la biblioteca a cualquier equipo de la LAN (T7).
    showmount -e "$NAS" 2>/dev/null | grep -i media | grep -q '\*' \
        && echo "  AVISO: exportado a '*'; restringe a la IP del appliance (T7)."
else
    echo "  FALLA: el NAS no exporta media"; rc=1
fi

echo; echo "== 2. Monta? =="
ls "$PUNTO" >/dev/null 2>&1          # dispara el automount
if mountpoint -q "$PUNTO"; then
    echo "  montado ($UNIDAD): $(find "$PUNTO" -maxdepth 1 -mindepth 1 | wc -l) entradas"
else
    echo "  FALLA: $PUNTO no esta montado"; rc=1
    systemctl status "$UNIDAD" --no-pager -n 5 2>&1 | grep -E 'Active|mount.nfs' | sed 's/^/    /'
fi

echo; echo "== 3. Hay video? =="
n=$(find "$PUNTO" -maxdepth 3 -type f \( -name '*.mkv' -o -name '*.mp4' -o -name '*.avi' \) 2>/dev/null | wc -l)
echo "  ficheros de video (hasta 3 niveles): $n"
[ "$n" -eq 0 ] && echo "  AVISO: vacio; Jellyfin no encontrara nada."

echo; [ "$rc" -eq 0 ] && echo "== Listo ==" || echo "== NO recrear Bragi hasta resolver lo de arriba =="
exit "$rc"
