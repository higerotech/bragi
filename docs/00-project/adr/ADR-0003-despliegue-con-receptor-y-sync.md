# ADR-0003: Despliegue continuo con el receptor y una tarea sync

* **Estado:** accepted
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0003
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A03 (imágenes por SHA), A08 (webhook firmado)

## Contexto
midgard ya tiene instalado el receptor de `higerotech/despliegue-continuo`: valida el
`workflow_run` firmado, hace `docker compose pull` + `up -d` con `IMAGE_TAG=sha-<7>` y hace
rollback si falla la `health_url`. No hace `git pull`. Bragi no construye su servidor (usa la
imagen oficial), pero su compose y su configuración viven en el repo y cambian con él. Yggdrasil
resolvió el mismo desajuste en su ADR-0005 con una tarea sync.

## Decisión
Mismo patrón que Yggdrasil:
- Workflow `build` publica `ghcr.io/higerotech/bragi-sync:sha-<7>` en cada push a `main`
  (paquete **público**: el receptor hace pull anónimo).
- El compose incluye `sync`, tarea de un solo uso que hace fetch del repo público y checkout
  del commit `IMAGE_TAG` en el clon `/srv/apps/bragi`. Jellyfin espera a que termine.
- Entrada en `/etc/cd-receiver/apps.yml`: `name: bragi`, `workflow: build`,
  `health_url: http://<IP LAN>:8096/health`, `health_timeout: 300` (primer arranque en el HDD).
- La configuración persistente (`/var/lib/bragi`) vive **fuera** del clon.

## Alternativas consideradas
| Opción | Pros | Contras |
|---|---|---|
| **Receptor + sync** (elegida) | Reutiliza infraestructura; rollback de configuración por commit | Un cambio del compose entra con un despliegue de retraso; una imagen propia más |
| `tag_template` literal como el canario | Sin imagen propia | La versión viviría en `apps.yml`, fuera del repo; sin trazabilidad |
| Manual (`git pull && compose up`) | Cero piezas | Sin healthcheck ni rollback; depende de SSH |

## Consecuencias
- Positivas: despliegue al minuto de fusionar en `main`, con rollback.
- Negativas: el rollback del receptor restaura imagen y ficheros, **no la base de datos**
  (ver ADR-0001). El bootstrap del servidor (clon, `.env`, `apps.yml`, `/var/lib/bragi`)
  necesita `sudo` y es un paso manual del runbook.
