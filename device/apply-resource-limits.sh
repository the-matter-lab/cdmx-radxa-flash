#!/usr/bin/env bash
set -euo pipefail

team=${1:-}
root=${CDMX_ROOT:-}

case "$root" in
    ""|/*) ;;
    *) printf 'CDMX_ROOT must be an absolute path.\n' >&2; exit 64 ;;
esac
if [[ -z $root && $EUID -ne 0 ]]; then
    printf 'cdmx-apply-resource-limits must run as root.\n' >&2
    exit 77
fi

case "$team" in
    0|1|2|3|4|5|6|7|8|9|10|11)
        desktop_memory_high=256M
        desktop_memory_max=320M
        agent_memory_high=192M
        agent_memory_max=256M
        ;;
    admin)
        desktop_memory_high=384M
        desktop_memory_max=512M
        agent_memory_high=384M
        agent_memory_max=512M
        ;;
    *) printf 'Team must be 0-11 or admin.\n' >&2; exit 64 ;;
esac

desktop_dropin="$root/etc/systemd/system/cdmx-desktop.service.d/20-memory.conf"
agent_dropin="$root/etc/systemd/system/cdmx-picoclaw.service.d/20-memory.conf"
install -d -m 0755 "$(dirname "$desktop_dropin")" "$(dirname "$agent_dropin")"
cat > "$desktop_dropin" <<EOF
[Service]
MemoryHigh=$desktop_memory_high
MemoryMax=$desktop_memory_max
TasksMax=192
EOF
cat > "$agent_dropin" <<EOF
[Service]
MemoryHigh=$agent_memory_high
MemoryMax=$agent_memory_max
TasksMax=128
EOF
chmod 0644 "$desktop_dropin" "$agent_dropin"

if [[ -z $root && ${CDMX_OFFLINE_IMAGE:-0} != 1 && -d /run/systemd/system ]]; then
    systemctl daemon-reload
fi
