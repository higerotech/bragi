# ADR-0009: Observabilidad de Bragi en Heimdall

* **Estado:** accepted
* **Fecha:** 2026-09-18
* **Decisores:** Jeremi
* **Fase AI-DLC:** 06-monitoring
* **Versión:** 1.0.0
* **ID:** ADR-0009
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A09 (registro y monitorización)

## Contexto
El Gate 5 exige que los fallos de Bragi lleguen a una persona. En el appliance ya corre Heimdall
(Yggdrasil): Mimir (Prometheus), Gjallarhorn (Alertmanager) y Nornas, que convierte cualquier
alerta **sin etiqueta `wan`** en un aviso push. Heimdall solo mide las WAN: no hay cAdvisor ni
node_exporter, así que no existe ninguna métrica de contenedores.

Tres preguntas guían el diseño:
1. ¿Está Bragi vivo, dentro de casa y desde fuera?
2. ¿Hay respaldo reciente? (riesgo aceptado en ADR-0008)
3. ¿Se come Bragi el router? (RNF02, la razón de ser de los topes de ADR-0002)

Las métricas del propio Jellyfin no bastan para la tercera: el proceso .NET no incluye a los
`ffmpeg` hijos, que son justo los que consumen CPU al transcodificar.

## Decisión
- **Recolector en el host** (`bragi-metricas.timer`, cada 30 s). Lee el **cgroup del contenedor**
  (CPU, periodos limitados por el tope, memoria anónima y total), cuenta los transcodes (los
  `ffmpeg` que escriben en `transcodes/`), comprueba `/health` en la LAN y por la URL pública, y
  lee el estado que deja `respaldar.sh` tras cada éxito verificado.
- **Lo sirve `bragi-metricas`**: `httpd` de busybox sobre la misma imagen `bragi-sync`, solo
  lectura, sin root y **solo en la red `yggdrasil_heimdall`**. Sin puertos publicados ni reglas
  nuevas en el firewall del router. Va en el perfil `metricas`, así que sin él Bragi no depende
  de Yggdrasil.
- **Especificación en este repo e instalación en Yggdrasil**, como hizo Fenrir:
  `deploy/prometheus/bragi-job.yml` y `bragi-alertas.yml`, con pruebas unitarias de `promtool`.
- **Alertas** (sin etiqueta `wan` → aviso push de Nornas): `BragiCaido`, `BragiExternoCaido`,
  `BragiSinMetricas`, `BragiRespaldoAtrasado`, `BragiMasDeUnTranscode`,
  `BragiCpuAltaSinTranscode`, `BragiMemoriaAlta` y `BragiTranscodeConWanDegradada` (informativa).

**Estar en el tope de CPU durante un transcode es lo diseñado, no un fallo.** Por eso no hay
alerta de "en el tope" a secas: se alerta de lo anómalo (tope sin transcode, dos transcodes a la
vez) y de la correlación con una WAN degradada.

## Alternativas consideradas
| Opción | Por qué no |
|---|---|
| cAdvisor | Un servicio más con acceso de lectura a todo Docker y ~100 MB de RAM, para medir un solo contenedor |
| Métricas de Jellyfin (`/metrics`) | No ven los `ffmpeg`; además el endpoint quedaría detrás del túnel público |
| node_exporter con *textfile collector* | Otro servicio en host-mode y una regla nueva en el firewall (como Sleipnir) |
| Publicar el puerto 9470 en `docker0` | Regla nueva en el `nftables` del router; la red compartida lo evita |

## Consecuencias
- Positivas: los tres riesgos del diseño (caída, respaldo y router) quedan vigilados con los
  canales que ya existen.
- Negativas: si el timer se para no hay métricas. Lo cubre `BragiSinMetricas`. Nornas no avisa
  de las resoluciones, solo de los disparos.
- `BragiExternoCaido` se calla si la casa no tiene ruta (`hogar:ruta_up`): para eso ya está
  `HogarSinRuta`.
