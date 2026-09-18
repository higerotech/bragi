#!/usr/bin/env bash
# Instala el recolector de metricas de Bragi en el appliance (Gate 5, ADR-0009). Idempotente.
#   sudo bash deploy/metricas/instalar.sh
#
# Despues hay que activar el perfil `metricas` en deploy/.env (COMPOSE_PROFILES) para que el
# receptor levante bragi-metricas, y desplegar en Yggdrasil el job y las reglas de
# deploy/prometheus/.
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
install -m 0755 "$DIR/recolectar.sh" /usr/local/sbin/bragi-recolectar.sh
install -m 0644 "$DIR/bragi-metricas.service" /etc/systemd/system/bragi-metricas.service
install -m 0644 "$DIR/bragi-metricas.timer" /etc/systemd/system/bragi-metricas.timer
systemctl daemon-reload
systemctl enable --now bragi-metricas.timer >/dev/null 2>&1
systemctl start bragi-metricas.service
echo "   $(grep -c '^bragi_' "$SALIDA/bragi.prom") series en $SALIDA/bragi.prom"
