# Glosario — lenguaje ubicuo de Bragi

* **Estado:** approved (Gate 0, 2026-09-17)
* **Fecha:** 2026-09-17
* **Decisores:** Jeremi
* **Fase AI-DLC:** 00-project
* **Versión:** 0.1.0

| Término | Definición |
|---|---|
| **Bragi** | El servicio completo: Jellyfin con sus topes, su tarea sync y su túnel. |
| **midgard** | El appliance de red de la casa (router con dos WAN) donde corre Bragi. |
| **Biblioteca** | El árbol de películas y series del NAS, montado en `/media` solo lectura. |
| **Reproducción directa** (direct play) | El cliente decodifica el fichero tal cual; el servidor solo lo lee y lo envía. CPU ≈ 0. |
| **Direct stream** | Se cambia el contenedor (remux) sin recodificar vídeo. CPU baja. |
| **Transcode** | Recodificar el vídeo para un cliente que no lo soporta o por límite de bitrate. Caro: uno como máximo. |
| **Tope** | Límite de cgroup del contenedor (`cpus`, `mem_limit`, `cpu_shares`). |
| **Speed** | Velocidad de un transcode respecto al tiempo real; ≥ 1,0x es fluido. |
| **Cuenta admin** | La cuenta de Jeremi con privilegios de administración; solo desde la LAN. |
| **Cuenta familiar** | Cuenta sin privilegios, con acceso remoto permitido. |
| **Túnel** | Conexión saliente de `cloudflared` que publica Bragi en un subdominio sin abrir puertos. |
| **Proxy de confianza** (KnownProxies) | La única IP de la que Jellyfin acepta `X-Forwarded-For`: la del contenedor del túnel. |
| **Receptor** | `cd-receiver` de `higerotech/despliegue-continuo`: despliega al recibir el `workflow_run` firmado. |
| **Sync** | Tarea de un solo uso que lleva el clon al commit que se despliega. |
| **Heimdall** | El monitor de SLA de las WAN (Yggdrasil); es el testigo de que Bragi no degrada la red. |
