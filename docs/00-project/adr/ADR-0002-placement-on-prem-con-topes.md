# ADR-0002: Placement en midgard, con topes de cgroup

* **Estado:** accepted
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0002
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A06 (diseño inseguro: disponibilidad del router)

## Contexto
Componente de clase **E** (procedimiento de placement): necesita leer 2,2 TB por la LAN a
856 Mbps. Sacarlo a la nube supondría subir la biblioteca entera y pagar almacenamiento y
salida de datos; no hay candidato de nube razonable, así que por proporcionalidad no se
construye la matriz PxD. El único hardware disponible es midgard, que es además el router.

Medido en midgard el 2026-09-17 (i3-3240, 2 núcleos / 4 hilos):

| Escenario | Resultado |
|---|---|
| Reproducción directa | CPU ≈ 0; lectura NFS 107 MB/s |
| Transcode HEVC 10 bit → H.264 1080p sin tope | 1,42x, carga 0,84 → 3,41 |
| Con `cpus: 3.0` (extrapolado) | ~1,25x |
| Con `cpus: 2.0` (extrapolado) | ~0,84x: por debajo de tiempo real |

La iGPU (HD 2500, Gen7) no decodifica HEVC, que es el 41 % de la muestra y justo lo que
habría que transcodificar. VAAPI no resuelve el cuello.

## Decisión
Bragi corre en midgard con:
- `cpus: 3.0`: sostiene **un** transcode y deja un hilo entero al enrutamiento (que además vive
  en softirq, fuera del cgroup).
- `cpu_shares: 512`: si algo del host pelea por CPU, Bragi cede primero.
- `mem_limit: 2g` y `pids_limit: 512`.
- Política de clientes que empuja a reproducción directa: sin límite de bitrate remoto por
  debajo del máximo de la biblioteca (4 Mbps). Sin límite de sesiones por cuenta familiar.

## Alternativas consideradas
| Opción | Pros | Contras |
|---|---|---|
| **midgard con topes** (elegida) | Cero coste; la biblioteca a un salto LAN | CPU compartida con el router |
| midgard sin topes | Transcode a 1,42x | Repite el caso Frigate: cero protección |
| Hardware dedicado (mini PC con Quick Sync ≥ Kaby Lake) | HEVC 10 bit por hardware, varios transcodes | Coste y otro equipo que mantener; **condición de revisión** |
| Nube | — | Subir 2,2 TB y pagar egress de vídeo: descartado |

## Consecuencias
- Positivas: el router queda protegido por el kernel y no por la buena voluntad del servicio.
- Negativas: un solo transcode; los clientes que no decodifican HEVC (algunos TV viejos) no
  tendrán fluidez si coinciden dos.
- Condiciones de revisión: si hacen falta dos transcodes simultáneos, o si Heimdall muestra
  impacto en las WAN durante un transcode, pasar a hardware dedicado con Quick Sync.
