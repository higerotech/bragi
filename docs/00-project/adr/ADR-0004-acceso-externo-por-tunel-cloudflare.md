# ADR-0004: Acceso externo por Cloudflare Tunnel

* **Estado:** accepted (HITL 2026-09-17, opción A)
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 02-design
* **Versión:** 1.1.0
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

## Decisión (HITL 2026-09-17)
**Opción A.** Jeremi aporta un dominio propio que ya tenía registrado en Cloudflare, distinto
del de la organización. El hostname público de Bragi vive en esa zona y no en `higerotech.com`.
Por anonimización, el dominio real solo aparece en `deploy/.env` (`PUBLISHED_URL`) y en el panel
de Cloudflare; aquí se escribe `media.example.com`.

Comprobado el mismo día: la zona usa **el mismo par de nameservers** que `higerotech.com`, y
Cloudflare asigna ese par por cuenta. Es decir, **zona aparte dentro de la misma cuenta**.

**Riesgo residual aceptado.** Los términos hablan de limitar "your access to or use of the CDN",
y la redacción no aclara si el alcance es la zona o la cuenta. En la práctica las limitaciones por
este motivo se aplican al hostname o a la zona que sirve el vídeo, así que la landing y el webhook
de despliegue quedan fuera del radio probable, pero **no garantizado**. La zona elegida también
tiene su propio contenido (web y Email Routing), que sí queda dentro del radio.

**Condición de revisión.** Si Cloudflare avisa o limita, o si el tráfico remoto crece (más de
un par de horas diarias de vídeo), mover la zona a una **cuenta de Cloudflare propia**, que es
gratuita, o pasar a WireGuard (opción C).

**Controles obligatorios antes de activar el perfil `tunel`** (verificación en Gate 3):
1. Túnel propio `bragi-tunel`, token solo en `deploy/.env`.
2. `network.xml`: `KnownProxies` = IP fija del túnel; `LocalNetworkSubnets` = solo la LAN.
3. Admin con `EnableRemoteAccess=false`.
4. Regla de límite de tasa en la zona sobre `/Users/AuthenticateByName`.
5. `LoginAttemptsBeforeLockout` en todas las cuentas.

## Verificación (2026-09-18)
Túnel activo en producción. Desde internet: TLS válido, Jellyfin registra la IP pública real, el
admin no entra desde fuera y la regla de límite de tasa bloquea las ráfagas contra el login (429).
El límite del plan gratuito es aproximado: deja pasar la primera ráfaga casi entera antes de
bloquear. El bloqueo por intentos de Jellyfin no funciona en 10.11.11 (H1), así que frente a T1
quedan el límite de tasa y la longitud de la clave. **Ninguna cuenta con acceso remoto puede
tener menos de 12 caracteres.**

## Consecuencias
- Positivas: los clientes nativos de TV y móvil funcionan fuera de casa sin VPN; una suspensión
  probable no toca `higerotech.com`.
- Negativas: el login de Jellyfin queda expuesto a internet (T1, mitigado por los controles 3–5);
  el riesgo T9 baja de "atender ya" a "monitorear", pero no desaparece mientras compartan cuenta.
