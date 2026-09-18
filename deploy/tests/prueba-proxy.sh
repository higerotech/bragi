#!/usr/bin/env bash
# prueba-proxy.sh — prueba de integracion de la frontera de confianza de Bragi.
#
# Levanta un Jellyfin real (misma imagen que produccion) con el network.xml que genera
# config.sh, completa el asistente, crea una cuenta familiar, aplica politicas.sh y comprueba:
#
#   P1  admin desde la LAN                                   -> entra
#   P2  admin desde otro contenedor, sin cabeceras           -> rechazado (red Docker != LAN)
#   P3  admin desde otro contenedor con XFF de la LAN        -> rechazado (XFF de no-proxy)
#   P4  admin por el proxy con IP publica                    -> rechazado (RS02)
#   P5  admin por el proxy con "IP LAN, IP publica"          -> rechazado (AB03 via Cloudflare,
#                                                               que ANADE la IP real al XFF)
#   P6  admin por el proxy con XFF de la LAN                 -> entra: prueba que el XFF del proxy
#                                                               se usa; sin P6, P4 y P5 pasarian
#                                                               aunque KnownProxies no funcionara
#   P7  familia por el proxy con IP publica                  -> entra (acceso remoto permitido)
#   P8  politicas.sh --verificar tras aplicar               -> sin deriva
#   P9  familia: 5 fallos y luego la clave buena             -> deberia rechazarse (RS03); hoy
#                                                               entra: fallo conocido de 10.11.11
#
#   ./deploy/tests/prueba-proxy.sh          (necesita Docker; tarda ~2 min la primera vez)
set -uo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash: no traducir las rutas del contenedor

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
PRUEBA_DIR="$(mktemp -d)"
export PRUEBA_DIR
mkdir -p "$PRUEBA_DIR/config" "$PRUEBA_DIR/cache"
chmod 0777 "$PRUEBA_DIR/config" "$PRUEBA_DIR/cache"   # el contenedor corre como 1000
# Git Bash: Docker Desktop no entiende /tmp/...; necesita la ruta de Windows (C:/...).
command -v cygpath >/dev/null && PRUEBA_DIR="$(cygpath -m "$PRUEBA_DIR")"

dc() { docker compose -f docker-compose.prueba.yml "$@"; }
limpiar() {
    dc down -v --remove-orphans >/dev/null 2>&1
    # Los ficheros son del uid 1000 del contenedor: se borran desde uno.
    docker run --rm -v "$PRUEBA_DIR:/d" alpine:3.22 rm -rf /d/config /d/cache >/dev/null 2>&1
    rm -rf "$PRUEBA_DIR"
}
[ "${PRUEBA_MANTENER:-0}" = 1 ] || trap limpiar EXIT   # PRUEBA_MANTENER=1 deja el banco vivo

J=http://jellyfin:8096
PUBLICA=203.0.113.9        # RFC 5737: "internet"
IP_LAN=172.31.251.50       # dentro de LocalNetworkSubnets de la prueba
CLAVE_ADMIN='prueba-Admin-2026!'
CLAVE_FAMILIA='prueba-Familia-2026!'
# DeviceId distinto para la sesion de gestion y para los logins de prueba: Jellyfin cierra la
# sesion anterior de un mismo dispositivo al autenticar, e invalidaria el token de gestion.
CABECERA='MediaBrowser Client="bragi-prueba", Device="ci", DeviceId="bragi-prueba-gestion", Version="1.0"'
CABECERA_LOGIN='MediaBrowser Client="bragi-prueba", Device="ci", DeviceId="bragi-prueba-login", Version="1.0"'

fallos=0
resultado() {   # resultado ID descripcion esperado obtenido
    if [ "$3" = "$4" ]; then
        printf '  ok     %-3s %-58s %s\n' "$1" "$2" "$4"
    else
        printf '  FALLA  %-3s %-58s esperado %s, obtenido %s\n' "$1" "$2" "$3" "$4"
        fallos=$((fallos + 1))
    fi
}

# http CLIENTE METODO RUTA [XFF] [TOKEN] [CUERPO]  -> imprime el cuerpo; el codigo va a $CODIGO_F
CODIGO_F="$PRUEBA_DIR/codigo"
http() {
    local cliente=$1 metodo=$2 ruta=$3 xff=${4:-} token=${5:-} cuerpo=${6:-}
    local auth="${CABECERA_HTTP:-$CABECERA}"
    [ -n "$token" ] && auth="$CABECERA, Token=\"$token\""
    local args=(curl -s -o /tmp/r -w '%{http_code}' -X "$metodo" -H "Authorization: $auth")
    [ -n "$xff" ] && args+=(-H "X-Forwarded-For: $xff")
    [ -n "$cuerpo" ] && args+=(-H 'Content-Type: application/json' --data-binary @-)
    args+=("$J$ruta")
    printf '%s' "$cuerpo" | dc exec -T "$cliente" "${args[@]}" > "$CODIGO_F"
    dc exec -T "$cliente" cat /tmp/r
}
codigo() { cat "$CODIGO_F"; }
jqc() { dc exec -T lan jq "$@"; }   # jq del contenedor: el host (p. ej. Git Bash) puede no tenerlo

login() {   # login CLIENTE USUARIO CLAVE [XFF] -> codigo HTTP
    CABECERA_HTTP="$CABECERA_LOGIN" http "$1" POST /Users/AuthenticateByName "${4:-}" "" \
        "$(printf '{"Username":"%s","Pw":"%s"}' "$2" "$3")" >/dev/null
    codigo
}

