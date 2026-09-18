#!/usr/bin/env bash
# politicas.sh — verifica (o aplica) las politicas de cuentas de Bragi por la API de Jellyfin.
#
# Las politicas viven en la base SQLite, no en ficheros, asi que el repo no puede imponerlas
# por despliegue como el network.xml. Este script es la forma de que sean codigo: se revisa en
# PR, se ejecuta tras dar de alta una cuenta y su modo --verificar detecta la deriva.
#
#   Administradores  EnableRemoteAccess=false (RS02), LoginAttemptsBeforeLockout=5 (RS03)
#   Resto            EnableRemoteAccess=true, LoginAttemptsBeforeLockout=5, MaxActiveSessions=2
#                    (RNF04), RemoteClientBitrateLimit=0: sin limite, para no forzar transcodes
#                    (AB04)
#   Todas            con contrasena (RS09; la longitud no es visible por la API)
#   Servidor         RemoteClientBitrateLimit=0 (AB04)
#
# Uso (desde la LAN: con el admin sin acceso remoto, desde fuera no funcionaria):
#   JELLYFIN_URL=http://192.0.2.1:8096 JELLYFIN_TOKEN=<api key> ./politicas.sh            verifica
#   JELLYFIN_URL=... JELLYFIN_TOKEN=... ./politicas.sh --aplicar                          corrige
#
# La API key se crea en Panel > Claves de API. Sale 0 si todo cumple, 1 si hay deriva (o si
# --aplicar no consigue corregirla), 2 si no puede hablar con Jellyfin.
set -uo pipefail

URL="${JELLYFIN_URL:?define JELLYFIN_URL}"
TOKEN="${JELLYFIN_TOKEN:?define JELLYFIN_TOKEN con una API key de Jellyfin}"
INTENTOS=5
# OJO: MaxActiveSessions cuenta SESIONES ABIERTAS (dispositivos con la sesion iniciada), no
# reproducciones simultaneas. Con 2, una persona con TV, movil y tablet no puede entrar en el
# tercero. Pendiente de revisar RNF04 (ver hallazgo H2 en el threat model). 0 = sin limite.
SESIONES="${BRAGI_SESIONES_MAX:-2}"

aplicar=0
[ "${1:-}" = "--aplicar" ] && aplicar=1

command -v jq >/dev/null || { echo "falta jq"; exit 2; }

api() {   # api METODO RUTA [cuerpo-json]
    local args=(-fsS -X "$1" -H "Authorization: MediaBrowser Token=\"$TOKEN\"")
    [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data-binary "$3")
    curl "${args[@]}" "$URL$2"
}

usuarios="$(api GET /Users)" || { echo "No pude leer /Users en $URL (token o URL)"; exit 2; }

# Politica objetivo como filtro jq sobre la politica actual: se parte de la que devuelve la API
# porque POST /Users/{id}/Policy exige el objeto completo (proveedores de autenticacion
# incluidos) y rellenar a mano los campos que no gestionamos los machacaria.
objetivo='
  if .IsAdministrator then
    .EnableRemoteAccess = false | .LoginAttemptsBeforeLockout = $intentos
  else
    .EnableRemoteAccess = true | .LoginAttemptsBeforeLockout = $intentos
    | .MaxActiveSessions = $sesiones | .RemoteClientBitrateLimit = 0
  end'

deriva=0
while IFS= read -r u; do
    id="$(jq -r .Id <<<"$u")"
    nombre="$(jq -r .Name <<<"$u")"
    rol="$(jq -r 'if .Policy.IsAdministrator then "admin" else "familia" end' <<<"$u")"
    actual="$(jq -S .Policy <<<"$u")"
    deseada="$(jq -S --argjson intentos "$INTENTOS" --argjson sesiones "$SESIONES" "$objetivo" <<<"$actual")"

    if [ "$(jq -r .HasPassword <<<"$u")" != true ]; then
        echo "  DERIVA  $nombre ($rol): cuenta SIN contrasena. Ponsela desde el panel."
        deriva=1
    fi

    if [ "$actual" = "$deseada" ]; then
        echo "  ok      $nombre ($rol)"
        continue
    fi
    cambios="$(jq -rn --argjson a "$actual" --argjson d "$deseada" \
        '[$d | to_entries[] | select($a[.key] != .value) | "\(.key): \($a[.key]) -> \(.value)"] | join(", ")')"
    if [ "$aplicar" = 1 ]; then
        if api POST "/Users/$id/Policy" "$deseada" >/dev/null; then
            echo "  aplico  $nombre ($rol): $cambios"
        else
            echo "  FALLO   $nombre ($rol): no pude aplicar $cambios"
            deriva=1
        fi
    else
        echo "  DERIVA  $nombre ($rol): $cambios"
        deriva=1
    fi
done < <(jq -c '.[]' <<<"$usuarios")

conf="$(api GET /System/Configuration)" || { echo "No pude leer /System/Configuration"; exit 2; }
limite="$(jq -r '.RemoteClientBitrateLimit // "ausente"' <<<"$conf")"
if [ "$limite" = 0 ] || [ "$limite" = ausente ]; then
    echo "  ok      servidor: RemoteClientBitrateLimit=$limite"
elif [ "$aplicar" = 1 ]; then
    if api POST /System/Configuration "$(jq -c '.RemoteClientBitrateLimit = 0' <<<"$conf")" >/dev/null; then
        echo "  aplico  servidor: RemoteClientBitrateLimit $limite -> 0"
    else
        echo "  FALLO   servidor: no pude poner RemoteClientBitrateLimit=0"; deriva=1
    fi
else
    echo "  DERIVA  servidor: RemoteClientBitrateLimit=$limite (fuerza transcodes remotos)"
    deriva=1
fi

exit "$deriva"
