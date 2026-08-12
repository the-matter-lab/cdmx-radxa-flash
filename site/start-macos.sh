#!/bin/bash
set -Eeuo pipefail

# The hosted launcher intentionally installs a reviewed, immutable source
# snapshot instead of asking macOS to trust an unsigned application bundle.
SOURCE_COMMIT=3ecbf3467f8fb5f140d89336b798ea17d47abbcd
ARCHIVE_SHA256=65efe3a87175a1aab45e29b9ec2702bffa29de6ff8046b515cf5bc411e4fbee4
ARCHIVE_URL="https://codeload.github.com/the-matter-lab/cdmx-radxa-flash/tar.gz/${SOURCE_COMMIT}"
APP_DIR="${HOME}/Library/Application Support/CDMXRadxaFlash"
SOURCE_DIR="${APP_DIR}/source-${SOURCE_COMMIT}"
LAUNCHER="${SOURCE_DIR}/host/start-imager.command"
PORT=${CDMX_IMAGER_PORT:-8766}
PUBLIC_SITE=https://cdmx-radxaflash.mantilla.ca/
PROCESS_PATTERN='CDMXRadxaFlash/source-[0-9a-f]+/host/imager_app\.py'
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
if [[ $root_status == 302 ]]; then
  /usr/bin/open "$PUBLIC_SITE"
  printf 'El lector ya está abierto.\n'
  exit 0
fi
if /usr/bin/curl --fail --silent "http://127.0.0.1:${PORT}/api/state" >/dev/null 2>&1; then
  printf 'Actualizando el lector anterior…\n'
  sudo /usr/bin/pkill -TERM -f "$PROCESS_PATTERN" || true
  /bin/sleep 1
fi

printf 'Abriendo el lector. macOS pedirá la contraseña de esta Mac una vez.\n'
printf 'La contraseña no se guarda ni se escribe en la Radxa.\n\n'
exec /bin/bash "$LAUNCHER"
