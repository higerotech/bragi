#!/usr/bin/env bash
# Instala el respaldo nocturno de Bragi en el appliance. Idempotente. Como root:
#   sudo NAS=192.0.2.30 bash deploy/respaldo/instalar.sh
#
# Anade el montaje NFS del share `respaldos` (automount, como los demas shares del NAS), el
# script y el timer. El share debe estar exportado SOLO al appliance.
set -euo pipefail

NAS=${NAS:?define NAS con la IP del NAS}
EXPORT=${EXPORT:-/nfs/respaldos}
PUNTO=${PUNTO:-/mnt/nas/respaldos}
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "ejecutar con sudo"; exit 1; }

echo "== 1. Montaje NFS en $PUNTO"
if ! grep -q "[[:space:]]${PUNTO}[[:space:]]" /etc/fstab; then
    cp -a /etc/fstab "/etc/fstab.bak-$(date +%Y%m%d-%H%M%S)"
    printf '%s:%s  %s  nfs  rw,vers=3,hard,noatime,x-systemd.automount,x-systemd.idle-timeout=600,_netdev  0  0\n' \
        "$NAS" "$EXPORT" "$PUNTO" >> /etc/fstab
    mkdir -p "$PUNTO"
    systemctl daemon-reload
    # Solo el automount nuevo: reiniciar remote-fs.target podria tocar los montajes que Bragi y
    # Transmission estan usando.
    systemctl start "$(systemd-escape --path --suffix=automount "$PUNTO")"
    echo "   anadido a /etc/fstab"
else
    echo "   ya declarado"
fi
ls "$PUNTO" >/dev/null && findmnt -rn -t nfs,nfs4 "$PUNTO" >/dev/null && echo "   montado"

echo "== 2. Script y timer"
install -m 0755 "$DIR/respaldar.sh" /usr/local/sbin/bragi-respaldar.sh
install -m 0644 "$DIR/bragi-respaldo.service" /etc/systemd/system/bragi-respaldo.service
install -m 0644 "$DIR/bragi-respaldo.timer" /etc/systemd/system/bragi-respaldo.timer
systemctl daemon-reload
systemctl enable --now bragi-respaldo.timer >/dev/null 2>&1
systemctl list-timers bragi-respaldo.timer --no-pager | sed -n 2p

echo "== Listo. Primer respaldo a mano:  sudo systemctl start bragi-respaldo.service"
