# ADR-0007: Usuario de sistema propio para Jellyfin

* **Estado:** accepted
* **Fecha:** 2026-09-18
* **Decisores:** Jeremi
* **Fase AI-DLC:** 05-deployment
* **Versión:** 1.0.0
* **ID:** ADR-0007
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A01 (mínimo privilegio)

## Contexto
El despliegue manual corría Jellyfin con el uid 1000, que en el appliance es el usuario del
operador: tiene `sudo` sin contraseña y pertenece al grupo `docker`. Un contenedor no hereda
esos privilegios por sí solo, pero cualquier fichero que Jellyfin escriba fuera del contenedor, o
una escapada del contenedor, quedaría a nombre de una cuenta que controla el router entero.

La biblioteca del NAS tiene permisos `777` (comprobado el 2026-09-18), así que no hace falta el
uid del operador para leerla.

## Decisión
`bootstrap-midgard.sh` crea el usuario de sistema `bragi`: sin shell, sin home propio y con los
grupos `render` y `video` para `/dev/dri`. `PUID`/`PGID` del `.env` son los suyos y
`/var/lib/bragi` le pertenece con modo `0750`.

## Alternativas consideradas
| Opción | Por qué no |
|---|---|
| Seguir con el uid del operador | Cualquier compromiso queda a nombre de una cuenta con `sudo` sin contraseña |
| Docker user namespaces (`userns-remap`) | Es un cambio de todo el demonio y afectaría a Yggdrasil y al resto de stacks del appliance |

## Consecuencias
- La migración desde el despliegue manual hace `chown -R bragi` sobre la copia (el origen queda
  intacto).
- Si el NAS endureciera algún día sus permisos, `bragi` necesitaría lectura explícita sobre la
  biblioteca.
