# ADR-0010: Bragi se muda a nidavellir

* **Estado:** accepted
* **Fecha:** 2026-10-26
* **Decisores:** Jeremi
* **Fase AI-DLC:** 05-deployment
* **Versión:** 1.0.0
* **ID:** ADR-0010
* **Supersede / Superseded-by:** modifica la ADR-0002 (placement) y la ADR-0005 (biblioteca)
* **Controles OWASP afectados:** A05 (configuración), A06 (diseño inseguro: disponibilidad)

## Contexto
- **El NAS está al 99 %.** Las películas (705 GB) salen de él para dejar sitio a los respaldos.
  Se copiaron y verificaron fichero a fichero en el disco WD10EZEX de nidavellir el 2026-10-26
  (Fáfnir, ADR-0010 de Yggdrasil: 816 ficheros, 0 fallos).
- **nidavellir es el segundo servidor de la LAN** (192.168.10.2). Tiene un Ryzen 3 2200G (4
  núcleos) con una Radeon Vega 8 que sí decodifica HEVC 10 bit, 13 GiB de RAM y Docker con el
  receptor de despliegue continuo ya instalado. **No es el router**, así que lo que llevó a
  los topes de la ADR-0002 (proteger el enrutamiento) no se aplica.
- La ADR-0002 ya dejaba el hardware dedicado como **condición de revisión**.
- Leer las películas de nidavellir desde midgard exigiría un export NFS más y un salto LAN más
  en cada reproducción.

## Decisión
Bragi corre en nidavellir con el mismo Compose, el mismo usuario de sistema (ADR-0007) y los
mismos datos, copiados de `/var/lib/bragi` de midgard.

- **Biblioteca repartida, mismas rutas.** El contenedor sigue viendo `/media/TV` y
  `/media/movies`, así que Jellyfin no reescanea ni pierde progreso. `MEDIA_PATH=/srv/medios/bragi`
  reúne dos montajes del host:
  - `TV`: un automount NFS propio del subdirectorio `/nfs/media/TV` del NAS, de solo lectura.
  - `movies`: un bind de solo lectura de `/srv/medios/wd/peliculas`.

  El `rslave` de la ADR-0005 propaga el autofs de `TV` igual que en midgard. No hay montajes
  anidados sobre el autofs. `bragi-arranque` espera a los dos (`MEDIA_MONTAJES`). Si el WD no
  monta, el bind falla y Jellyfin no arranca. Así no ve las películas vacías ni las da por
  borradas.
- **Despliegue continuo por el reconciliador.** El webhook de GitHub llega a midgard por el túnel
  de despliegue, y nidavellir no tiene túnel propio. Su receptor encola el despliegue al ver el
  último `build` correcto (`RECONCILE_INTERVAL`, ADR-0011 de despliegue-continuo). El webhook
  deja de tener efecto: midgard ya no declara la app `bragi`.
- **Métricas por Thor.** nidavellir no tiene la red `yggdrasil_heimdall`, así que el perfil
  `metricas` queda apagado. El recolector escribe `bragi.prom` en `/var/lib/yggdrasil-thor`,
  que ya sirve `yggdrasil-thor-http.service` en `:9471` solo a midgard (`IPAddressAllow`). El
  job `bragi` de Mimir apunta allí. Las alertas no cambian.
- **Salida por PIA** (decisión de Jeremi, 2026-10-26). nidavellir sigue en `PIA_MACS` (ADR-0009
  de Yggdrasil). `cloudflared` y todo el streaming externo salen por el túnel WireGuard a PIA.
  Si PIA cae, el desvío vuelve a las WAN directas.
- **Clientes de la LAN reconfigurados** (decisión de Jeremi). Apuntan a `192.168.10.2:8096`. No
  hay redirección en midgard, así que Jellyfin ve la IP real de cada cliente.
- **Topes:** se mantienen los de la ADR-0002 (3 CPU, 2 GiB) hasta medir en nidavellir con
  `probar-limites.sh`. Subirlos, o activar VAAPI en la Vega, es un cambio aparte con su medida.

## Alternativas consideradas
| Opción | Pros | Contras |
|---|---|---|
| **Bragi en nidavellir** (elegida) | Películas en disco local; CPU sin router al lado; Vega con HEVC | Un host que se colgó el 2026-10-25 (mitigado con watchdog); CD por sondeo |
| Bragi en midgard, WD exportado por NFS a midgard | Nada cambia para los clientes | Export y salto LAN nuevos; sigue compitiendo con el router |
| Dejar las películas en el NAS | Sin trabajo | El NAS no tiene sitio para los respaldos |
| Sacar nidavellir de PIA | Streaming externo directo | Jeremi prefiere mantener nidavellir en PIA |

## Consecuencias
- Positivas:
  - midgard deja de cargar con el vídeo: el caso Frigate desaparece por diseño.
  - Las películas se leen del disco local, sin pasar por la red.
  - La Vega abre la puerta al transcode HEVC por hardware.
- Negativas:
  - Las películas tienen **una sola copia** (el WD). Se aceptó porque se pueden volver a
    descargar; Fáfnir les exige una copia (`copias_minimas = 1`) y avisa si se queda sin ella.
  - nidavellir se colgó el 2026-10-25. Desde entonces tiene el watchdog `sp5100_tco` y
    `processor.max_cstate=1`; si vuelve a colgarse, Bragi cae hasta que el watchdog lo reinicie.
  - Un despliegue tarda hasta `RECONCILE_INTERVAL` + gracia en llegar.
  - El streaming externo depende del ancho de banda de PIA.
- Seguimiento:
  - Medir los topes en nidavellir.
  - Decidir VAAPI.
  - Borrar las películas del NAS solo cuando Bragi lleve días sano en nidavellir, con
    confirmación de Jeremi.
  - Retirar de midgard `/var/lib/bragi` y `~/jellyfin` (son el rollback).
