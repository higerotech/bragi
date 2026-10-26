#!/usr/bin/env bash
# Instala el recolector de metricas de Bragi en el appliance (Gate 5, ADR-0009). Idempotente.
#   sudo bash deploy/metricas/instalar.sh
#
# Con el Compose de Yggdrasil en el mismo host (midgard): activar despues el perfil `metricas` en
# deploy/.env (COMPOSE_PROFILES) para que el receptor levante bragi-metricas en la red heimdall.
# En un host sin ese Compose (nidavellir, ADR-0010) no hay red heimdall: el textfile va al
# directorio que ya sirve Thor por la LAN, solo a midgard, y el perfil `metricas` queda apagado:
#   sudo BRAGI_METRICAS_DIR=/var/lib/yggdrasil-thor bash deploy/metricas/instalar.sh
# En los dos casos, el job y las reglas de deploy/prometheus/ van al prometheus.yml de Yggdrasil.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALIDA=${BRAGI_METRICAS_DIR:-/var/lib/bragi-metricas}
ESTADO_DIR=${BRAGI_ESTADO_DIR:-/var/lib/bragi-respaldo}
RESPALDOS=${RESPALDO_DESTINO:-/mnt/nas/respaldos/bragi}

[ "$(id -u)" = 0 ] || { echo "ejecutar con sudo"; exit 1; }

echo "== 1. Directorios"
install -d -m 0755 "$SALIDA"
install -d -m 0755 "$ESTADO_DIR"

echo "== 2. Estado inicial del respaldo (si aun no lo ha escrito respaldar.sh)"
if [ ! -s "$ESTADO_DIR/ultimo-exito" ] && ls "$RESPALDOS" >/dev/null 2>&1; then
    ultimo=$(ls -1t "$RESPALDOS"/bragi-config-*.tar.gz 2>/dev/null | head -1)
    if [ -n "$ultimo" ] && (cd "$RESPALDOS" && sha256sum -c --quiet "$(basename "$ultimo").sha256"); then
        echo "$(stat -c %Y "$ultimo") $(stat -c %s "$ultimo")" > "$ESTADO_DIR/ultimo-exito"
        echo "   sembrado desde $(basename "$ultimo")"
    fi
fi

echo "== 3. Recolector y timer"
if [ "$SALIDA" != /var/lib/bragi-metricas ]; then
    echo "BRAGI_METRICAS_DIR=$SALIDA" > /etc/default/bragi-metricas
    echo "   textfile en $SALIDA (/etc/default/bragi-metricas)"
else
    rm -f /etc/default/bragi-metricas
fi
install -m 0755 "$DIR/recolectar.sh" /usr/local/sbin/bragi-recolectar.sh
install -m 0644 "$DIR/bragi-metricas.service" /etc/systemd/system/bragi-metricas.service
install -m 0644 "$DIR/bragi-metricas.timer" /etc/systemd/system/bragi-metricas.timer
systemctl daemon-reload
systemctl enable --now bragi-metricas.timer >/dev/null 2>&1
systemctl start bragi-metricas.service
echo "   $(grep -c '^bragi_' "$SALIDA/bragi.prom") series en $SALIDA/bragi.prom"
