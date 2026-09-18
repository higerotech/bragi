# Gate 2 — Implementation

- [x] Implementación de los controles de configuración: `network.xml` como código (ADR-0006),
      tarea `config` con validación de entrada, `politicas.sh` para las políticas de cuenta
- [x] Test-first de la frontera de confianza: `deploy/tests/prueba-proxy.sh` contra Jellyfin real
      (P1–P8 pasan; P9 = hallazgo H1)
- [x] SAST de configuración: `docker compose config`, RS01 sin `0.0.0.0`, RS06 digest obligatorio,
      shellcheck, casos inválidos de `config.sh` (incluido un intento de inyectar XML)
- [x] Secretos: gitleaks en CI
- [x] Cadena de suministro: Trivy (config e imágenes) como informe semanal
- [x] Workflow `build` para el receptor (imagen `bragi-sync`, redespliegue si cambia el Compose)
- [x] Primera ejecución verde del CI en GitHub (PR #5, run 35297591676)
- [x] `docs/03-implementation/repo-history.md` generado con `gitgraph_from_log.py` sobre `develop`
      tras fusionar #5
- [x] **HITL H1**: 10.11.11 mientras sea solo LAN; la versión se decide antes del túnel (Gate 4)
- [x] **HITL H2**: RNF04 revisado, sin límite de sesiones (`BRAGI_SESIONES_MAX=0` por defecto)

Evidencia: salida de `prueba-proxy.sh` en el job `integracion` del CI; C4 Container actualizado.
**Aprobado 2026-09-17.** Cortado `0.3.0`.
