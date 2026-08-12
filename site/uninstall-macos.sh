#!/bin/bash
set -Eeuo pipefail

APP_DIR="${HOME}/Library/Application Support/CDMXRadxaFlash"
USER_CACHE="${HOME}/Library/Caches/CDMXRadxaFlash"
ROOT_CACHE="/var/root/Library/Caches/CDMXRadxaFlash"
PROCESS_PATTERN='CDMXRadxaFlash/source-[0-9a-f]+/host/imager_app\.py'

[[ $(/usr/bin/uname -s) == Darwin ]] || {
  printf 'Error: este comando es solo para macOS.\n' >&2
  exit 1
}

printf '\nDesinstalando CDMX Radxa Flasher…\n'
if /usr/bin/pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
  sudo /usr/bin/pkill -TERM -f "$PROCESS_PATTERN" || true
  /bin/sleep 1
fi

sudo /bin/rm -rf -- "$ROOT_CACHE"
/bin/rm -rf -- "$APP_DIR" "$USER_CACHE"
printf 'Listo. El lector y la imagen en caché fueron eliminados.\n'
printf 'No se modificó ninguna tarjeta SD.\n'
