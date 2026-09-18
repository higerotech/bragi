#!/usr/bin/env bash
# recolectar.sh — metricas de Bragi para Heimdall (Gate 5, ADR-0009).
#
# Lo lanza bragi-metricas.timer cada 30 s. Escribe un textfile de Prometheus que sirve el
# contenedor bragi-metricas (busybox httpd) SOLO en la red yggdrasil_heimdall: sin puertos
# publicados ni reglas nuevas en el firewall del router.
#
# De donde sale cada cosa:
#   - CPU, throttling y memoria: el cgroup del contenedor. Es la unica fuente que ve tambien a
#     los ffmpeg hijos de Jellyfin; las metricas del propio proceso .NET no los cuentan.
#   - Transcodes: procesos ffmpeg del cgroup que escriben en el directorio de transcodes. Los
#     ffmpeg de las tareas (capitulos, miniaturas) no cuentan: no son un cliente esperando.
#   - Salud: /health contra la IP LAN y, si hay tunel, contra la URL publicada.
#   - Respaldo: el estado que deja respaldar.sh tras cada exito verificado.
# No publica la URL publica ni ninguna IP como etiqueta: solo `comprobacion="lan|externo"`.
set -uo pipefail

ENV_FILE=${BRAGI_ENV:-/srv/apps/bragi/deploy/.env}
SALIDA_DIR=${BRAGI_METRICAS_DIR:-/var/lib/bragi-metricas}
ESTADO_RESPALDO=${BRAGI_ESTADO_RESPALDO:-/var/lib/bragi-respaldo/ultimo-exito}
CONTENEDOR=${BRAGI_CONTENEDOR:-bragi}
TUNEL=${BRAGI_TUNEL:-bragi-tunel}

leer_env() { sed -n "s/^$1=//p" "$ENV_FILE" 2>/dev/null | tail -1; }
LAN_IP=$(leer_env HOST_LAN_IP)
PUBLICA=$(leer_env PUBLISHED_URL)
PERFILES=$(leer_env COMPOSE_PROFILES)

m=()
metrica() { m+=("$1"); }
ayuda() { metrica "# HELP $1 $3"; metrica "# TYPE $1 $2"; }

salud() {   # salud ETIQUETA URL
    local r codigo segundos
    r=$(curl -s -o /dev/null -m 10 -w '%{http_code} %{time_total}' "$2/health" 2>/dev/null || echo "000 0")
    codigo=${r%% *}; segundos=${r##* }
    metrica "bragi_up{comprobacion=\"$1\"} $([ "$codigo" = 200 ] && echo 1 || echo 0)"
    metrica "bragi_health_seconds{comprobacion=\"$1\"} $segundos"
}

ayuda bragi_up gauge "1 si /health responde 200"
ayuda bragi_health_seconds gauge "Duracion de la peticion a /health"
[ -n "$LAN_IP" ] && salud lan "http://$LAN_IP:8096"
case ",$PERFILES," in
    *,tunel,*) [[ "$PUBLICA" == https://* ]] && salud externo "$PUBLICA" ;;
esac

ayuda bragi_container_running gauge "1 si el contenedor esta en marcha"
for c in "$CONTENEDOR" "$TUNEL"; do
    en_marcha=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
    metrica "bragi_container_running{contenedor=\"$c\"} $([ "$en_marcha" = true ] && echo 1 || echo 0)"
done

pid=$(docker inspect -f '{{.State.Pid}}' "$CONTENEDOR" 2>/dev/null || echo 0)
cg=""
[ "${pid:-0}" -gt 0 ] && cg="/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pid/cgroup" 2>/dev/null)"
if [ -n "$cg" ] && [ -r "$cg/cpu.stat" ]; then
    campo() { awk -v k="$1" '$1 == k {print $2}' "$cg/$2"; }
    read -r cuota periodo < "$cg/cpu.max"
    limite=$(awk -v c="$cuota" -v p="$periodo" 'BEGIN { if (c == "max") print 0; else printf "%.3f", c / p }')
    ayuda bragi_cpu_usage_seconds_total counter "CPU consumida por el cgroup de Bragi (incluye ffmpeg)"
    metrica "bragi_cpu_usage_seconds_total $(awk -v u="$(campo usage_usec cpu.stat)" 'BEGIN { printf "%.3f", u / 1e6 }')"
    ayuda bragi_cpu_limit_cores gauge "Tope de CPU del cgroup en nucleos (0 = sin tope)"
    metrica "bragi_cpu_limit_cores $limite"
    ayuda bragi_cpu_periods_total counter "Periodos de planificacion del cgroup"
    metrica "bragi_cpu_periods_total $(campo nr_periods cpu.stat)"
    ayuda bragi_cpu_throttled_periods_total counter "Periodos en que el cgroup choco con el tope"
    metrica "bragi_cpu_throttled_periods_total $(campo nr_throttled cpu.stat)"
    ayuda bragi_memory_bytes gauge "Memoria del cgroup: total (incluye cache) y anonima"
    metrica "bragi_memory_bytes{tipo=\"total\"} $(cat "$cg/memory.current")"
    metrica "bragi_memory_bytes{tipo=\"anon\"} $(campo anon memory.stat)"
    ayuda bragi_memory_limit_bytes gauge "Tope de memoria del cgroup"
    metrica "bragi_memory_limit_bytes $(sed 's/^max$/0/' "$cg/memory.max")"

    transcodes=0; ffmpeg=0
    while read -r p; do
        [ "$(cat "/proc/$p/comm" 2>/dev/null)" = ffmpeg ] || continue
        ffmpeg=$((ffmpeg + 1))
        tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q '/transcodes/' && transcodes=$((transcodes + 1))
    done < "$cg/cgroup.procs"
    ayuda bragi_transcodes gauge "Transcodes en curso (ffmpeg que escriben en transcodes/)"
    metrica "bragi_transcodes $transcodes"
    ayuda bragi_ffmpeg_processes gauge "Procesos ffmpeg del cgroup (transcodes y tareas)"
    metrica "bragi_ffmpeg_processes $ffmpeg"
fi

if [ -r "$ESTADO_RESPALDO" ]; then
    read -r ts bytes < "$ESTADO_RESPALDO"
    ayuda bragi_backup_last_success_timestamp_seconds gauge "Ultimo respaldo verificado (epoch)"
    metrica "bragi_backup_last_success_timestamp_seconds ${ts:-0}"
    ayuda bragi_backup_last_bytes gauge "Tamano del ultimo respaldo verificado"
    metrica "bragi_backup_last_bytes ${bytes:-0}"
fi

ayuda bragi_collector_timestamp_seconds gauge "Momento de la ultima recoleccion (epoch)"
metrica "bragi_collector_timestamp_seconds $(date +%s)"

mkdir -p "$SALIDA_DIR"
tmp=$(mktemp "$SALIDA_DIR/.bragi.prom.XXXXXX")
printf '%s\n' "${m[@]}" > "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$SALIDA_DIR/bragi.prom"
