#!/bin/sh
set -eu

exec xterm -title 'Pi Agent' -geometry 100x30 \
    -fa Monospace -fs 10 -bg '#0b1020' -fg '#e5e7eb' \
    -e /opt/cdmx-radxa-flash/device/desktop/pi-terminal.sh
