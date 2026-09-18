#!/usr/bin/env bash
# Lleva el clon /repo al commit que el receptor esta desplegando (ADR-0003).
#
# IMAGE_TAG llega como sha-<7>. El receptor no hace git pull (su modelo es de imagenes
# inmutables), asi que el fetch lo hace esta tarea contra el repo publico, sin credenciales.
# Mismo patron que yggdrasil-sync.
#
# Rollback: el receptor relanza con el tag anterior y esta tarea vuelve a ese commit.
set -euo pipefail

REMOTO="${BRAGI_REMOTO:-https://github.com/higerotech/bragi.git}"
tag="${IMAGE_TAG:?IMAGE_TAG es obligatorio}"
sha="${tag#sha-}"

log() { echo "sync: $*"; }

cd /repo
git config --global --add safe.directory /repo
if [ ! -d .git ]; then log "clon inicial de $REMOTO"; git clone --quiet "$REMOTO" .; fi
git fetch --quiet origin main
git -c advice.detachedHead=false checkout --quiet --detach "$sha" \
    || { log "commit $sha no esta en origin/main"; exit 1; }
log "checkout $(git rev-parse --short HEAD): $(git log -1 --format=%s)"
