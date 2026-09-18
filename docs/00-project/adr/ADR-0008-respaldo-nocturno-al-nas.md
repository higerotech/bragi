# ADR-0008: Respaldo nocturno de la configuración al NAS

* **Estado:** accepted
* **Fecha:** 2026-09-18
* **Decisores:** Jeremi
* **Fase AI-DLC:** 05-deployment
* **Versión:** 1.0.0
* **ID:** ADR-0008
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A08 (integridad de datos)

## Contexto
La configuración de Bragi (usuarios, progreso de visionado, bibliotecas) vive en una base SQLite
de 62 MB sobre un HDD de 2013, en un appliance **sin UPS** que ha sufrido tres apagones en diez
días. Es T10 del threat model. Además, el rollback del receptor no deshace una migración de
esquema de Jellyfin (ADR-0001): antes de subir de versión hace falta una copia.

## Decisión
Timer de systemd a las 05:30 **hora de la casa**, después de las tareas pesadas de Jellyfin, con
`Persistent=true` para que un apagón no se coma la ventana. El script:
1. copia la base **en caliente** con el backup de SQLite, como el usuario `bragi`;
2. exige `PRAGMA integrity_check = ok` a la copia **antes** de archivarla;
3. empaqueta la base y los ficheros de configuración (~23 MB comprimidos). **Excluye
   `metadata/`**: 2,7 GB que Jellyfin vuelve a descargar;
4. sube el archivo al share `respaldos` del NAS, exportado solo al appliance, con suma sha256
   verificada en destino;
5. conserva los 14 más recientes y solo borra los antiguos si la subida del día se verificó.

## Alternativas consideradas
| Opción | Por qué no |
|---|---|
| Parar Jellyfin y copiar el directorio | Corte nocturno innecesario: el backup de SQLite da una copia consistente en caliente |
| Backup integrado de Jellyfin 10.11 (API) | Necesita una API key guardada en el appliance para un proceso desatendido |
| Copiar también `metadata/` | 115 veces más volumen por algo regenerable |
| Respaldo por *pull* desde el NAS (patrón de Fenrir) | El NAS no tiene acceso al appliance, y abrírselo es más superficie que un export restringido |

## Consecuencias
- **Probado:** simulacro de restauración del 2026-09-18. Con el archivo del NAS, un Jellyfin
  temporal arrancó en ~21 s con el mismo Id de servidor, el asistente completado y 0 errores.
- Tras restaurar, Jellyfin vuelve a descargar las carátulas en el siguiente escaneo.
- **Riesgo aceptado:** un fallo del respaldo solo se ve en `systemctl status bragi-respaldo`.
  Integrarlo en Heimdall es trabajo del Gate 5.
