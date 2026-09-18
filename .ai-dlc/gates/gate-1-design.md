# Gate 1 — Design

- [x] C4 Container (`docs/02-design/architecture.md`)
- [x] Secuencia del flujo crítico (login remoto) y estado del servicio
- [x] Threat model STRIDE (T1–T12) + DREAD residual
- [x] ADR de placement (ADR-0002, clase E sin matriz PxD por proporcionalidad: no hay
      candidato de nube razonable para 2,2 TB de vídeo)
- [x] ADRs 0001, 0003, 0005 aceptadas
- [x] **HITL: ADR-0004** — opción A aceptada el 2026-09-17: túnel en una zona propia de
      Jeremi, distinta de `higerotech.com`. Riesgo residual: misma cuenta de Cloudflare.
- [x] **HITL: T7** — export `media` del NAS restringido a la IP del appliance el 2026-09-17
      (panel del NAS). Verificado: montaje nuevo desde el appliance OK; desde otro equipo de
      la LAN, `access denied by server`.
- [x] Contratos: no aplica (Bragi no publica API propia; la de Jellyfin es upstream).

Evidencia: C4 + sequence + state + DFD + quadrant.
**Aprobado 2026-09-17** por Jeremi. Cortado `0.2.0`; arquitectura y threat model en `approved`.
