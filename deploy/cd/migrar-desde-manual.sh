#!/usr/bin/env bash
# Ventana de corte: pasa la configuracion del Jellyfin manual (~/jellyfin) a Bragi.
# INTERRUMPE EL SERVICIO: para el contenedor manual. Ejecutar como root, con la autorizacion
# del owner y sin nadie viendo nada:
#   sudo ORIGEN=/home/<usuario>/jellyfin bash deploy/cd/migrar-desde-manual.sh
#
# No borra nada del origen: el directorio y el contenedor manual quedan intactos (solo parado y
# sin reinicio automatico) para poder volver atras. Rollback en docs/05-deployment/deployment.md.
set -euo pipefail

ORIGEN=${ORIGEN:?define ORIGEN con el directorio del despliegue manual (el que tiene config/)}
DESTINO=${BRAGI_DATA:-/var/lib/bragi}
MANUAL=${CONTENEDOR_MANUAL:-jellyfin}
PUERTO=${PUERTO:-8096}
forzar=0
[ "${1:-}" = "--forzar" ] && forzar=1

[ "$(id -u)" = 0 ] || { echo "ejecutar con sudo"; exit 1; }
id bragi >/dev/null 2>&1 || { echo "falta el usuario bragi: ejecutar antes bootstrap-midgard.sh"; exit 1; }
[ -d "$ORIGEN/config" ] || { echo "no existe $ORIGEN/config"; exit 1; }

echo "== 1. Comprobaciones"
if [ -e "$DESTINO/config/data" ] && [ "$forzar" = 0 ]; then
    echo "   $DESTINO/config ya tiene datos: no se sobrescribe sin --forzar"; exit 1
fi
clientes=$(ss -tn state established "( sport = :$PUERTO )" | tail -n +2 | wc -l)
if [ "$clientes" -gt 0 ] && [ "$forzar" = 0 ]; then
    echo "   hay $clientes cliente(s) conectados a :$PUERTO; esperar o usar --forzar"; exit 1
fi
echo "   origen $(du -sh "$ORIGEN/config" | cut -f1), clientes conectados: $clientes"

echo "== 2. Parar el Jellyfin manual ($MANUAL) y quitarle el reinicio automatico"
if docker inspect "$MANUAL" >/dev/null 2>&1; then
    docker update --restart=no "$MANUAL" >/dev/null
    docker stop -t 30 "$MANUAL" >/dev/null
    echo "   $(docker inspect -f '{{.Name}} {{.State.Status}}' "$MANUAL")"
else
    echo "   no existe; nada que parar"
fi

echo "== 3. Copia de config y cache (el origen queda intacto)"
rsync -a --delete "$ORIGEN/config/" "$DESTINO/config/"
rsync -a --delete "$ORIGEN/cache/" "$DESTINO/cache/"
chown -R bragi:bragi "$DESTINO"
chmod 0750 "$DESTINO" "$DESTINO/config" "$DESTINO/cache"
echo "   $(du -sh "$DESTINO/config" | cut -f1) copiados a $DESTINO, dueno $(stat -c %U "$DESTINO/config")"

echo "== Listo. Siguiente: primer despliegue por el receptor (deployment.md, paso 5)."
