#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/cdmx-network-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/workshop.conf" <<'EOF'
TEAM=0
AP_SSID=equipo0-setup
OPEN_ACCESS=1
EOF

cat >"$tmp/bin/nmcli" <<'EOF'
#!/bin/sh
set -eu
state=${CDMX_TEST_STATE:?}
printf '%s\n' "$*" >>"$state/calls"
case "$*" in
    "general status") exit 0 ;;
    "-t -f NAME connection show --active")
        [ -f "$state/active" ] && cat "$state/active"
        ;;
    "connection show cdmx-venue")
        [ -f "$state/venue-profile" ]
        ;;
    "-t -f DEVICE,TYPE device status")
        printf 'wlan0:wifi\n'
        ;;
    "--wait 1 connection up cdmx-venue")
        [ -f "$state/venue-available" ] || exit 10
        printf 'cdmx-venue\n' >"$state/active"
        ;;
    "--wait 30 connection up cdmx-setup")
        printf 'cdmx-setup\n' >"$state/active"
        ;;
esac
EOF

cat >"$tmp/bin/rfkill" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$tmp/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$tmp/bin/date" <<'EOF'
#!/bin/sh
set -eu
state=${CDMX_TEST_STATE:?}
value=100
[ ! -f "$state/clock" ] || value=$(cat "$state/clock")
printf '%s\n' "$value"
printf '%s\n' "$((value + 61))" >"$state/clock"
EOF
chmod +x "$tmp/bin/"*

run_monitor() {
    CDMX_TEST_STATE=$tmp \
    CDMX_NETWORK_CONFIG=$tmp/workshop.conf \
    CDMX_NETWORK_VENUE_WAIT=1 \
    CDMX_NETWORK_MONITOR_INTERVAL=1 \
    CDMX_NETWORK_FALLBACK_DELAY=60 \
    CDMX_NETWORK_MONITOR_MAX_CYCLES="$1" \
    PATH="$tmp/bin:$PATH" \
        "$ROOT/device/network/cdmx-network" monitor
}

touch "$tmp/venue-profile"
run_monitor 2 >"$tmp/output"
grep -Fxq cdmx-setup "$tmp/active"
grep -Fq 'restoring the setup hotspot' "$tmp/output"
grep -Fq 'connection add type wifi ifname wlan0 con-name cdmx-setup' "$tmp/calls"
printf 'ok - unavailable saved Wi-Fi restores the equipo setup hotspot\n'

: >"$tmp/calls"
printf 'cdmx-venue\n' >"$tmp/active"
run_monitor 1 >"$tmp/output"
if grep -Fq 'connection add type wifi' "$tmp/calls"; then
    printf 'not ok - active venue Wi-Fi unexpectedly started a hotspot\n' >&2
    exit 1
fi
printf 'ok - active venue Wi-Fi remains connected\n'
