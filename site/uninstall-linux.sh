#!/bin/bash
set -Eeuo pipefail

APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cdmx-radxa-flash"
USER_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cdmx-radxa-flash"
ROOT_CACHE=/root/.cache/cdmx-radxa-flash
PROCESS_PATTERN='cdmx-radxa-flash/source-[0-9a-f]+/host/imager_app\.py'

[[ $(uname -s) == Linux ]] || {
  printf 'Error: este comando es solo para Linux.\n' >&2
  exit 1
}

printf '\nDesinstalando CDMX Radxa Flasher…\n'
if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
  sudo pkill -TERM -f "$PROCESS_PATTERN" || true
  sleep 1
fi

sudo rm -rf -- "$ROOT_CACHE"
rm -rf -- "$APP_DIR" "$USER_CACHE"
printf 'Listo. El lector y la imagen en caché fueron eliminados.\n'
printf 'No se modificó ninguna tarjeta SD.\n'
