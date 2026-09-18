# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

El cierre de cada gate AI-DLC corta versión (Gate 0 → 0.1.0, Gate 1 → 0.2.0, …).

## [Unreleased]

### Cambiado
- **ADR-0004 aceptada (opción A):** el hostname público de Bragi vive en una zona propia de
  Jeremi, distinta de `higerotech.com`. Riesgo residual documentado: la zona está en la misma
  cuenta de Cloudflare (mismo par de nameservers). T9 baja en el DREAD residual.

### Añadido
- Arranque del proyecto: charter, glosario y clasificación de datos.
- PRD `mvp-streaming` (BRG-001) con requisitos funcionales, RNF, requisitos de seguridad ASVS L1,
  escenarios de abuso, C4 de contexto, journey, requirementDiagram, DFD y DREAD inicial.
- Arquitectura (C4 Container, secuencia del login remoto, estado del servicio) y threat model
  STRIDE T1–T12 con DREAD residual.
- ADR-0001 Jellyfin pineado por digest; ADR-0002 placement en midgard con topes;
  ADR-0003 despliegue con receptor y tarea sync; ADR-0005 biblioteca NFS solo lectura con
  `rslave`.
- ADR-0004 acceso externo por Cloudflare Tunnel, **propuesta** y pendiente de HITL por los
  términos de Cloudflare sobre vídeo en el CDN gratuito.
- `deploy/docker-compose.yml` llevado del despliegue manual de `~/jellyfin` en midgard:
  datos fuera del clon, `cap_drop ALL`, `no-new-privileges`, túnel bajo perfil `tunel`.
- Imagen `bragi-sync` (Dockerfile y `sync.sh`), `probar-limites.sh` y `verificar-media.sh`.
- Checklists de gates 0–5.
