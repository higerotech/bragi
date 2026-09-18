#!/usr/bin/env bash
# Escribe el network.xml de Jellyfin a partir de la plantilla horneada en la imagen (ADR-0006).
#
# Corre como el usuario de Jellyfin (PUID) y sin red. La plantilla va DENTRO de la imagen y no
# se lee del clon a proposito: el clon es 750 deploy:deploy y el PUID no puede leerlo. Como la
# imagen se construye por commit, la plantilla sigue versionada con el resto.
#
# Valida los dos valores antes de escribir: un network.xml con una subred mal formada hace que
# Jellyfin la ignore EN SILENCIO y vuelva a derivar la LAN de sus interfaces, que es justo el
# fallo que este fichero existe para evitar.
set -euo pipefail

PLANTILLA=/usr/local/share/bragi/network.xml.tmpl
DESTINO_DIR=/salida/config
DESTINO="$DESTINO_DIR/network.xml"

lan="${LAN_SUBNET:?LAN_SUBNET es obligatorio (p. ej. 192.0.2.0/24)}"
tunel="${TUNEL_IP:?TUNEL_IP es obligatorio}"

octeto='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
ipv4="^${octeto}(\.${octeto}){3}$"

[[ "${lan%/*}" =~ $ipv4 ]] && [[ "$lan" == */* ]] && [[ "${lan#*/}" =~ ^([0-9]|[12][0-9]|3[0-2])$ ]] \
    || { echo "config: LAN_SUBNET no es una subred IPv4 valida: '$lan'" >&2; exit 1; }
[[ "$tunel" =~ $ipv4 ]] \
    || { echo "config: TUNEL_IP no es una IPv4 valida: '$tunel'" >&2; exit 1; }

mkdir -p "$DESTINO_DIR"
tmp="$(mktemp "$DESTINO_DIR/.network.xml.XXXXXX")"
sed -e "s|@@LAN_SUBNET@@|$lan|" -e "s|@@TUNEL_IP@@|$tunel|" "$PLANTILLA" > "$tmp"
if grep -q '@@' "$tmp"; then
    rm -f "$tmp"
    echo "config: quedan marcadores sin sustituir" >&2
    exit 1
fi
chmod 0644 "$tmp"
mv -f "$tmp" "$DESTINO"
echo "config: network.xml escrito (LAN $lan, proxy de confianza $tunel)"
