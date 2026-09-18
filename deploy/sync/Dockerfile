# bragi-sync — tarea de un solo uso que corre en cada despliegue del receptor de
# despliegue-continuo (ADR-0003): lleva el clon al commit exacto que se despliega (IMAGE_TAG).
# Misma base pineada que yggdrasil-sync.
FROM alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce

RUN apk upgrade --no-cache \
 && apk add --no-cache bash git ca-certificates

COPY --chmod=0755 sync.sh /usr/local/bin/sync.sh

ENV HOME=/tmp
ENTRYPOINT ["/usr/local/bin/sync.sh"]
