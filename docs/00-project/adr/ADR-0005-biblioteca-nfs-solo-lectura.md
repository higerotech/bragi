# ADR-0005: Biblioteca por NFS, solo lectura y con propagación rslave

* **Estado:** accepted
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0005
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A01 (mínimo privilegio sobre la biblioteca)

## Contexto
La biblioteca está en el NAS (export NFS v3). En midgard se monta en `/mnt/nas/media` con
`x-systemd.automount` e `idle-timeout=600`: es un autofs que se desmonta tras 10 minutos sin
uso y vuelve a montar al siguiente acceso. Jellyfin necesita una base SQLite, que se corrompe
sobre NFS.

## Decisión
1. Bind de `/mnt/nas/media` a `/media` **solo lectura** y con `propagation: rslave`.
2. Config y caché en disco local, en `/var/lib/bragi`, fuera del clon.
3. Antes de (re)crear el contenedor, `deploy/scripts/verificar-media.sh`.

**Por qué `rslave`.** Con la propagación por defecto (`rprivate`) los montajes y desmontajes
del autofs no llegan al contenedor: Jellyfin se queda con la vista del arranque y ve el
directorio vacío tras el primer ciclo. Comprobado en midgard el 2026-09-17 con dos contenedores
y un tmpfs montado después de arrancarlos: `rprivate` veía 0 entradas, `rslave` las 3.

**Por qué verificar antes.** Si el NFS no monta, runc dispara el automount al hacer el bind, este
falla y **el contenedor no arranca** (`error mounting /mnt/nas/media to rootfs at /media: no such
device`). Comprobado el mismo día, antes de que el NAS exportara el share.

## Alternativas consideradas
| Opción | Contras |
|---|---|
| Montaje de lectura y escritura | Jellyfin podría guardar NFOs y carátulas junto a los vídeos, pero un Bragi comprometido podría borrar o cifrar la biblioteca |
| Volumen NFS de Docker (`driver_opts`) | Saca el montaje del control de systemd y de su automount; falla distinto en cada arranque |
| Montaje fijo sin automount | Un NAS apagado deja colgado el arranque de midgard, que es el router |

## Consecuencias
- Las carátulas y metadatos se guardan en `/var/lib/bragi/config/metadata`, no junto a los
  vídeos.
- Si el NAS cae, Bragi no arranca en el siguiente despliegue: el health falla y el receptor
  hace rollback, lo cual es seguro.
