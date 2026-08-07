#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
printf 'CDMX Radxa Flasher\n'
printf 'macOS asks once for permission to access the removable SD card.\n\n'
exec sudo "$ROOT/CDMX-Radxa-Flasher" "$@"
