# Clasificación de datos — Bragi

* **Estado:** approved (Gate 0, 2026-09-17)
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 00-project
* **Versión:** 0.1.0

| Dato | Clase | Dónde vive | Protección | Tránsito | Retención |
|---|---|---|---|---|---|
| Contraseñas de las cuentas | **Confidencial** | SQLite de Jellyfin (`/var/lib/bragi/config`), con hash | Directorio del usuario del servicio, fuera del repo | TLS del túnel desde fuera; **HTTP en claro dentro de la LAN** | Mientras exista la cuenta |
| Tokens de sesión / API keys | **Confidencial** | SQLite de Jellyfin | Igual | Cabecera en cada petición | Hasta cerrar sesión o revocar |
| API key de Jellyfin (para `politicas.sh`) | **Confidencial** | Solo en el panel de Jellyfin; se pasa por variable de entorno al ejecutar | No se guarda en ficheros ni en el repo | HTTP en la LAN | Revocar si se filtra |
| `TUNNEL_TOKEN` | **Confidencial** | `deploy/.env` 0600 | Fuera del repo (`.gitignore`) | No viaja: lo usa `cloudflared` | Hasta rotación |
| Historial de visionado, usuarios, dispositivos | **Interno (personal)** | SQLite de Jellyfin | Igual que el resto de la config | Solo por la API autenticada | Indefinida; sin requisito legal |
| Biblioteca de medios | **Interno** | NAS por NFS | Montaje solo lectura en Bragi | Streaming autenticado | Fuera del alcance de Bragi |
| Respaldos de la configuración | **Confidencial** (contienen los hashes de las contraseñas y los tokens de sesión) | Share `respaldos` del NAS | Export NFS solo al appliance | NFS en la LAN | 14 días |
| Metadatos y carátulas descargados | **Público** | `/var/lib/bragi/config/metadata` | — | Salida a TMDB y similares | Regenerable |
| IPs, hostnames y MACs de la instalación | **Interno** | Solo `deploy/.env` y la cabeza del operador | El repo es público: ejemplos RFC 5737 | — | — |

## Reglas
1. Nada de la fila "Confidencial" llega al repositorio. `git ls-files` no lista `.env`.
2. La base SQLite nunca vive en NFS ni dentro del clon.
3. Dentro de la LAN el tráfico va en HTTP. Se acepta porque la LAN es de confianza en este
   diseño, igual que Odín (Grafana) de Yggdrasil. Queda anotado como T8 en el threat model.
