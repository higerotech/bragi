#!/usr/bin/env bash
# probar-limites.sh — mide si el tope de CPU del contenedor deja transcodificar en tiempo real.
#
# El transcode corre DENTRO del contenedor con `docker exec`, asi que queda sujeto al mismo
# cgroup que usaria Jellyfin de verdad. Eso es lo que hace la medida valida: no mide la
# maquina, mide el contenedor con sus topes puestos.
#
# Criterio: speed >= 1.0x es tiempo real. Por debajo, la reproduccion se entrecorta.
#
#   ./probar-limites.sh              60 s de video
#   ./probar-limites.sh 30           30 s (mas rapido, algo menos fiable)
#
# Para comparar topes sin reiniciar nada:
#   docker update --cpus 2.0 bragi && ./probar-limites.sh
#   docker update --cpus 3.0 bragi && ./probar-limites.sh

set -uo pipefail

DUR="${1:-60}"
C="${BRAGI_CONTENEDOR:-bragi}"
FF=/usr/lib/jellyfin-ffmpeg/ffmpeg

docker inspect "$C" >/dev/null 2>&1 || { echo "El contenedor '$C' no existe. Levantalo primero."; exit 1; }
[ "$(docker inspect -f '{{.State.Running}}' "$C")" = true ] || { echo "El contenedor '$C' no esta corriendo."; exit 1; }

echo "== Topes efectivos del contenedor =="
ncpu=$(nproc)
q=$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$C")
m=$(docker inspect -f '{{.HostConfig.Memory}}' "$C")
if [ "$q" -gt 0 ] 2>/dev/null; then
    printf "  CPU:      %.2f de %d hilos (%.0f %% de la maquina)\n" \
        "$(echo "$q" | awk '{print $1/1e9}')" "$ncpu" "$(echo "$q $ncpu" | awk '{print $1/1e9/$2*100}')"
else
    echo "  CPU:      SIN TOPE  <-- es el escenario que echo a Frigate"
fi
[ "$m" -gt 0 ] 2>/dev/null && echo "  Memoria:  $((m / 1048576)) MiB" || echo "  Memoria:  sin tope"
echo "  Peso relativo (cpu_shares): $(docker inspect -f '{{.HostConfig.CpuShares}}' "$C")"

echo
echo "== Buscando un HEVC 10 bit, que es el caso peor =="
rel=$(docker exec "$C" sh -c '
  find /media -type f -name "*.mkv" 2>/dev/null | head -40 | while IFS= read -r f; do
    c=$(/usr/lib/jellyfin-ffmpeg/ffprobe -v quiet -select_streams v:0 \
        -show_entries stream=codec_name,pix_fmt -of csv=p=0 "$f" 2>/dev/null)
    case "$c" in hevc,yuv420p10le) echo "$f"; break ;; esac
  done')
[ -z "$rel" ] && { echo "  No encontre ningun HEVC 10 bit en /media."; exit 1; }
echo "  $(basename "$rel" | cut -c1-70)"

echo
echo "== Carga del host ANTES =="
uptime | sed 's/^/  /'

echo
echo "== Transcode HEVC 10bit -> H.264 1080p, ${DUR}s de video, dentro del contenedor =="
# ffmpeg emite la linea con speed= al terminar, pero DESPUES imprime los resumenes de
# cada codec. Hay que filtrar por speed=, no quedarse con las ultimas lineas.
salida=$(docker exec "$C" "$FF" -hide_banner -nostats -t "$DUR" -i "$rel" \
    -c:v libx264 -preset veryfast -crf 23 -c:a aac -f null - 2>&1)
echo "$salida" | grep -E 'speed=|frame=' | tail -1 | sed 's/^/  /'
speed=$(echo "$salida" | grep -oE 'speed=[0-9.]+x' | tail -1 | sed 's/speed=//; s/x$//')

echo
echo "== Carga del host DESPUES =="
uptime | sed 's/^/  /'

echo
echo "== Veredicto =="
if [ -n "$speed" ]; then
    ok=$(echo "$speed" | awk '{print ($1 >= 1.0) ? "si" : "no"}')
    margen=$(echo "$speed" | awk '{printf "%.0f", ($1 - 1) * 100}')
    if [ "$ok" = si ]; then
        echo "  speed=${speed}x -> SOSTIENE un transcode en tiempo real (${margen} % de margen)."
        echo "  Dos transcodes simultaneos necesitarian $(echo "$speed" | awk '{printf "%.2f", 2}')x; no caben."
    else
        echo "  speed=${speed}x -> NO llega a tiempo real. La reproduccion se entrecortaria."
        echo "  Sube BRAGI_CPUS o asegura que los clientes reproduzcan en directo."
    fi
else
    echo "  No pude leer la velocidad; revisa la salida de arriba."
fi

echo
echo "== Heimdall aguanto el pico? =="
if docker inspect yggdrasil-prometheus >/dev/null 2>&1; then
    docker exec yggdrasil-prometheus wget -qO- http://localhost:9090/api/v1/alerts 2>/dev/null |
        python3 -c "import sys,json; a=json.load(sys.stdin)['data']['alerts']; print('  alertas activas:', len(a)); [print('   -', x['labels'].get('alertname'), x['labels'].get('wan',''), x['state']) for x in a]" 2>/dev/null ||
        echo "  (no pude consultar Prometheus)"
else
    echo "  (Prometheus no esta aqui)"
fi
