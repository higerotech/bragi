# Observabilidad — Bragi

* **Estado:** review
* **Fecha:** 2026-09-18
* **Decisores:** Jeremi
* **Fase AI-DLC:** 06-monitoring
* **Versión:** 0.6.0-dev
* **Gate:** 5

Bragi no trae su propio stack de observabilidad: se integra en **Heimdall** (Yggdrasil), que ya
corre en el appliance (ADR-0009).

## Qué se vigila

| Pregunta | Métrica | Alerta | Umbral y porqué |
|---|---|---|---|
| ¿Vive en la LAN? | `bragi_up{comprobacion="lan"}` | `BragiCaido` (critical) | 3 min: un despliegue reinicia Jellyfin ~30 s |
| ¿Vive desde fuera? | `bragi_up{comprobacion="externo"}` | `BragiExternoCaido` | 5 min; se calla si la casa no tiene ruta |
| ¿Llegan las métricas? | `up{job="bragi"}`, `bragi_collector_timestamp_seconds` | `BragiSinMetricas` | 3 min: sin ellas ninguna otra alerta salta |
| ¿Hay respaldo? | `bragi_backup_last_success_timestamp_seconds` | `BragiRespaldoAtrasado` | 30 h: diario, con `Persistent=true` |
| ¿Cabe el transcode? | `bragi_transcodes` | `BragiMasDeUnTranscode` | >1: solo cabe uno (ADR-0002) |
| ¿CPU anómala? | `bragi:cpu_uso:ratio_5m` | `BragiCpuAltaSinTranscode` | >80 % del tope 20 min **sin** transcode |
| ¿Memoria? | `bragi_memory_bytes{tipo="anon"}` | `BragiMemoriaAlta` | >85 % de 2 GiB; la caché no cuenta |
| ¿Afecta al router? | `bragi_transcodes` + `ALERTS` de WAN | `BragiTranscodeConWanDegradada` (info) | Correlación para RNF02 |

También se exportan, para paneles: `bragi:cpu_limitado:ratio_5m` (fracción de periodos en el
tope), `bragi_health_seconds`, `bragi_container_running`, `bragi_ffmpeg_processes`,
`bragi_cpu_limit_cores`, `bragi_memory_limit_bytes` y `bragi_backup_last_bytes`.

## Cómo fluye

```mermaid
C4Dynamic
    title Observabilidad — de Bragi a una persona

    Container(timer, "bragi-metricas.timer", "systemd, host", "Cada 30 s")
    Container(cg, "cgroup de bragi", "kernel", "CPU, throttling, memoria, procesos")
    Container(met, "bragi-metricas", "busybox httpd", "Solo en yggdrasil_heimdall")
    Container(mimir, "Mimir", "Prometheus", "Scrape y reglas de Bragi")
    Container(gj, "Gjallarhorn", "Alertmanager", "Agrupa y enruta")
    Container(nornas, "Nornas", "Node-RED", "Aviso push")
    Person(jeremi, "Jeremi")

    Rel(timer, cg, "1. lee")
    Rel(timer, met, "2. escribe bragi.prom")
    Rel(mimir, met, "3. scrape /bragi.prom")
    Rel(mimir, gj, "4. alerta disparada")
    Rel(gj, nornas, "5. webhook con Bearer")
    Rel(nornas, jeremi, "6. Heimdall: <alerta>")
```
*Eje comportamiento · C4 Dynamic · Gate 5.*

```mermaid
sequenceDiagram
    autonumber
    participant T as bragi-metricas.timer
    participant C as cgroup y /health
    participant M as Mimir
    participant G as Gjallarhorn
    participant N as Nornas
    loop cada 30 s
        T->>C: lee CPU, memoria, procesos y health
        T->>T: escribe bragi.prom de forma atómica
        M->>T: scrape vía bragi-metricas
    end
    M->>M: evalúa reglas cada 15 s
    alt condición sostenida durante "for"
        M->>G: alerta firing
        G->>N: webhook (agrupado, 30 s)
        N-->>N: sin etiqueta wan: aviso push
    end
```
*Eje comportamiento · secuencia de observabilidad · Gate 5.*

## Ciclo de un incidente

```mermaid
stateDiagram-v2
    [*] --> Normal
    Normal --> Pendiente: la condición se cumple
    Pendiente --> Normal: deja de cumplirse antes del "for"
    Pendiente --> Disparada: se sostiene durante el "for"
    Disparada --> Avisada: Nornas envía el push
    Avisada --> Resuelta: la condición deja de cumplirse
    Resuelta --> Normal: sin aviso de resolución (Nornas no lo envía)
    Avisada --> Avisada: repetición cada 4 h si sigue
```
*Eje comportamiento · estado del incidente · Gate 5.*

## Historial

```mermaid
timeline
    title Bragi — de la idea a la observabilidad
    2026-09-17 : Nombre y repo
               : Gates 0 a 2 (diseño, network.xml como código, CI con Jellyfin real)
    2026-09-18 madrugada : Gate 3 en staging (superfast, 1,13x)
                         : Corte del Jellyfin manual (5 min 33 s)
    2026-09-18 mañana : Túnel con límite de tasa
                      : Respaldo nocturno y simulacro de restauración
    2026-09-18 tarde : Prueba de reinicio
                     : v0.5.0
                     : Gate 5 en Heimdall
```
*Eje trazabilidad · timeline · Gate 5.*

## Instalación
1. **Bragi:** `sudo bash /srv/apps/bragi/deploy/metricas/instalar.sh` (recolector, timer y estado
   inicial del respaldo) y añadir `metricas` a `COMPOSE_PROFILES` en `deploy/.env`.
2. **Yggdrasil:** `bragi-job.yml` en `scrape_configs` y `bragi-alertas.yml` en
   `deploy/prometheus/rules/`. Lo despliega su receptor.
3. **Verificación de extremo a extremo:** parar `bragi-metricas` más de 3 min debe producir el
   aviso `Heimdall: BragiSinMetricas`.
