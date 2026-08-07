#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PORT=${CDMX_IMAGER_PORT:-8766}
VENV="$ROOT/.venv-imager"

printf 'CDMX Radxa Flasher\n'
printf 'Dependencies install locally; macOS asks once for removable-disk access.\n'
printf 'No password is stored or written to a Radxa.\n\n'

if [[ ! -x $VENV/bin/python ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --disable-pip-version-check -q -r "$ROOT/host/requirements.txt"

(
  for _ in {1..60}; do
    if curl --fail --silent "http://127.0.0.1:${PORT}/api/state" >/dev/null 2>&1; then
      open "http://127.0.0.1:${PORT}/"
      exit 0
    fi
    sleep 0.5
  done
) &

exec sudo "$VENV/bin/python" "$ROOT/host/imager_app.py" --port "$PORT" --no-browser
