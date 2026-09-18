# Bragi

Servidor de medios doméstico sobre [Jellyfin](https://jellyfin.org), desplegado en el appliance
de red de la casa (Ubuntu Server 24.04, i3-3240) **con topes de CPU y memoria** para que el
streaming nunca degrade el enrutamiento. Documentación bajo la metodología AI-DLC.

Bragi es el dios nórdico de la poesía, el bardo de Valhalla: el que cuenta las historias. Es
repo hermano de [Yggdrasil](https://github.com/higerotech/yggdrasil) (monitor de las WAN) y
de [Fenrir](https://github.com/higerotech/fenrir) (NVR), y sigue su convención de nombres.

## Estado
Gate 0 y Gate 1 en revisión. El acceso externo (ADR-0004) espera decisión.

| Gate | Estado |
|---|---|
| 0 Requirements | Artefactos listos; falta HITL |
| 1 Design | Bloqueado por ADR-0004 (túnel y términos de Cloudflare) |
| 2–5 | Pendientes |

## Números que mandan el diseño
Medidos en el appliance el 2026-09-17:

- Reproducción directa: CPU ≈ 0; el NAS entrega 107 MB/s.
- Transcode HEVC 10 bit → H.264 1080p por software: 1,42x sin tope, ~1,25x con `cpus: 3.0`.
  **Cabe un transcode, no dos.**
- La iGPU (HD 2500, Gen7) no decodifica HEVC: la aceleración por hardware no ayuda aquí.

## Estructura
```
deploy/
  docker-compose.yml    # jellyfin + sync (+ tunel bajo perfil)
  .env.example          # copiar a deploy/.env en el servidor, 0600
  sync/                 # imagen bragi-sync: checkout del commit desplegado
  scripts/
    probar-limites.sh   # mide si el tope de CPU sostiene un transcode
    verificar-media.sh  # comprueba el NFS antes de recrear
docs/
  00-project/           # charter, glosario, clasificación, ADRs
  01-requirements/      # PRD con abuso, ASVS y threat assessment
  02-design/            # arquitectura y threat model
.ai-dlc/gates/          # checklists de gates
```

## Despliegue
Lo despliega el receptor de
[despliegue-continuo](https://github.com/higerotech/despliegue-continuo) al fusionar en
`main` (ADR-0003). El bootstrap del servidor está previsto para Gate 4.

## Anonimización
Repositorio público. No contiene IPs, MACs, hostnames ni credenciales reales: los ejemplos usan
el rango de documentación RFC 5737 (`192.0.2.0/24`) y `example.com`. Los valores reales viven
solo en `deploy/.env` del servidor, que está en `.gitignore`.

## Licencia
GPL-3.0. Jellyfin se distribuye bajo GPL-2.0 y aquí solo se usa su imagen oficial.
