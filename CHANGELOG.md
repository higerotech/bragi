# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

El cierre de cada gate AI-DLC corta versión (Gate 0 → 0.1.0, Gate 1 → 0.2.0, …).

## [Unreleased]

### Desplegado
- **Acceso externo por el túnel activo** (2026-09-18) en la zona aparte de ADR-0004, con los
  controles verificados desde internet: IP real del cliente en Jellyfin, admin bloqueado desde
  fuera y límite de tasa de Cloudflare sobre el login (429). Se mantiene Jellyfin 10.11.11 (H1).
- Políticas aplicadas en producción y verificación completa en verde con la cuenta real del
  operador (admin bloqueado desde fuera de la LAN: 403).
- **Bragi en producción desde el 2026-09-18 03:36 UTC**, desplegado por el receptor
  (`sha-b1dd0f2`). Corte desde el Jellyfin manual en 5 min 33 s, conservando base, usuarios e
  identidad del servidor.

### Seguridad
- **Token del túnel rotado.** El primero quedó expuesto en la sesión de trabajo al diagnosticar el
  `.env` con un comando que imprimía líneas; además se había guardado corrupto (una `n` en lugar
  de salto de línea, porque la shell se comió la barra invertida de `printf`). Regla desde
  entonces: sobre ficheros con secretos, solo recuentos, longitudes y hashes; y guardar secretos con
  `echo`, sin barras invertidas.

### Corregido
- **`bootstrap-midgard.sh` tomaba la zona horaria del host**, que en el appliance es UTC. La
  ventana de tareas pesadas (01:00–06:00, hora del contenedor) habría caído en plena noche en la
  zona de la casa. Ahora se pasa `TZ_HOGAR` y el script avisa si queda en UTC. En el appliance se
  corrigió el `.env` a mano antes del primer despliegue.

## [0.5.0-rc.1] - 2026-09-18

**Candidata del Gate 4 (Deployment).** Primera release en `main`: trae los gates 0 a 3 y los
artefactos de despliegue. Es candidata y no `0.5.0` porque el Gate 4 se cierra después de
verificar el despliegue real (corte, políticas en producción y prueba de reinicio). Su build
publica la primera `bragi-sync` para el receptor.

### Añadido
- Runbook del Gate 4 (`docs/05-deployment/deployment.md`) con C4 Deployment, pipeline con rollback
  y gantt del corte.
- `deploy/cd/bootstrap-midgard.sh`: prepara el appliance (usuario, datos, clon, `.env`,
  inventario del receptor, unidad de arranque). Idempotente y sin secretos.
- `deploy/cd/migrar-desde-manual.sh`: ventana de corte desde el Jellyfin manual; no borra el origen.
- `deploy/cd/bragi-arranque.{sh,service}` (H4): tras un apagón espera al NFS y converge Jellyfin
  (y el túnel si está activo) sin depender de `restart: unless-stopped`.
- `deploy/cd/apps.bragi.yml`: entrada del receptor.
- CI: shellcheck de `deploy/cd` y `systemd-analyze verify` de la unidad.

### Seguridad
- **ADR-0007: Jellyfin corre con un usuario de sistema propio (`bragi`)** y no con el uid del
  operador, que tiene `sudo` sin contraseña.

## [0.4.0] - 2026-09-18

**Gate 3 (Testing) aprobado.**

### Cambiado
- **RF03 se cumple con el preset `superfast`** (HITL): con el tope de 3 CPU y el host libre, el
  transcode HEVC 10 bit a 1080p da 0,92x con `veryfast` y 1,13x con `superfast`. `politicas.sh`
  lo aplica y verifica (`EncoderPreset`).
