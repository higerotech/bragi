# Gate 5 — Monitoring

Documentación: `docs/06-monitoring/observability.md` (C4 Dynamic, secuencia, estado del incidente
y timeline) y ADR-0009.

## Artefactos
- [x] Recolector desde el cgroup (`deploy/metricas/`): CPU, throttling, memoria anónima y total,
      transcodes, health LAN y externo, último respaldo. Probado en el appliance: 0,56 s, formato
      válido, sin IPs ni URL en las etiquetas; transcode detectado (1) y separado de un `ffmpeg`
      de tarea (2 procesos)
- [x] `bragi-metricas` solo en la red `yggdrasil_heimdall`, sin puertos publicados
- [x] Especificación para Heimdall (`deploy/prometheus/`): job, 2 reglas de registro y 8 alertas,
      con **pruebas unitarias de promtool** (10 casos) en el CI
- [x] `respaldar.sh` deja el estado del último éxito verificado

## Instalación y verificación
- [x] Release a `main` (la imagen `bragi-sync` gana `busybox-extras`): `0.6.0-rc.1` (#19,
      2026-10-18). El receptor desplegó `sha-0eeb040` dos veces (el Compose cambió) y el segundo
      build no reconstruyó: un solo digest y Jellyfin recreado una vez
- [x] `deploy/metricas/instalar.sh` en el appliance y perfil `metricas` activo: 18 series, marca
      del respaldo sembrada desde `bragi-config-20261018T0930Z`, `COMPOSE_PROFILES=tunel,metricas`
- [x] `deploy/respaldo/instalar.sh` otra vez: `/usr/local/sbin/bragi-respaldar.sh` es una copia
      instalada a mano y sin él el respaldo no escribe la marca de éxito (`metricas/instalar.sh`
      solo la siembra una vez); sin reinstalar, `BragiRespaldoAtrasado` saltaría a las 30 h
- [x] PR en Yggdrasil con el job y las reglas, desplegado por su receptor: yggdrasil#50, en su
      `0.5.6`. Desde entonces y hasta esta release, `BragiSinMetricas` estuvo disparada porque
      `bragi-metricas` no existía (Gate 5 fusionado en develop el 2026-09-18 y sin release)
- [x] `up{job="bragi"} == 1` y series `bragi_*` en Mimir (2026-10-18 14:30 UTC): `bragi_up` LAN y
      externo 1, 0 transcodes, memoria anónima 4 % del tope, respaldo de hace 5 h, reglas de
      registro con valor; 0 alertas en el appliance
- [x] **Extremo a extremo:** parar `bragi-metricas` más de 3 min → aviso push
      `Heimdall: BragiSinMetricas` recibido por Jeremi (HITL). Parado 14:38:03 UTC, `pending`
      14:38:24, `firing` 14:41:24, una notificación al webhook de Nornas sin fallos, **push
      recibido por Jeremi**; levantado 14:42:22 y resuelta en el siguiente scrape
- [ ] SLO revisados con datos reales tras unos días (umbrales de CPU y memoria)