echo "== Levantando el banco de pruebas =="
if ! dc up -d --build --quiet-pull >"$PRUEBA_DIR/up.log" 2>&1; then
    tail -5 "$PRUEBA_DIR/up.log"
    dc logs config
    exit 1
fi
for _ in $(seq 1 90); do
    estado="$(docker inspect -f '{{.State.Health.Status}}' "$(dc ps -q jellyfin)" 2>/dev/null)"
    listos=0
    for c in proxy intruso lan; do dc exec -T "$c" test -f /listo 2>/dev/null && listos=$((listos + 1)); done
    [ "$estado" = healthy ] && [ "$listos" = 3 ] && break
    sleep 3
done
[ "$estado" = healthy ] || { echo "Jellyfin no quedo sano"; dc logs --tail 40 jellyfin; exit 1; }
# /health da 200 antes de que Jellyfin termine de arrancar; hasta entonces el resto de la API
# responde 503. Se espera a que la API publica conteste de verdad.
for _ in $(seq 1 60); do
    http lan GET /System/Info/Public >/dev/null
    [ "$(codigo)" = 200 ] && break
    sleep 2
done
echo "  Jellyfin sano; network.xml generado:"
grep -E '<string>' "$PRUEBA_DIR/config/config/network.xml" | sed 's/^ */    /'

echo "== Asistente inicial y cuentas =="
http lan POST /Startup/Configuration "" "" \
    '{"UICulture":"es","MetadataCountryCode":"US","PreferredMetadataLanguage":"es"}' >/dev/null
http lan GET /Startup/User >/dev/null
http lan POST /Startup/User "" "" "$(printf '{"Name":"admin","Password":"%s"}' "$CLAVE_ADMIN")" >/dev/null
http lan POST /Startup/Complete >/dev/null
resultado "--" "asistente completado" 204 "$(codigo)"

token="$(http lan POST /Users/AuthenticateByName "" "" \
    "$(printf '{"Username":"admin","Pw":"%s"}' "$CLAVE_ADMIN")" | jqc -r .AccessToken)"
[ -n "$token" ] && [ "$token" != null ] || { echo "No obtuve token de admin"; exit 1; }
http lan POST /Users/New "" "$token" "$(printf '{"Name":"familia","Password":"%s"}' "$CLAVE_FAMILIA")" >/dev/null
resultado "--" "cuenta familia creada" 200 "$(codigo)"

echo "== politicas.sh =="
dc exec -T -e JELLYFIN_URL="$J" -e JELLYFIN_TOKEN="$token" lan bash /scripts/politicas.sh --aplicar | sed 's/^/  /'

echo "== Frontera de confianza =="
resultado P1 "admin desde la LAN" 200 "$(login lan admin "$CLAVE_ADMIN")"
resultado P2 "admin desde contenedor ajeno, sin XFF" 403 "$(login intruso admin "$CLAVE_ADMIN")"
resultado P3 "admin desde contenedor ajeno, XFF=$IP_LAN" 403 "$(login intruso admin "$CLAVE_ADMIN" "$IP_LAN")"
resultado P4 "admin por el proxy, XFF=$PUBLICA" 403 "$(login proxy admin "$CLAVE_ADMIN" "$PUBLICA")"
resultado P5 "admin por el proxy, XFF=$IP_LAN, $PUBLICA" 403 "$(login proxy admin "$CLAVE_ADMIN" "$IP_LAN, $PUBLICA")"
resultado P6 "admin por el proxy, XFF=$IP_LAN (control)" 200 "$(login proxy admin "$CLAVE_ADMIN" "$IP_LAN")"
resultado P7 "familia por el proxy, XFF=$PUBLICA" 200 "$(login proxy familia "$CLAVE_FAMILIA" "$PUBLICA")"

dc exec -T -e JELLYFIN_URL="$J" -e JELLYFIN_TOKEN="$token" lan bash /scripts/politicas.sh >/dev/null
resultado P8 "politicas.sh --verificar tras aplicar (codigo de salida)" 0 "$?"

# P9 es un FALLO CONOCIDO de Jellyfin 10.11.11 (jellyfin/jellyfin#17278, arreglado en 12.0 por
# el PR #17274): registra "Disabling user ... due to N unsuccessful login attempts" pero no
# persiste IsDisabled y la clave buena sigue entrando. No rompe el CI mientras sigamos en 10.11;
# si un dia pasa, avisa para convertirla en obligatoria. El control efectivo de T1 mientras tanto
# es el limite de tasa de Cloudflare (ADR-0004). Ver hallazgo H1 en el threat model.
#
# Se usa un DeviceId nuevo para no chocar con MaxActiveSessions: ese limite cuenta sesiones
# abiertas, y un 403 por sesiones se confundiria con un bloqueo que funciona.
for _ in 1 2 3 4 5; do login proxy familia 'clave-mala' "$PUBLICA" >/dev/null; done
CABECERA_LOGIN="${CABECERA_LOGIN/bragi-prueba-login/bragi-prueba-p9}"
p9="$(login proxy familia "$CLAVE_FAMILIA" "$PUBLICA")"
if [ "$p9" = 200 ]; then
    printf '  CONOCIDO P9  %-56s %s  (jellyfin#17278)\n' "familia tras 5 fallos, con la clave buena" "$p9"
else
    printf '  AVISO  P9  %-58s %s\n' "el bloqueo ya funciona: haz P9 obligatoria" "$p9"
fi

echo
if [ "$fallos" -eq 0 ]; then
    echo "== Todas las pruebas pasan =="
else
    echo "== $fallos prueba(s) fallan =="
    dc logs --tail 30 jellyfin
fi
exit "$fallos"