- **Tareas pesadas de Jellyfin de madrugada:** escaneo diario a las 04:00 (de fábrica era "cada
  12 h" y podía caer a cualquier hora), personas los domingos a las 05:00. `politicas.sh`
  comprueba que escaneo, personas, capítulos y miniaturas caigan entre la 01:00 y las 06:00.
- ADR-0002 pasa a 1.1.0 con ambas decisiones.
- `.gitattributes` fuerza LF: un clon de Windows con `core.autocrlf=true` dejaba los scripts con
  CRLF, y copiados al appliance rompen bash.

### Añadido
- `deploy/tests/docker-compose.staging.yml`: el compose de producción levantado en el appliance
  junto al despliegue actual (puerto 18096, base propia), sin receptor ni GHCR.
- `deploy/tests/prueba-appliance.sh`: verificador en el appliance (RS01, RS05, RS06, RS08, topes,
  `rslave`, `network.xml`, frontera de confianza en la red real y deriva de políticas). Se
  reutiliza en el Gate 4 contra producción.
- `docs/04-testing/test-plan.md` con los resultados del staging del 2026-09-17.

### Seguridad
- Verificado en la red real que Docker conserva la IP del cliente LAN en el puerto publicado (F3)
  y que un contenedor de `docker0` cuenta como remoto (F2).

### Corregido
- **H5, RF03 en el appliance:** con el preset de fábrica y `cpus: 3.0`, 0,78x con el Jellyfin
  manual escaneando y 0,92x sin contención (dos pausas de producción autorizadas, 82 s y 124 s,
  sin clientes). Resuelto con `superfast` (1,13x); ver "Cambiado".

### Trasladado al Gate 4
- **H4:** arranque tras apagón sin probar (patrón `yggdrasil-arranque.service` y prueba de
  reinicio con HITL).

## [0.3.0] - 2026-09-17

**Gate 2 (Implementation) aprobado.**

### Cambiado
- **RNF04 revisado (HITL, hallazgo H2):** sin límite de sesiones por cuenta. `MaxActiveSessions`
  cuenta dispositivos con sesión, no reproducciones, y los topes de CPU ya protegen el router.
  `politicas.sh` aplica `0` por defecto. PRD pasa a 0.1.1.
- **Versión de Jellyfin (HITL, hallazgo H1):** se mantiene la 10.11.11 mientras Bragi sea solo LAN;
  la versión se decide antes de activar el túnel (Gate 4). Anotado en ADR-0001 y en el Gate 4.

### Añadido
- `docs/03-implementation/repo-history.md`, derivado del historial real de `develop`.
- **`network.xml` de Jellyfin como código** (ADR-0006): plantilla horneada en `bragi-sync` y tarea
  `config` de un solo uso que la escribe en cada despliegue, como el usuario de Jellyfin y sin red.
  Valida `LAN_SUBNET` y `TUNEL_IP` antes de escribir. Jellyfin se recrea en cada despliegue
  (`BRAGI_REV`) porque solo lee `network.xml` al arrancar.
- `deploy/scripts/politicas.sh`: aplica y verifica por la API las políticas de cuenta (admin sin
  acceso remoto, bloqueo a 5 intentos, límite de sesiones, sin límite de bitrate remoto).
- `deploy/tests/prueba-proxy.sh`: prueba de integración de la frontera de confianza contra un
  Jellyfin 10.11.11 real, atacada desde la LAN, desde el proxy de confianza y desde otro
  contenedor. Incluye el `X-Forwarded-For` falsificado a través de Cloudflare (P5).
- Workflow `build` (publica `bragi-sync` para el receptor) y workflow `ci` (compose, RS01, RS06,
  shellcheck, casos inválidos de `config.sh`, integración, gitleaks, Trivy).
- `LAN_SUBNET` en `.env.example`.

### Seguridad
- **H1: el bloqueo por intentos de Jellyfin 10.11.11 no bloquea** (jellyfin#17278, arreglado en
  12.0). Frente a la fuerza bruta (T1) quedan el límite de tasa de Cloudflare y la longitud de la
  clave. P9 queda como fallo conocido hasta la decisión HITL sobre la versión.
- **H2: `MaxActiveSessions` limita dispositivos con sesión, no reproducciones.** RNF04 queda
  pendiente de revisión HITL. `BRAGI_SESIONES_MAX` permite ajustar el límite sin tocar el script.

## [0.2.0] - 2026-09-17

**Gate 1 (Design) aprobado.**

### Añadido
- Arquitectura (C4 Container, secuencia del login remoto, estado del servicio) y threat model
  STRIDE T1–T12 con DREAD residual.
- ADR-0001 Jellyfin pineado por digest; ADR-0002 placement en midgard con topes;
  ADR-0003 despliegue con receptor y tarea sync; ADR-0005 biblioteca NFS solo lectura con
  `rslave`.
- ADR-0004 acceso externo por Cloudflare Tunnel, aceptada en su opción A: el hostname público
  vive en una zona propia de Jeremi, distinta de `higerotech.com`. Riesgo residual documentado:
  la zona está en la misma cuenta de Cloudflare (mismo par de nameservers).
- `deploy/docker-compose.yml` llevado del despliegue manual de `~/jellyfin` en midgard:
  datos fuera del clon, `cap_drop ALL`, `no-new-privileges`, túnel bajo perfil `tunel`.
- Imagen `bragi-sync` (Dockerfile y `sync.sh`), `probar-limites.sh` y `verificar-media.sh`.
- Guardia de GitFlow hacia `main` (check exigido por el ruleset Protect-MAIN).

### Seguridad
- **T7 cerrado:** el export NFS `media` del NAS pasa de `*` a la IP del appliance (cambio en el
  panel del NAS). Verificado con un montaje nuevo desde el appliance (OK) y otro desde un equipo
  de la LAN (`access denied by server`).

## [0.1.0] - 2026-09-17

**Gate 0 (Requirements) aprobado.**

### Añadido
- Arranque del proyecto: charter, glosario y clasificación de datos.
- PRD `mvp-streaming` (BRG-001) con requisitos funcionales, RNF, requisitos de seguridad ASVS L1,
  escenarios de abuso, C4 de contexto, journey, requirementDiagram, DFD y DREAD inicial.
- Checklists de gates 0–5.

[Unreleased]: https://github.com/higerotech/bragi/compare/v0.5.0-rc.1...HEAD
[0.5.0-rc.1]: https://github.com/higerotech/bragi/compare/v0.4.0...v0.5.0-rc.1
[0.4.0]: https://github.com/higerotech/bragi/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/higerotech/bragi/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/higerotech/bragi/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/higerotech/bragi/releases/tag/v0.1.0
