#!/usr/bin/env bash
# prueba-appliance.sh — verifica un Bragi desplegado EN EL APPLIANCE (Gate 3 en staging,
# Gate 4 en produccion). Complementa a prueba-proxy.sh, que prueba en contenedores aislados:
# aqui la red, el NFS, los topes y el Docker son los reales.
#
#   BRAGI_CONTENEDOR=bragi BRAGI_PUERTO=8096 HOST_LAN_IP=... LAN_SUBNET=... \
#   ADMIN_USUARIO=... ADMIN_CLAVE=... ./prueba-appliance.sh
#
# La clave del admin se pasa por entorno y no se escribe en ningun sitio. Hay que ejecutarlo en
# el propio appliance: desde el host, las peticiones salen con la IP LAN (y deben ser "locales").
set -uo pipefail

C="${BRAGI_CONTENEDOR:-bragi}"
PUERTO="${BRAGI_PUERTO:-8096}"
LAN_IP="${HOST_LAN_IP:?define HOST_LAN_IP}"
LAN_SUBNET="${LAN_SUBNET:?define LAN_SUBNET}"
TUNEL_IP="${TUNEL_IP:-172.30.50.10}"
USUARIO="${ADMIN_USUARIO:?define ADMIN_USUARIO}"
CLAVE="${ADMIN_CLAVE:?define ADMIN_CLAVE}"
URL="http://$LAN_IP:$PUERTO"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CABECERA='MediaBrowser Client="bragi-appliance", Device="verificacion", DeviceId="bragi-appliance", Version="1.0"'

fallos=0
res() {   # res ID descripcion esperado obtenido
    if [ "$3" = "$4" ]; then printf '  ok     %-4s %-60s %s\n' "$1" "$2" "$4"
    else printf '  FALLA  %-4s %-60s esperado %s, obtenido %s\n' "$1" "$2" "$3" "$4"; fallos=$((fallos + 1)); fi
}
insp() { docker inspect -f "$1" "$C" 2>/dev/null; }
cuerpo_login() { printf '{"Username":"%s","Pw":"%s"}' "$USUARIO" "$CLAVE"; }

docker inspect "$C" >/dev/null 2>&1 || { echo "No existe el contenedor $C"; exit 2; }

echo "== Contenedor $C =="
res A1 "sano (healthcheck)" healthy "$(insp '{{.State.Health.Status}}')"
publicado="$(docker port "$C" 8096/tcp | sort -u | tr '\n' ' ' | sed 's/ $//')"
res A2 "RS01: 8096 publicado solo en la IP LAN" "$LAN_IP:$PUERTO" "$publicado"
usuario="$(insp '{{.Config.User}}')"
res A3 "RS08: usuario sin root" si "$([ -n "$usuario" ] && [ "${usuario%%:*}" != 0 ] && echo si || echo "no ($usuario)")"
res A4 "RS08: cap_drop ALL" "[ALL]" "$(insp '{{.HostConfig.CapDrop}}')"
res A5 "RS08: no-new-privileges" si "$(insp '{{.HostConfig.SecurityOpt}}' | grep -q no-new-privileges && echo si || echo no)"
res A6 "RS06: imagen pineada por digest" si "$(insp '{{.Config.Image}}' | grep -q '@sha256:' && echo si || echo no)"
res A7 "RNF01: tope de CPU (nanocpus)" 3000000000 "$(insp '{{.HostConfig.NanoCpus}}')"
res A8 "RNF01: tope de memoria (bytes)" 2147483648 "$(insp '{{.HostConfig.Memory}}')"
res A9 "cpu_shares" 512 "$(insp '{{.HostConfig.CpuShares}}')"

echo "== Biblioteca =="
res B1 "ADR-0005: /media con propagacion rslave" rslave \
    "$(insp '{{range .Mounts}}{{if eq .Destination "/media"}}{{.Propagation}}{{end}}{{end}}')"
res B2 "RS05: /media de solo lectura" ro \
    "$(docker exec "$C" sh -c 'touch /media/.bragi-escritura 2>/dev/null && { rm -f /media/.bragi-escritura; echo rw; } || echo ro')"
res B3 "/media tiene contenido" si "$(docker exec "$C" sh -c '[ -n "$(ls -A /media)" ] && echo si || echo no')"

echo "== network.xml (ADR-0006) =="
xml="$(docker exec "$C" cat /config/config/network.xml)"
res N1 "LocalNetworkSubnets = solo la LAN" "$LAN_SUBNET" \
    "$(sed -n '/<LocalNetworkSubnets>/,/<\/LocalNetworkSubnets>/p' <<<"$xml" | grep -o '<string>[^<]*' | sed 's/<string>//' | tr '\n' ' ' | sed 's/ $//')"
res N2 "KnownProxies = solo el tunel" "$TUNEL_IP" \
    "$(sed -n '/<KnownProxies>/,/<\/KnownProxies>/p' <<<"$xml" | grep -o '<string>[^<]*' | sed 's/<string>//' | tr '\n' ' ' | sed 's/ $//')"

echo "== Frontera de confianza en la red real =="
# El cuerpo con la clave va por stdin (@-), nunca como argumento: los argumentos se ven con ps.
login_json="$(mktemp)"
codigo_host="$(cuerpo_login | curl -s -o "$login_json" -w '%{http_code}' -H "Authorization: $CABECERA" \
    -H 'Content-Type: application/json' --data-binary @- "$URL/Users/AuthenticateByName")"
res F1 "admin desde el host (IP LAN) -> local" 200 "$codigo_host"
token="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("AccessToken",""))' "$login_json" 2>/dev/null)"
rm -f "$login_json"

# Un contenedor en docker0 llega al puerto publicado con una IP 172.17.x.x: Jellyfin debe
# tratarlo como REMOTO. Si la red Docker contara como LAN, esto entraria (RS04).
# Se usa la propia imagen de Bragi (ya presente, trae curl) para no depender de otra descarga.
codigo_ajeno="$(cuerpo_login | docker run --rm -i --network bridge --entrypoint curl "$(insp '{{.Config.Image}}')" \
    -s -o /dev/null -w '%{http_code}' -H "Authorization: $CABECERA" \
    -H 'Content-Type: application/json' --data-binary @- "$URL/Users/AuthenticateByName")"
res F2 "admin desde un contenedor en docker0 -> remoto, rechazado" 403 "$codigo_ajeno"

echo "== Politicas (politicas.sh --verificar) =="
if [ -n "$token" ]; then
    JELLYFIN_URL="$URL" JELLYFIN_TOKEN="$token" bash "$DIR/../scripts/politicas.sh" | sed 's/^/  /'
    res P1 "politicas sin deriva (codigo de salida)" 0 "${PIPESTATUS[0]}"
else
    res P1 "politicas sin deriva" 0 "sin token"
fi

echo
[ "$fallos" -eq 0 ] && echo "== $C cumple ==" || echo "== $fallos comprobacion(es) fallan en $C =="
exit "$fallos"
