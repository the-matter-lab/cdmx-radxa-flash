#!/bin/bash
set -Eeuo pipefail

# The hosted launcher intentionally installs a reviewed, immutable source
# snapshot instead of asking macOS to trust an unsigned application bundle.
SOURCE_COMMIT=0380f57a9550c8e3e7895425096aa934a507c901
ARCHIVE_SHA256=b9778ffee98013789204e3793abbd9b3695a1626f364815d3623cf88d5e877b2
ARCHIVE_URL="https://codeload.github.com/the-matter-lab/cdmx-radxa-flash/tar.gz/${SOURCE_COMMIT}"
APP_DIR="${HOME}/Library/Application Support/CDMXRadxaFlash"
SOURCE_DIR="${APP_DIR}/source-${SOURCE_COMMIT}"
LAUNCHER="${SOURCE_DIR}/host/start-imager.command"
PORT=${CDMX_IMAGER_PORT:-8766}
PUBLIC_SITE=https://cdmx-radxaflash.mantilla.ca/
PROCESS_PATTERN='CDMXRadxaFlash/source-[0-9a-f]+/host/imager_app\.py'
CURRENT_PROCESS_PATTERN="CDMXRadxaFlash/source-${SOURCE_COMMIT}/host/imager_app\.py"
WORK_DIR=

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n ${WORK_DIR:-} && -d $WORK_DIR ]]; then
    /bin/rm -rf -- "$WORK_DIR"
  fi
}

open_public_site() {
  local app
  for app in "Google Chrome" Chromium "Microsoft Edge"; do
    if /usr/bin/open -Ra "$app" >/dev/null 2>&1; then
      /usr/bin/open -a "$app" "$PUBLIC_SITE"
      return
    fi
  done
  printf 'Chrome, Chromium, o Edge es necesario para conectar la web con el lector.\n' >&2
  /usr/bin/open "$PUBLIC_SITE"
}
trap cleanup EXIT

[[ $(/usr/bin/uname -s) == Darwin ]] || die 'este comando es solo para macOS'
for command in /usr/bin/curl /usr/bin/shasum /usr/bin/tar /usr/bin/python3; do
  [[ -x $command ]] || die "falta ${command}; actualiza macOS o instala las herramientas de línea de comandos"
done

printf '\nCDMX Radxa Flasher · Matter Lab\n'
printf 'Código fijado: %.12s\n\n' "$SOURCE_COMMIT"

if [[ ! -x $LAUNCHER || ! -f $SOURCE_DIR/.source-verified || $(<"$SOURCE_DIR/.source-verified") != "$ARCHIVE_SHA256" ]]; then
  WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cdmx-radxa-flash.XXXXXX")
  archive="$WORK_DIR/source.tar.gz"
  unpacked="$WORK_DIR/source"
  /bin/mkdir -p "$APP_DIR" "$unpacked"

  printf 'Descargando el lector desde GitHub…\n'
  /usr/bin/curl --fail --location --retry 3 --show-error --silent "$ARCHIVE_URL" --output "$archive"
  actual_sha256=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
  [[ $actual_sha256 == "$ARCHIVE_SHA256" ]] || die 'la verificación SHA-256 del código fuente falló'

  /usr/bin/tar -xzf "$archive" -C "$unpacked" --strip-components=1
  [[ -x $unpacked/host/start-imager.command ]] || die 'el archivo descargado no contiene el lector esperado'

  if [[ -e $SOURCE_DIR ]]; then
    /bin/rm -rf -- "$SOURCE_DIR"
  fi
  /bin/mv "$unpacked" "$SOURCE_DIR"
  printf '%s\n' "$ARCHIVE_SHA256" > "$SOURCE_DIR/.source-verified"
fi

cleanup
WORK_DIR=
trap - EXIT

root_status=$(/usr/bin/curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:${PORT}/" || true)
if [[ $root_status == 302 ]] && /usr/bin/pgrep -f "$CURRENT_PROCESS_PATTERN" >/dev/null 2>&1; then
  open_public_site
  printf 'El lector ya está abierto.\n'
  exit 0
fi
if [[ $root_status == 302 ]] || /usr/bin/curl --fail --silent "http://127.0.0.1:${PORT}/api/state" >/dev/null 2>&1; then
  printf 'Actualizando el lector anterior…\n'
  sudo /usr/bin/pkill -TERM -f "$PROCESS_PATTERN" || true
  /bin/sleep 1
fi

printf 'Abriendo el lector. macOS pedirá la contraseña de esta Mac una vez.\n'
printf 'La contraseña no se guarda ni se escribe en la Radxa.\n\n'
exec /bin/bash "$LAUNCHER"
