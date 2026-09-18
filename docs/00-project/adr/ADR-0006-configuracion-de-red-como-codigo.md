# ADR-0006: Configuración de red y políticas de Jellyfin como código

* **Estado:** accepted
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 03-implementation
* **Versión:** 1.0.0
* **ID:** ADR-0006
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A01 (control de acceso), A05 (configuración)

## Contexto
Toda la frontera de confianza del acceso externo (RS02, RS04) depende de dos líneas de
`network.xml` y de una política por cuenta:

- `LocalNetworkSubnets` vacío hace que Jellyfin derive la LAN de sus interfaces. La red Docker de
  Bragi contaría como local, y todo lo que entra por el túnel parecería LAN.
- Sin `KnownProxies`, el `X-Forwarded-For` del túnel se ignora. Todo el tráfico remoto tendría la
  IP del contenedor `cloudflared`, y la restricción del admin compararía contra esa IP.
- `EnableRemoteAccess=false` del admin vive en la base SQLite, no en un fichero.

Si cualquiera de las tres se cambia desde el panel, no queda rastro y nada lo detecta.

## Decisión
1. **`network.xml` lo escribe el despliegue.** La plantilla (`deploy/sync/network.xml.tmpl`) se
   hornea en la imagen `bragi-sync`. La tarea `config` corre como el usuario de Jellyfin y sin
   red, valida `LAN_SUBNET` y `TUNEL_IP` y escribe el fichero de forma atómica. Jellyfin se
   recrea en cada despliegue (`BRAGI_REV=${IMAGE_TAG}`) porque solo lee `network.xml` al
   arrancar.
2. **Las políticas de cuenta las aplica y verifica `deploy/scripts/politicas.sh`** por la API.
   `--verificar` detecta la deriva y sale con 1.
3. **Ambas cosas las prueba el CI contra un Jellyfin real** (`deploy/tests/prueba-proxy.sh`).
   Levanta la misma imagen, genera el `network.xml` con el mismo `config.sh` y ataca la frontera
   desde tres posiciones: LAN, proxy de confianza y otro contenedor.

**Consecuencia buscada:** un cambio del panel de Red se pierde en el siguiente despliegue. La
configuración de red se cambia por PR.

## Alternativas consideradas
| Opción | Por qué no |
|---|---|
| Configurar a mano desde el panel | Sin rastro ni detección de deriva; es justo lo que falló a otros con Jellyfin tras proxy |
| Montar `network.xml` del clon en solo lectura | El clon es `750 deploy:deploy` y el PUID no lo lee; además, un bind de un fichero sigue al inodo y `git checkout` lo sustituye (lección de Yggdrasil 0.4.1) |
| Plantilla leída del clon por la tarea `config` | Mismo problema de permisos; hornearla en la imagen la mantiene versionada por commit igualmente |

## Consecuencias
- Positivas: la frontera de confianza se revisa en PR y se prueba en cada PR.
- Negativas: cada despliegue reinicia Jellyfin y corta las reproducciones en curso. Se acepta
  porque se despliega poco y a mano (PR a `main`).
- La prueba de integración destapó dos hallazgos, H1 y H2, descritos en el threat model.
