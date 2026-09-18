# bragi-sync — tareas de un solo uso que corren en cada despliegue del receptor de
# despliegue-continuo:
#   sync.sh    (entrypoint por defecto) lleva el clon al commit exacto que se despliega (ADR-0003)
#   config.sh  escribe el network.xml de Jellyfin desde la plantilla horneada aqui (ADR-0006)
# Misma base pineada que yggdrasil-sync.
FROM alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce

# El directorio de la plantilla se crea antes: COPY --chmod aplica el modo tambien al directorio
# que crea, y con 0644 queda sin permiso de paso (config.sh fallaba con Permission denied).
RUN apk upgrade --no-cache \
 && apk add --no-cache bash git ca-certificates \
 && mkdir -p -m 0755 /usr/local/share/bragi

COPY --chmod=0755 sync.sh config.sh /usr/local/bin/
COPY --chmod=0644 network.xml.tmpl /usr/local/share/bragi/network.xml.tmpl

ENV HOME=/tmp
# Sin root por defecto (Trivy DS-0002). El compose fija el usuario real de cada tarea: sync corre
# como el dueño del clon y config como el de Jellyfin.
USER 65534:65534
ENTRYPOINT ["/usr/local/bin/sync.sh"]
