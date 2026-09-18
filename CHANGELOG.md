# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

El cierre de cada gate AI-DLC corta versión (Gate 0 → 0.1.0, Gate 1 → 0.2.0, …).

## [Unreleased]

## [0.3.0] - 2026-09-17

**Gate 2 (Implementation) aprobado.**

### Cambiado
- **RNF04 revisado (HITL, hallazgo H2):** sin límite de sesiones por cuenta. `MaxActiveSessions`
  cuenta dispositivos con sesión, no reproducciones, y los topes de CPU ya protegen el router.
  `politicas.sh` aplica `0` por defecto. PRD pasa a 0.1.1.
- **Versión de Jellyfin (HITL, hallazgo H1):** se mantiene la 10.11.11 mientras Bragi sea solo LAN;
  la versión se decide antes de activar el túnel (Gate 4). Anotado en ADR-0001 y en el Gate 4.

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

### Pendiente
- **H5: el transcode con `cpus: 3.0` dio 0,78x** en el appliance, con el Jellyfin manual en pleno
  escaneo de la biblioteca. Falta la medida sin contención para decidir el tope.
- **H4:** arranque tras apagón sin probar; pasa al Gate 4.

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

[Unreleased]: https://github.com/higerotech/bragi/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/higerotech/bragi/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/higerotech/bragi/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/higerotech/bragi/releases/tag/v0.1.0
