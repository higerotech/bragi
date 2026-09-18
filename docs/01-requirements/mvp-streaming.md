# PRD — MVP de streaming doméstico (Bragi)

* **Estado:** approved (Gate 0, 2026-09-17)
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 01-requirements
* **Versión:** 0.1.1
* **Gate:** 0
* **Feature ID:** BRG-001
* **ASVS:** L1 (V2 autenticación, V3 sesiones, V4 control de acceso, V9 comunicaciones, V14 configuración)

## Problema
La biblioteca (2,2 TB) está en el NAS y no hay forma cómoda de verla desde el TV o el móvil,
y menos fuera de casa. El único servidor disponible es el router de la casa, que no puede
permitirse otro episodio como el de Frigate (45,7 % de CPU media, retirado el 2026-09-11).

## Objetivos
1. Ver cualquier título de la biblioteca en TV, móvil y navegador, en casa y fuera.
2. Una cuenta por persona, con el administrador separado de las cuentas de uso.
3. El streaming nunca degrada el enrutamiento: medible con Heimdall.
4. Despliegue reproducible desde el repo, con rollback.

## No-objetivos
Ver el no-scope del [charter](../00-project/charter.md): adquisición de contenido, más de un
transcode, HEVC por hardware, DLNA, plugins de terceros y Live TV.

## Requisitos funcionales
| ID | Requisito | Verificación |
|---|---|---|
| RF01 | La biblioteca del NAS aparece en Jellyfin, separada en Películas y Series | Prueba: escaneo completo y recuento contra el NAS |
| RF02 | Reproducción directa de H.264 8 bit y HEVC 10 bit en clientes que los soportan | Prueba: panel de actividad muestra "Direct Play" |
| RF03 | Un transcode HEVC 10 bit → H.264 1080p sostenido a ≥ 1,0x con los topes puestos | `probar-limites.sh`: speed ≥ 1,0 |
| RF04 | Acceso externo por HTTPS a un subdominio propio, sin puertos abiertos en las WAN | Prueba desde datos móviles |
| RF05 | Despliegue automático al fusionar en `main`, con rollback si el health falla | Prueba: despliegue con health roto a propósito |

## Requisitos no funcionales
| ID | Requisito |
|---|---|
| RNF01 | Bragi no pasa de 3 hilos de 4 ni de 2 GiB de RAM (tope de cgroup, no buena voluntad) |
| RNF02 | Durante un transcode, las sondas de Heimdall no registran pérdida atribuible a CPU |
| RNF03 | Arranca solo tras un apagón (midgard no tiene UPS) |
| RNF04 | ~~Como máximo 2 sesiones de reproducción simultáneas por cuenta familiar~~ **Sin límite de sesiones por cuenta** (revisado por HITL el 2026-09-17, hallazgo H2): el límite de Jellyfin cuenta dispositivos con sesión, no reproducciones, y la protección del router ya la dan los topes de RNF01 |

## Requisitos de seguridad (ASVS L1)
| ID | Requisito | ASVS | OWASP Top 10:2025 |
|---|---|---|---|
| RS01 | Puerto 8096 atado solo a la IP LAN; nunca a `0.0.0.0` ni a una WAN | V14.4 | A02 |
| RS02 | La cuenta admin no puede autenticarse desde fuera de la LAN | V4.1 | A01 |
| RS03 | Bloqueo de cuenta tras intentos fallidos y límite de tasa del login en Cloudflare | V2.2 | A07 |
| RS04 | Jellyfin solo confía en `X-Forwarded-For` del contenedor del túnel (KnownProxies); la red Docker **no** cuenta como LAN | V14.5 | A01, A05 |
| RS05 | La biblioteca se monta solo lectura: un Bragi comprometido no borra ni cifra la biblioteca | V4.1 | A01 |
| RS06 | Imágenes pineadas por digest; sin `latest` | V14.2 | A03, A08 |
| RS07 | Ningún secreto ni dato de la instalación en el repo | V14.1 | A02 |
| RS08 | Contenedor sin root, sin capacidades y con `no-new-privileges` | V14.2 | A02 |
| RS09 | Contraseñas de ≥ 12 caracteres en todas las cuentas; alta solo por el admin, sin autorregistro | V2.1 | A07 |

## Escenarios de abuso
| ID | Escenario | Control |
|---|---|---|
| AB01 | Un bot en internet prueba contraseñas contra `/Users/AuthenticateByName` a través del túnel | RS03, RS09 |
| AB02 | Con credenciales de un familiar, alguien intenta entrar al panel de administración | RS02, perfil sin privilegios |
| AB03 | Un atacante manda `X-Forwarded-For: 192.0.2.50` para parecer de la LAN y saltarse RS02 | RS04 |
| AB04 | Un usuario remoto con límite de bitrate fuerza transcodes y se come la CPU del router | Tope RNF01, bitrate remoto sin límite bajo |
| AB05 | Una vulnerabilidad de Jellyfin da ejecución en el contenedor e intenta tocar la biblioteca o el host | RS05, RS08, red propia |
| AB06 | Tráfico de vídeo por el CDN gratuito de Cloudflare dispara la suspensión por sus términos | Decisión HITL en ADR-0004 |
| AB07 | Un equipo cualquiera de la LAN monta el export NFS de la biblioteca | Export restringido a la IP del appliance en el NAS (T7) |

## Contexto

