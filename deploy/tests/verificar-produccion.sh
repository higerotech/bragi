#!/usr/bin/env bash
# verificar-produccion.sh — el operador verifica Bragi en produccion con SU cuenta de admin.
#
# Pide usuario y clave por la terminal (la clave sin eco), inicia sesion desde el propio
# appliance (IP LAN, asi que el admin puede entrar), y con esa sesion:
#   --aplicar  aplica politicas.sh (admin sin acceso remoto, preset, tareas de madrugada...)
#   siempre    ejecuta prueba-appliance.sh completo
# La clave no sale del proceso: no se escribe en disco, ni en el historial, ni en argumentos.
#
#   ssh -t <usuario>@<appliance> sudo bash /srv/apps/bragi/deploy/tests/verificar-produccion.sh --aplicar
set -uo pipefail

REPO=${BRAGI_REPO:-/srv/apps/bragi}          # de aqui solo se lee deploy/.env
ENV_FILE="$REPO/deploy/.env"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # scripts hermanos: los de esta copia
aplicar=0
[ "${1:-}" = "--aplicar" ] && aplicar=1

[ -t 0 ] || { echo "necesita una terminal: usa ssh -t"; exit 2; }
command -v jq >/dev/null || { echo "falta jq"; exit 2; }

leer_env() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -1; }
HOST_LAN_IP=$(leer_env HOST_LAN_IP)
LAN_SUBNET=$(leer_env LAN_SUBNET)
PUERTO=${BRAGI_PUERTO:-8096}
URL="http://$HOST_LAN_IP:$PUERTO"

read -rp "Usuario admin de Jellyfin: " ADMIN_USUARIO
read -rsp "Clave (no se muestra): " ADMIN_CLAVE
echo

cuerpo=$(jq -nc --arg u "$ADMIN_USUARIO" --arg p "$ADMIN_CLAVE" '{Username: $u, Pw: $p}')
# Por stdin (@-): como argumento, la clave se veria con ps mientras dura la peticion.
respuesta=$(printf '%s' "$cuerpo" | curl -s -w '\n%{http_code}' \
    -H 'Authorization: MediaBrowser Client="bragi-operador", Device="verificacion", DeviceId="bragi-operador", Version="1.0"' \
    -H 'Content-Type: application/json' --data-binary @- "$URL/Users/AuthenticateByName")
codigo=$(tail -n1 <<<"$respuesta")
token=$(head -n -1 <<<"$respuesta" | jq -r '.AccessToken // empty' 2>/dev/null)
unset cuerpo respuesta
if [ "$codigo" != 200 ] || [ -z "$token" ]; then
    echo "No pude iniciar sesion (HTTP $codigo). Revisa usuario y clave."
    exit 2
fi
echo "Sesion iniciada desde la LAN."

if [ "$aplicar" = 1 ]; then
    echo; echo "== politicas.sh --aplicar =="
    JELLYFIN_URL="$URL" JELLYFIN_TOKEN="$token" bash "$DIR/../scripts/politicas.sh" --aplicar
fi

echo; echo "== prueba-appliance.sh =="
BRAGI_CONTENEDOR=${BRAGI_CONTENEDOR:-bragi} BRAGI_PUERTO="$PUERTO" HOST_LAN_IP="$HOST_LAN_IP" \
    LAN_SUBNET="$LAN_SUBNET" ADMIN_USUARIO="$ADMIN_USUARIO" ADMIN_CLAVE="$ADMIN_CLAVE" \
    bash "$DIR/prueba-appliance.sh"
rc=$?
unset ADMIN_CLAVE token
exit "$rc"
