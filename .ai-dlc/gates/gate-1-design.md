# Gate 1 — Design

- [x] C4 Container (`docs/02-design/architecture.md`)
- [x] Secuencia del flujo crítico (login remoto) y estado del servicio
- [x] Threat model STRIDE (T1–T12) + DREAD residual
- [x] ADR de placement (ADR-0002, clase E sin matriz PxD por proporcionalidad: no hay
      candidato de nube razonable para 2,2 TB de vídeo)
- [x] ADRs 0001, 0003, 0005 aceptadas
- [ ] **HITL: ADR-0004** — acceso externo: túnel en zona aparte (A), en `higerotech.com` (B),
      WireGuard (C) o solo LAN (D). Bloquea el gate por T9.
- [ ] **HITL: T7** — restringir el export NFS del NAS a la IP del appliance (acción fuera de Bragi).
- [x] Contratos: no aplica (Bragi no publica API propia; la de Jellyfin es upstream).

Evidencia: C4 + sequence + state + DFD + quadrant.
Al aprobar: cortar `0.2.0`.