```mermaid
C4Context
    title Contexto — Bragi, servidor de medios doméstico

    Person(jeremi, "Jeremi", "Administra Bragi desde la LAN")
    Person(familia, "Familia", "Ve series y películas en TV, móvil y navegador")
    Person_Ext(atacante, "Atacante en internet", "Prueba credenciales contra el login publicado")

    Enterprise_Boundary(lan, "LAN doméstica (trust boundary nftables)") {
        System(bragi, "Bragi", "Jellyfin con topes sobre midgard")
        System_Ext(nas, "NAS", "Biblioteca de 2,2 TB por NFS")
        System_Ext(heimdall, "Heimdall (Yggdrasil)", "Testigo del SLA de las WAN")
    }

    System_Ext(cf, "Cloudflare", "Túnel y TLS del subdominio público")
    System_Ext(gh, "GitHub + receptor", "Despliegue continuo firmado")
    System_Ext(tmdb, "TMDB y otros", "Metadatos y carátulas")

    Rel(jeremi, bragi, "Administra", "HTTP 8096 LAN")
    Rel(familia, bragi, "Ve en casa", "HTTP 8096 LAN")
    Rel(familia, cf, "Ve fuera de casa", "HTTPS")
    Rel(atacante, cf, "Ataca el login", "HTTPS")
    Rel(cf, bragi, "Entrega por el túnel", "QUIC saliente")
    Rel(bragi, nas, "Lee la biblioteca", "NFS v3 solo lectura")
    Rel(bragi, tmdb, "Descarga metadatos", "HTTPS")
    Rel(gh, bragi, "Despliega", "webhook firmado")
    Rel(heimdall, bragi, "Vigila el impacto en", "sondas WAN")

    UpdateElementStyle(bragi, $bgColor="#1168bd", $fontColor="#ffffff")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```
*Eje estructura · fase 01 · Gate 0.*

## Recorrido del usuario

```mermaid
journey
    title Ver un capitulo desde fuera de casa
    section Entrar
      Abre la app de Jellyfin en el movil: 4: Familia
      Pone usuario y clave una vez: 3: Familia
    section Elegir
      Busca la serie y el capitulo: 5: Familia
      Retoma donde lo dejo en el TV: 5: Familia
    section Ver
      Reproduccion directa sin cortes: 5: Familia, Sistema
      Heimdall sigue en verde: 5: Jeremi
```
*Eje trazabilidad · fase 01 · Gate 0.*

## Trazabilidad

```mermaid
requirementDiagram
    requirement RF02 {
      id: RF02
      text: Reproduccion directa H264 y HEVC
      risk: medium
      verifymethod: test
    }
    requirement RF03 {
      id: RF03
      text: Un transcode a 1x con topes
      risk: high
      verifymethod: test
    }
    requirement RS02 {
      id: RS02
      text: Admin solo desde la LAN
      risk: high
      verifymethod: test
    }
    requirement RS04 {
      id: RS04
      text: Solo el tunel es proxy de confianza
      risk: high
      verifymethod: test
    }
    requirement RS05 {
      id: RS05
      text: Biblioteca solo lectura
      risk: medium
      verifymethod: inspection
    }
    element Jellyfin {
      type: "servicio"
    }
    element Topes {
      type: "control cgroup"
    }
    element NetworkXml {
      type: "configuracion"
    }
    element Compose {
      type: "configuracion"
    }
    element ProbarLimites {
      type: "prueba"
    }
    Jellyfin - satisfies -> RF02
    Topes - satisfies -> RF03
    NetworkXml - satisfies -> RS02
    NetworkXml - satisfies -> RS04
    Compose - satisfies -> RS05
    ProbarLimites - verifies -> RF03
```
*Eje trazabilidad · fase 01 · Gate 0.*

## Threat assessment inicial

```mermaid
flowchart LR
    INET([Internet: familia y atacante]) -->|"HTTPS"| CF([Cloudflare edge])
    CF -->|"QUIC saliente"| TUN
    subgraph MID [Trust boundary: midgard]
      subgraph NET [Red Docker bragi]
        TUN[cloudflared] -->|"HTTP + X-Forwarded-For"| JF[Jellyfin]
      end
      JF --> DB[(SQLite en disco local)]
    end
    LAN([Clientes LAN]) -->|"HTTP 8096"| JF
    JF -->|"NFS solo lectura"| NAS[(NAS biblioteca)]
    JF -.->|"HTTPS saliente"| META([TMDB])
```
*Eje comportamiento · DFD inicial · Gate 0. Tres fronteras: internet↔Cloudflare,
Cloudflare↔midgard (túnel saliente) y midgard↔NAS.*

```mermaid
quadrantChart
    title DREAD inicial — MVP Bragi
    x-axis Baja probabilidad --> Alta probabilidad
    y-axis Bajo impacto --> Alto impacto
    quadrant-1 Atender ya
    quadrant-2 Monitorear
    quadrant-3 Aceptar
    quadrant-4 Planear
    Fuerza bruta al login: [0.75, 0.6]
    Suplantar IP LAN por XFF: [0.45, 0.8]
    Transcode ahoga al router: [0.6, 0.75]
    Suspension por terminos CF: [0.4, 0.7]
    RCE en Jellyfin: [0.2, 0.85]
    Export NFS abierto en LAN: [0.3, 0.5]
    SQLite corrupta por apagon: [0.5, 0.45]
```
*Eje trazabilidad · DREAD · Gate 0. El análisis completo, con STRIDE, está en
[threat-model.md](../02-design/threat-model.md).*
