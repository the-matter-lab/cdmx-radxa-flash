#!/bin/bash
set -Eeuo pipefail

# The hosted launcher intentionally installs a reviewed, immutable source
# snapshot instead of asking macOS to trust an unsigned application bundle.
SOURCE_COMMIT=9ba4ea0a9d18f1f25c36753a9c418b6a9db503a6
ARCHIVE_SHA256=3b15ced6ce1b15591ab158ab791d119c30bce2a756e6fae58a547588789cc98e
ARCHIVE_URL="https://codeload.github.com/the-matter-lab/cdmx-radxa-flash/tar.gz/${SOURCE_COMMIT}"
APP_DIR="${HOME}/Library/Application Support/CDMXRadxaFlash"
SOURCE_DIR="${APP_DIR}/source-${SOURCE_COMMIT}"
LAUNCHER="${SOURCE_DIR}/host/start-imager.command"
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
printf 'Abriendo el lector. macOS pedirá la contraseña de esta Mac una vez.\n'
printf 'La contraseña no se guarda ni se escribe en la Radxa.\n\n'
exec /bin/bash "$LAUNCHER"
