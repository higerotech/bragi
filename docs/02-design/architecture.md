# Arquitectura — Bragi

* **Estado:** review
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 02-design
* **Versión:** 0.1.0
* **Gate:** 1

Bragi no tiene código de dominio propio: es **configuración y operación** de un producto
existente (Jellyfin). Por eso no hay capas Clean/DDD, `erDiagram` ni `classDiagram`: el modelo
de datos es el de Jellyfin y no lo tocamos. Lo que sí se diseña es el despliegue, las fronteras
de confianza y los topes.

## Contenedores

```mermaid
C4Container
    title Contenedores — Bragi en midgard

    Person(familia, "Familia", "TV, móvil, navegador")
    Person(jeremi, "Jeremi", "Admin, solo LAN")
    System_Ext(cf, "Cloudflare", "Edge TLS y túnel")
    System_Ext(receptor, "cd-receiver", "Despliega al recibir el workflow_run")
    System_Ext(nas, "NAS", "Export NFS de la biblioteca")

    System_Boundary(midgard, "midgard (appliance y router)") {
        Container(sync, "bragi-sync", "Alpine + git", "Un solo uso: checkout del commit desplegado")
        Container(jf, "bragi", "Jellyfin 10.11.11", "Biblioteca, cuentas, streaming. Topes: 3 CPU, 2 GiB")
        Container(tunel, "bragi-tunel", "cloudflared 2026.8.3", "Túnel saliente; perfil tunel")
        ContainerDb(db, "/var/lib/bragi", "SQLite en HDD local", "Config, usuarios, metadatos")
    }

    Rel(familia, cf, "Fuera de casa", "HTTPS")
    Rel(cf, tunel, "Entrega", "QUIC, iniciado por el túnel")
    Rel(tunel, jf, "Reenvía", "HTTP 8096, red bragi")
    Rel(familia, jf, "En casa", "HTTP 8096 IP LAN")
    Rel(jeremi, jf, "Administra", "HTTP 8096 IP LAN")
    Rel(jf, db, "Lee y escribe")
    Rel(jf, nas, "Lee", "NFS v3 solo lectura, rslave")
    Rel(receptor, sync, "Lanza con IMAGE_TAG", "docker compose")

    UpdateElementStyle(jf, $bgColor="#1168bd", $fontColor="#ffffff")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```
*Eje estructura · fase 02 · Gate 1.*

## Flujo crítico: login remoto y protección del admin

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario remoto
    participant CF as Cloudflare edge
    participant T as bragi-tunel
    participant J as Jellyfin
    U->>CF: POST /Users/AuthenticateByName (HTTPS)
    CF->>CF: Límite de tasa del login
    alt supera la tasa
        CF-->>U: 429
    else dentro de la tasa
        CF->>T: petición por el túnel (con CF-Connecting-IP)
        T->>J: HTTP + X-Forwarded-For: IP real
        J->>J: ¿remitente en KnownProxies? sí: toma la IP real
        J->>J: ¿IP real en LocalNetworkSubnets? no: sesión REMOTA
        alt cuenta con EnableRemoteAccess=false (admin)
            J-->>U: 401
        else credenciales incorrectas
            J->>J: suma intento y bloquea al llegar al límite
            J-->>U: 401
        else correcto
            J-->>U: 200 + token de sesión
        end
    end
```
*Eje comportamiento · fase 02 · Gate 1. Si `X-Forwarded-For` llega de una IP que no está en
KnownProxies, Jellyfin usa la IP del socket y la cabecera se ignora (AB03).*

## Ciclo de vida del servicio

```mermaid
stateDiagram-v2
    [*] --> Sincronizando: receptor lanza IMAGE_TAG
    Sincronizando --> Fallido: commit no está en origin/main
    Sincronizando --> Arrancando: checkout OK
    Arrancando --> Fallido: NFS no monta (runc no hace el bind)
    Arrancando --> Sano: /health 200 antes de 300 s
    Arrancando --> Fallido: health_timeout
    Sano --> Transcodificando: cliente sin soporte o límite de bitrate
    Transcodificando --> Sano: fin del transcode
    Sano --> Arrancando: apagón y vuelta (restart unless-stopped)
    Fallido --> Sincronizando: receptor hace rollback al tag anterior
```
*Eje comportamiento · fase 02 · Gate 1.*

## Despliegue
1. Push a `main` → workflow `build` publica `bragi-sync:sha-<7>`.
2. El `workflow_run` firmado llega al receptor por `deploy.<dominio>`.
3. Receptor: `docker compose -p bragi pull` + `up -d` con `IMAGE_TAG`. `sync` hace el checkout;
   Jellyfin arranca cuando `sync` termina bien.
4. Health `http://<IP LAN>:8096/health`; si falla, rollback al tag anterior.

Bootstrap único en el servidor (runbook de Gate 4): clon en `/srv/apps/bragi` (deploy:deploy
750), `deploy/.env` 0600, `/var/lib/bragi/{config,cache}` del `PUID`, migración de la config
actual desde `~/jellyfin`, entrada en `apps.yml` y recarga del receptor.
