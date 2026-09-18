#!/usr/bin/env bash
# politicas.sh — verifica (o aplica) las politicas de cuentas de Bragi por la API de Jellyfin.
#
# Las politicas viven en la base SQLite, no en ficheros, asi que el repo no puede imponerlas
# por despliegue como el network.xml. Este script es la forma de que sean codigo: se revisa en
# PR, se ejecuta tras dar de alta una cuenta y su modo --verificar detecta la deriva.
#
#   Administradores  EnableRemoteAccess=false (RS02), LoginAttemptsBeforeLockout=5 (RS03)
#   Resto            EnableRemoteAccess=true, LoginAttemptsBeforeLockout=5, MaxActiveSessions=2
#                    (0 = sin limite, RNF04 revisado), RemoteClientBitrateLimit=0: sin limite,
#                    para no forzar transcodes
#                    (AB04)
#   Todas            con contrasena (RS09; la longitud no es visible por la API)
#   Servidor         RemoteClientBitrateLimit=0 (AB04)
#   Transcodificacion EncoderPreset=superfast: con el tope de 3 CPU, veryfast da 0,92x en un
#                    HEVC 10 bit y superfast 1,13x (RF03, Gate 3)
#   Tareas pesadas   escaneo, personas, capitulos y miniaturas solo entre la 01:00 y las 06:00
#                    (hora del contenedor): con un escaneo en marcha un transcode no llega a 1x
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
# MaxActiveSessions cuenta SESIONES ABIERTAS (dispositivos con la sesion iniciada), no
# reproducciones simultaneas: con 2, una persona con TV, movil y tablet no entraria en el tercero.
# Por eso RNF04 se reviso a sin limite (H2, HITL 2026-09-17). 0 = sin limite.
SESIONES="${BRAGI_SESIONES_MAX:-0}"

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

PRESET=superfast
enc="$(api GET /System/Configuration/encoding)" || { echo "No pude leer la configuracion de codificacion"; exit 2; }
preset="$(jq -r '.EncoderPreset // "auto"' <<<"$enc")"
if [ "$preset" = "$PRESET" ]; then
    echo "  ok      transcodificacion: EncoderPreset=$preset"
elif [ "$aplicar" = 1 ]; then
    if api POST /System/Configuration/encoding "$(jq -c --arg p "$PRESET" '.EncoderPreset = $p' <<<"$enc")" >/dev/null; then
        echo "  aplico  transcodificacion: EncoderPreset $preset -> $PRESET"
    else
        echo "  FALLO   transcodificacion: no pude poner EncoderPreset=$PRESET"; deriva=1
    fi
else
    echo "  DERIVA  transcodificacion: EncoderPreset=$preset (con el tope de CPU, solo $PRESET llega a 1x)"
    deriva=1
fi

# Tareas pesadas: cada disparador debe ser diario o semanal y caer en la ventana de madrugada.
# Un IntervalTrigger (el escaneo viene "cada 12 h" de fabrica) cae a cualquier hora.
HORA=36000000000   # ticks de .NET en una hora (100 ns)
declare -A VENTANA=(
    [RefreshLibrary]='[{"Type":"DailyTrigger","TimeOfDayTicks":144000000000}]'
    [RefreshPeople]='[{"Type":"WeeklyTrigger","DayOfWeek":"Sunday","TimeOfDayTicks":180000000000}]'
    [RefreshChapterImages]='[{"Type":"DailyTrigger","TimeOfDayTicks":72000000000,"MaxRuntimeTicks":144000000000}]'
    [RefreshTrickplayImages]='[{"Type":"DailyTrigger","TimeOfDayTicks":108000000000}]'
)
tareas="$(api GET /ScheduledTasks)" || { echo "No pude leer las tareas programadas"; exit 2; }
for clave in RefreshLibrary RefreshPeople RefreshChapterImages RefreshTrickplayImages; do
    tarea="$(jq -c --arg k "$clave" '.[] | select(.Key == $k)' <<<"$tareas")"
    [ -z "$tarea" ] && { echo "  aviso   tarea $clave no existe en esta version"; continue; }
    fuera="$(jq -r --argjson h "$HORA" '
        [.Triggers[] | select(
            (.Type != "DailyTrigger" and .Type != "WeeklyTrigger")
            or .TimeOfDayTicks < 1 * $h or .TimeOfDayTicks >= 6 * $h)] | length' <<<"$tarea")"
    if [ "$fuera" = 0 ]; then
        echo "  ok      tarea $clave: de madrugada"
    elif [ "$aplicar" = 1 ]; then
        if api POST "/ScheduledTasks/$(jq -r .Id <<<"$tarea")/Triggers" "${VENTANA[$clave]}" >/dev/null; then
            echo "  aplico  tarea $clave: $(jq -c '[.Triggers[].Type]' <<<"$tarea") -> ventana de madrugada"
        else
            echo "  FALLO   tarea $clave: no pude reprogramarla"; deriva=1
        fi
    else
        echo "  DERIVA  tarea $clave: $fuera disparador(es) fuera de la ventana 01:00-06:00"
        deriva=1
    fi
done

exit "$deriva"
