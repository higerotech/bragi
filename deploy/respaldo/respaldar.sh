#!/usr/bin/env bash
# respaldar.sh — respaldo nocturno de la configuracion de Bragi al NAS (T10, ADR-0008).
#
# Que copia: la base SQLite (usuarios, progreso, bibliotecas) y los ficheros de configuracion,
# ~70 MB. Que NO copia: metadata/ (2,7 GB de caratulas e informacion que Jellyfin vuelve a
# descargar), log/ y las copias internas de SQLite.
#
# La base se copia EN CALIENTE con el backup de SQLite, sin parar Jellyfin, y la copia pasa
# `PRAGMA integrity_check` ANTES de archivarse: un respaldo corrupto que nadie comprueba es peor
# que ninguno, porque da una falsa seguridad. midgard no tiene UPS.
#
# Lo lanza bragi-respaldo.timer. A mano:  sudo bash respaldar.sh
set -euo pipefail

DATOS=${BRAGI_DATA:-/var/lib/bragi}/config
DESTINO=${RESPALDO_DESTINO:-/mnt/nas/respaldos/bragi}
RETENER=${RESPALDO_RETENER:-14}
USUARIO=${BRAGI_USUARIO:-bragi}

[ "$(id -u)" = 0 ] || { echo "ejecutar como root"; exit 1; }
command -v sqlite3 >/dev/null || { echo "falta sqlite3"; exit 1; }
[ -f "$DATOS/data/jellyfin.db" ] || { echo "no existe $DATOS/data/jellyfin.db"; exit 1; }

fecha=$(date -u +%Y%m%dT%H%MZ)   # UTC explicito: el host va en UTC y la casa no
nombre="bragi-config-$fecha.tar.gz"
tmp=$(mktemp -d /var/tmp/bragi-respaldo.XXXXXX)   # disco local, no /tmp en RAM
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/config/data"
chown -R "$USUARIO:" "$tmp"

echo "respaldo: copia en caliente de la base"
# Como el usuario de Jellyfin: root crearia ficheros -shm/-wal ajenos junto a la base viva.
runuser -u "$USUARIO" -- sqlite3 "$DATOS/data/jellyfin.db" ".backup $tmp/config/data/jellyfin.db"
integridad=$(runuser -u "$USUARIO" -- sqlite3 "$tmp/config/data/jellyfin.db" "PRAGMA integrity_check;")
[ "$integridad" = ok ] || { echo "respaldo: la copia NO pasa integrity_check: $integridad"; exit 1; }
usuarios=$(runuser -u "$USUARIO" -- sqlite3 "$tmp/config/data/jellyfin.db" "SELECT count(*) FROM Users;")
echo "respaldo: integrity_check ok, $usuarios usuario(s)"

rsync -a \
    --exclude=/metadata --exclude=/log --exclude=/cache \
    --exclude='/data/jellyfin.db*' --exclude=/data/SQLiteBackups --exclude=/data/backups \
    "$DATOS/" "$tmp/config/"
tar -C "$tmp" -czf "$tmp/$nombre" config
( cd "$tmp" && sha256sum "$nombre" > "$nombre.sha256" )

echo "respaldo: subiendo al NAS ($DESTINO)"
ls "$(dirname "$DESTINO")" >/dev/null   # dispara el automount; si el NAS no responde, falla aqui
mkdir -p "$DESTINO"
cp "$tmp/$nombre" "$DESTINO/.$nombre.parcial"
cp "$tmp/$nombre.sha256" "$DESTINO/$nombre.sha256"
mv -f "$DESTINO/.$nombre.parcial" "$DESTINO/$nombre"
( cd "$DESTINO" && sha256sum -c --quiet "$nombre.sha256" ) \
    || { echo "respaldo: la copia en el NAS no coincide con la suma"; exit 1; }

# Retencion: los RETENER mas recientes. Nunca borra si la subida de hoy no esta verificada
# (set -e ya habria salido antes).
mapfile -t viejos < <(ls -1t "$DESTINO"/bragi-config-*.tar.gz | tail -n +"$((RETENER + 1))")
for f in "${viejos[@]}"; do rm -f "$f" "$f.sha256"; done

echo "respaldo: $nombre ($(du -h "$DESTINO/$nombre" | cut -f1)) verificado; ${#viejos[@]} antiguo(s) borrado(s)"

# Estado para Heimdall (ADR-0009): solo se escribe tras un exito VERIFICADO, asi que un fallo
# deja envejecer la marca y dispara BragiRespaldoAtrasado.
ESTADO_DIR=${BRAGI_ESTADO_DIR:-/var/lib/bragi-respaldo}
install -d -m 0755 "$ESTADO_DIR"
echo "$(date +%s) $(stat -c %s "$DESTINO/$nombre")" > "$ESTADO_DIR/.ultimo-exito.tmp"
mv -f "$ESTADO_DIR/.ultimo-exito.tmp" "$ESTADO_DIR/ultimo-exito"
