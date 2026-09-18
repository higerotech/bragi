# Gate 4 — Deployment

Pendiente. Se abre al cerrar el gate anterior.

Previsto: runbook de bootstrap (clon, `.env`, `/var/lib/bragi`, migración desde `~/jellyfin`,
entrada en `apps.yml`) y respaldo de la config. El asistente inicial ya se completó en midgard.

- [ ] **H4:** unidad de arranque (patrón `yggdrasil-arranque.service`) que asegure que Bragi
      vuelve tras un apagón aunque el automount NFS no esté listo, y prueba de reinicio con HITL.
- [ ] `politicas.sh --aplicar` contra producción (API key de Jeremi) y `prueba-appliance.sh` limpio.
- [ ] Desmontar el staging del Gate 3 (`~/bragi-staging`): usa los nombres `bragi-sync`,
      `bragi-config` y la red `bragi` de producción.

**Antes de activar el perfil `tunel`:**
- [ ] **HITL:** versión de Jellyfin (H1, ADR-0001): 10.11.11 o 12.x según el estado de #18100.
- [ ] Los cinco controles de ADR-0004 verificados en el appliance.
