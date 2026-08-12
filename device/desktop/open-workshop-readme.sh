#!/bin/sh
set -eu

README_PATH=/home/cdmx/WORKSHOP-README.txt
if command -v less >/dev/null 2>&1; then
    exec xterm -title 'Workshop Instructions' -geometry 110x34 \
        -fa Monospace -fs 10 -bg '#000000' -fg '#e5e7eb' \
        -e less "$README_PATH"
fi
exec xterm -title 'Workshop Instructions' -geometry 110x34 \
    -fa Monospace -fs 10 -bg '#000000' -fg '#e5e7eb' \
    -e nano --view "$README_PATH"
