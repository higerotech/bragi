# ADR-0001: Jellyfin como servidor de medios, en Docker con imagen pineada

* **Estado:** accepted
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0001
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A03 (supply chain), A08 (integridad de software)

## Contexto
Hace falta un servidor de medios para una biblioteca de 2,2 TB, con cuentas por persona y
clientes de TV y móvil. Corre en un appliance que también es el router de la casa.

## Decisión
Jellyfin 10.11.11, imagen oficial `jellyfin/jellyfin`, **pineada por digest** en el
`docker-compose.yml`. Subir de versión es un PR que cambia esa línea; el receptor lo
despliega y, si el health falla, vuelve al commit anterior.

## Alternativas consideradas
| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Jellyfin** (elegida) | Libre (GPL-2.0), sin cuenta en la nube, clientes para TV y móvil | Clientes de TV menos pulidos | Bajo: todo local |
| Plex | Clientes excelentes | Requiere cuenta en plex.tv; funciones clave de pago; telemetría | La autenticación depende de un tercero |
| Emby | Parecido a Jellyfin | Funciones clave de pago; Jellyfin es su fork libre | Medio |
| Imagen `linuxserver/jellyfin` | Popular | Una capa más de terceros sobre el upstream | Supply chain mayor |

## Consecuencias
- Positivas: rollback trivial por commit; ninguna dependencia de nubes para autenticar.
- **Decisión de versión (HITL 2026-09-17, hallazgo H1):** se queda la 10.11.11 mientras Bragi sea
  solo LAN. Antes de activar el túnel (Gate 4) se decide entre 10.11.11 y 12.x con estos datos: el
  bloqueo por intentos no funciona en 10.11.11 (jellyfin#17278), la 12.0 tiene un OOM en
  `/UserViews` (#17871) y la 12.1 un informe abierto de corrupción de la base (#18100). Si se sube,
  hacerlo con la base aún pequeña y con respaldo previo, y convertir P9 en prueba obligatoria.
- Negativas: la actualización es manual (un PR). Jellyfin migra su base de datos entre minors,
  así que **antes de subir de minor hay que respaldar `/var/lib/bragi/config`**: el rollback de
  la imagen no deshace una migración de esquema.
- Impacto en threat model: mitiga la cadena de suministro (T6).
