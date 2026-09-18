# Gate 4 — Deployment

Runbook: `docs/05-deployment/deployment.md` (C4 Deployment, pipeline con rollback y gantt del corte).

## Artefactos
- [x] `deploy/cd/bootstrap-midgard.sh`: usuario `bragi` (ADR-0007), `/var/lib/bragi`, clon,
      `.env` con la LAN real, entrada en `apps.yml` y unidad de arranque. Idempotente
- [x] `deploy/cd/migrar-desde-manual.sh`: ventana de corte; no borra el origen
- [x] **H4:** `bragi-arranque.service` espera al NFS (con `findmnt`, porque el autofs engaña a
      `mountpoint`) y converge solo los servicios de larga duración; reintenta si el NAS tarda
- [x] Rollback de la migración documentado

## Ejecución en el appliance
- [x] Release `v0.5.0-rc.1` a `main` y build de `bragi-sync` (2026-09-18)
- [x] **[Jeremi]** Paquete GHCR `bragi-sync` público (manifest anónimo: 200)
- [x] Staging del Gate 3 desmontado
- [x] `bootstrap-midgard.sh` (usuario `bragi` 995:986, `/var/lib/bragi`, clon, `.env`, receptor
      recargado con `bragi`, unidad habilitada). Corregido a mano `TZ=Etc/UTC` → zona de la casa
- [x] **[Jeremi]** Webhook `workflow_run` (id 681171011); ping 202 con firma válida
- [x] Ventana de corte autorizada por Jeremi (2026-09-18): 0 clientes, `migrar-desde-manual.sh`
      copió 2,7 GB con la base cerrada limpia (sin WAL). Primer despliegue por el receptor:
      `despliegue OK bragi sha-b1dd0f2 en 32.1s`. **Servicio cortado 03:31:19–03:36:52 UTC (5 min 33 s)**
- [x] Verificado sin credenciales: usuario 995 `bragi`, `cap_drop ALL`, `no-new-privileges`, topes
      3 CPU / 2 GiB / shares 512, puerto solo en la IP LAN, digest, `/media` `ro`+`rslave`,
      `network.xml` con la LAN real, TZ de la casa, 0 errores en el arranque. **Mismo Id de
      servidor** que el Jellyfin manual: la base migrada cargó entera. El manual queda parado,
      sin reinicio automático y con su directorio intacto
- [x] Políticas aplicadas en producción y `prueba-appliance.sh` limpio (2026-09-18), ejecutado
      por Jeremi con su admin mediante `verificar-produccion.sh`, sin API key. Admin sin acceso
      remoto, bloqueo a 5 intentos, `superfast`, escaneo 04:00 y personas domingo 05:00 (hora de la
      casa). **F2: admin desde fuera de la LAN → 403.** `== bragi cumple ==`
- [ ] **[Jeremi] H4:** prueba de reinicio con Bragi volviendo solo
- [ ] Respaldo de `/var/lib/bragi/config` (T10), sobre todo antes de cualquier subida de versión

## Antes de activar el perfil `tunel`
- [ ] **HITL:** versión de Jellyfin (H1, ADR-0001): 10.11.11 o 12.x según el estado de #18100
- [ ] Túnel creado en la zona aparte y `TUNNEL_TOKEN` en `deploy/.env`
- [ ] Los cinco controles de ADR-0004 verificados en el appliance, incluida la regla de límite de
      tasa sobre el login
