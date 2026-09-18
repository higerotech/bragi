# ADR-0004: Acceso externo por Cloudflare Tunnel

* **Estado:** proposed — **pendiente de decisión HITL** (bloquea Gate 1)
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 02-design
* **Versión:** 0.1.0
* **ID:** ADR-0004
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A01 (control de acceso), A05 (configuración), A07 (autenticación)

## Contexto
La familia quiere ver Bragi fuera de casa. midgard no abre puertos en las WAN y ya publica
`deploy.<dominio>` con un Cloudflare Tunnel (contenedor `deploy-service-tunnel`). WireGuard
está referenciado en el firewall pero no instalado.

**Restricción de Cloudflare.** Los *Service-Specific Terms* (actualizados el 2026-06-02),
sección *Content Delivery Network (Free, Pro, or Business)*, dicen:

> "Cloudflare reserves the right to disable or limit your access to or use of the CDN, or to
> limit your End Users' access to certain of your resources through the CDN, if you use or are
> suspected of using the CDN without such Paid Services to serve video or a disproportionate
> percentage of pictures, audio files, or other large files."

Un hostname publicado por un túnel pasa por el proxy (el CDN) de Cloudflare. Servir vídeo así
en un plan gratuito queda dentro de lo que Cloudflare se reserva limitar. El riesgo es
**probable a bajo volumen y seguro a alto**, y su radio es la **zona entera**: si limitan
`higerotech.com`, caen también la landing y el webhook de despliegue.

Fuente: <https://www.cloudflare.com/service-specific-terms-application-services/>
(consultada el 2026-09-17).

## Opciones
| Opción | Pros | Contras | Riesgo |
|---|---|---|---|
| **A. Túnel en una zona o cuenta aparte** (recomendada si se quiere túnel) | Clientes nativos funcionan sin VPN; una suspensión no toca `higerotech.com` | Un dominio más (~10 USD/año); sigue incumpliendo el espíritu de los términos | Medio: la limitación afectaría solo a Bragi |
| B. Túnel en la zona `higerotech.com` | Nada nuevo que comprar | Una suspensión se lleva la landing y el CD | **Alto** |
| C. WireGuard (Bifrost) | Sin terceros en el camino del vídeo; sin login expuesto a internet | Hay que instalarlo; cada dispositivo necesita la app de WireGuard (los TV de fuera, casi nunca) | Bajo |
| D. Solo LAN | Cero superficie | No cumple el objetivo 1 | Ninguno |

## Decisión propuesta
**A**, con estos controles (el compose ya los prepara bajo el perfil `tunel`, apagado):
1. Túnel **propio** de Bragi (`bragi-tunel`), con su token, separado del de despliegue.
2. Jellyfin `network.xml`: `KnownProxies` = IP fija del túnel; `LocalNetworkSubnets` =
   solo la subred LAN, **nunca** la red Docker. Sin esto, todo lo que entra por el túnel
   parece LAN y la restricción del admin no vale nada (AB03).
3. Admin sin acceso remoto (`EnableRemoteAccess=false` en su política); familia con él.
4. Regla de límite de tasa de Cloudflare sobre `/Users/AuthenticateByName` (el plan gratuito
   incluye una).
5. Bloqueo de cuenta por intentos fallidos (`LoginAttemptsBeforeLockout`).

Si Jeremi prefiere no depender de Cloudflare para vídeo, **C** es la alternativa limpia, y
desbloquearía también el udp/51820 y las 6 reglas `wg0` que hoy existen en el firewall sin
servicio detrás.

## Consecuencias
- Pendiente de la decisión. Hasta entonces Bragi funciona solo en la LAN y Gate 1 queda abierto.
