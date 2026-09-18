# Bragi

Servidor de medios doméstico sobre [Jellyfin](https://jellyfin.org), desplegado en el appliance
de red de la casa (Ubuntu Server 24.04, i3-3240) **con topes de CPU y memoria** para que el
streaming nunca degrade el enrutamiento. Documentación bajo la metodología AI-DLC.

Bragi es el dios nórdico de la poesía, el bardo de Valhalla: el que cuenta las historias. Es
repo hermano de [Yggdrasil](https://github.com/higerotech/yggdrasil) (monitor de las WAN) y
de [Fenrir](https://github.com/higerotech/fenrir) (NVR), y sigue su convención de nombres.

## Estado
Gates 0 a 4 aprobados (0.5.0): **en producción** desde el 2026-09-18, con acceso externo por el túnel y respaldo nocturno. Siguiente: Gate 5, observabilidad en Heimdall.

| Gate | Estado |
|---|---|
| 0 Requirements | Aprobado 2026-09-17 (0.1.0) |
| 1 Design | Aprobado 2026-09-17 (0.2.0) |
| 2 Implementation | Aprobado 2026-09-17 (0.3.0) |
| 3 Testing | Aprobado 2026-09-18 (0.4.0) |
| 4 Deployment | Aprobado 2026-09-18 (0.5.0) |
| 5 Monitoring | Pendiente |

## Números que mandan el diseño
Medidos en el appliance el 2026-09-17:

- Reproducción directa: CPU ≈ 0; el NAS entrega 107 MB/s.
- Transcode HEVC 10 bit → H.264 1080p por software con `cpus: 3.0` (Gate 3, host libre): 0,92x
  con el preset de fábrica y **1,13x con `superfast`**, que es el que se usa. **Cabe un
  transcode, no dos**, y no mientras corre un escaneo (por eso las tareas pesadas van de
  madrugada).
- La iGPU (HD 2500, Gen7) no decodifica HEVC: la aceleración por hardware no ayuda aquí.

## Estructura
```
deploy/
  docker-compose.yml    # jellyfin + sync (+ tunel bajo perfil)
  .env.example          # copiar a deploy/.env en el servidor, 0600
  sync/                 # imagen bragi-sync: checkout del commit y network.xml (config.sh)
  scripts/
    probar-limites.sh   # mide si el tope de CPU sostiene un transcode
    verificar-media.sh  # comprueba el NFS antes de recrear
    politicas.sh        # aplica y verifica las politicas de cuenta por la API
  tests/
    prueba-proxy.sh     # integracion: ataca la frontera de confianza con Jellyfin real
    prueba-appliance.sh # verificacion en el appliance (staging o produccion)
  cd/                   # bootstrap, migracion y unidad de arranque (Gate 4)
docs/
  00-project/           # charter, glosario, clasificación, ADRs
  01-requirements/      # PRD con abuso, ASVS y threat assessment
  02-design/            # arquitectura y threat model
.ai-dlc/gates/          # checklists de gates
```

## Despliegue
Lo despliega el receptor de
[despliegue-continuo](https://github.com/higerotech/despliegue-continuo) al fusionar en
`main` (ADR-0003). Runbook completo en `docs/05-deployment/deployment.md`.

## Anonimización
Repositorio público. No contiene IPs, MACs, hostnames ni credenciales reales: los ejemplos usan
el rango de documentación RFC 5737 (`192.0.2.0/24`) y `example.com`. Los valores reales viven
solo en `deploy/.env` del servidor, que está en `.gitignore`.

## Licencia
GPL-3.0. Jellyfin se distribuye bajo GPL-2.0 y aquí solo se usa su imagen oficial.
