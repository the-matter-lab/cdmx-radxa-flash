#!/bin/bash
set -Eeuo pipefail

SOURCE_COMMIT=ade5f3b540ad4ac4fb6a5b943c98a0f50bdf87b2
ARCHIVE_SHA256=5dd25c9b65589c8460582a09652c64a3641b382bdd9a8322ec8eaf828fd57a9f
ARCHIVE_URL="https://codeload.github.com/the-matter-lab/cdmx-radxa-flash/tar.gz/${SOURCE_COMMIT}"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cdmx-radxa-flash"
SOURCE_DIR="${APP_DIR}/source-${SOURCE_COMMIT}"
LAUNCHER="${SOURCE_DIR}/host/imager_app.py"
VENV="${SOURCE_DIR}/.venv-imager"
PUBLIC_SITE=https://cdmx-radxaflash.mantilla.ca/
PORT=${CDMX_IMAGER_PORT:-8766}
PROCESS_PATTERN='cdmx-radxa-flash/source-[0-9a-f]+/host/imager_app\.py'
CURRENT_PROCESS_PATTERN="cdmx-radxa-flash/source-${SOURCE_COMMIT}/host/imager_app\.py"
WORK_DIR=

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n ${WORK_DIR:-} && -d $WORK_DIR ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}

open_public_site() {
  local browser
  for browser in google-chrome chromium chromium-browser microsoft-edge; do
    if command -v "$browser" >/dev/null 2>&1; then
      "$browser" "$PUBLIC_SITE" >/dev/null 2>&1 &
      return
    fi
  done
  command -v xdg-open >/dev/null 2>&1 && xdg-open "$PUBLIC_SITE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

[[ $(uname -s) == Linux ]] || die 'este comando es solo para Linux'
for command in curl sha256sum tar python3 sudo; do
  command -v "$command" >/dev/null 2>&1 || die "falta ${command}"
done

printf '\nCDMX Radxa Flasher · Matter Lab\n'
printf 'Código fijado: %.12s\n\n' "$SOURCE_COMMIT"

if [[ ! -f $LAUNCHER || ! -f $SOURCE_DIR/.source-verified || $(<"$SOURCE_DIR/.source-verified") != "$ARCHIVE_SHA256" ]]; then
  WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cdmx-radxa-flash.XXXXXX")
  archive="$WORK_DIR/source.tar.gz"
  unpacked="$WORK_DIR/source"
  mkdir -p "$APP_DIR" "$unpacked"

  printf 'Descargando el lector desde GitHub…\n'
  curl --fail --location --retry 3 --show-error --silent "$ARCHIVE_URL" --output "$archive"
  actual_sha256=$(sha256sum "$archive" | awk '{print $1}')
  [[ $actual_sha256 == "$ARCHIVE_SHA256" ]] || die 'la verificación SHA-256 del código fuente falló'
  tar -xzf "$archive" -C "$unpacked" --strip-components=1
  [[ -f $unpacked/host/imager_app.py ]] || die 'el archivo descargado no contiene el lector esperado'

  if [[ -e $SOURCE_DIR ]]; then
    rm -rf -- "$SOURCE_DIR"
  fi
  mv "$unpacked" "$SOURCE_DIR"
  printf '%s\n' "$ARCHIVE_SHA256" > "$SOURCE_DIR/.source-verified"
fi

cleanup
WORK_DIR=
trap - EXIT

if [[ ! -x $VENV/bin/python ]]; then
  python3 -m venv "$VENV" || die 'no se pudo crear el entorno Python; instala python3-venv'
fi
"$VENV/bin/python" -m pip install --disable-pip-version-check -q -r "$SOURCE_DIR/host/requirements.txt"

root_status=$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:${PORT}/" || true)
if [[ $root_status == 302 ]] && pgrep -f "$CURRENT_PROCESS_PATTERN" >/dev/null 2>&1; then
  open_public_site
  printf 'El lector ya está abierto.\n'
  exit 0
fi
if [[ $root_status == 302 ]] || curl --fail --silent "http://127.0.0.1:${PORT}/api/state" >/dev/null 2>&1; then
  printf 'Actualizando el lector anterior…\n'
  sudo pkill -TERM -f "$PROCESS_PATTERN" || true
  sleep 1
fi

(
  for _ in {1..60}; do
    if curl --fail --silent "http://127.0.0.1:${PORT}/api/state" >/dev/null 2>&1; then
      open_public_site
      exit 0
    fi
    sleep 0.5
  done
) &

printf 'Abriendo el lector. Linux pedirá autorización una vez.\n'
printf 'Mantén esta terminal abierta mientras grabas tarjetas.\n\n'
exec sudo "$VENV/bin/python" "$LAUNCHER" --port "$PORT" --no-browser
