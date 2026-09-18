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
- [ ] Release a `main` (la imagen `bragi-sync` gana `busybox-extras`)
- [ ] `deploy/metricas/instalar.sh` en el appliance y perfil `metricas` activo
- [ ] PR en Yggdrasil con el job y las reglas, desplegado por su receptor
- [ ] `up{job="bragi"} == 1` y series `bragi_*` en Mimir
- [ ] **Extremo a extremo:** parar `bragi-metricas` más de 3 min → aviso push
      `Heimdall: BragiSinMetricas` recibido por Jeremi (HITL)
- [ ] SLO revisados con datos reales tras unos días (umbrales de CPU y memoria)
