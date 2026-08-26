#!/usr/bin/env bash
set -Eeuo pipefail

image=${1:?image path required}
source_input=${2:?tracked source archive required}
image_version=${3:?image version required}
source_commit=${4:?source commit required}
base_image_version=${5:?base image version required}
mount_root=/mnt/cdmx-patch
rootfs=$mount_root/rootfs
source_root=/mnt/cdmx-source
root_loop=""

cleanup() {
    set +e
    if [[ -n $root_loop ]]; then
        mountpoint -q "$rootfs" && umount "$rootfs"
        losetup -d "$root_loop" 2>/dev/null || true
    fi
    rm -rf -- "$source_root"
    rmdir "$rootfs" "$mount_root" 2>/dev/null || true
}
trap cleanup EXIT

[[ $image_version =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$ ]] || {
    printf 'Invalid image version: %s\n' "$image_version" >&2
    exit 64
}
[[ $base_image_version =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$ ]] || {
    printf 'Invalid base image version: %s\n' "$base_image_version" >&2
    exit 64
}
[[ $source_commit =~ ^[0-9a-f]{40}$ ]] || {
    printf 'Invalid source commit: %s\n' "$source_commit" >&2
    exit 64
}

export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null
apt-get install -y --no-install-recommends gdisk e2fsprogs util-linux >/dev/null

mkdir -p "$source_root"
tar -xf "$source_input" -C "$source_root"

root_first_sector=$(sgdisk --info=3 "$image" | awk '/First sector:/ {print $3}')
root_last_sector=$(sgdisk --info=3 "$image" | awk '/Last sector:/ {print $3}')
[[ $root_first_sector =~ ^[0-9]+$ && $root_last_sector =~ ^[0-9]+$ ]] || {
    printf 'Could not read the root partition geometry.\n' >&2
    exit 65
}
root_offset=$(( root_first_sector * 512 ))
root_size=$(( (root_last_sector - root_first_sector + 1) * 512 ))
root_loop=$(losetup --find --show --offset "$root_offset" --sizelimit "$root_size" "$image")
e2fsck -fy "$root_loop" >/dev/null

mkdir -p "$rootfs"
mount "$root_loop" "$rootfs"

[[ -d $rootfs/opt/cdmx-radxa-flash && -e $rootfs/etc/cdmx/needs-personalization ]] || {
    printf 'The base image is not an unpersonalized CDMX workshop image.\n' >&2
    exit 65
}
[[ -f $rootfs/usr/lib/python3.11/tkinter/__init__.py ]] || {
    printf 'The base image is missing python3-tk for the reset confirmation dialog.\n' >&2
    exit 69
}

# Replace only the tracked workshop source and installed CDMX runtime files.
# The proven OS, bootloader, packages, agent stack, and instructor key remain
# byte-for-byte from the published base image.
find "$rootfs/opt/cdmx-radxa-flash" -mindepth 1 -delete
tar -C "$source_root" \
    --exclude=.git --exclude=artifacts --exclude=image/cache \
    --exclude='*.img' --exclude='*.img.xz' -cf - . |
    tar -C "$rootfs/opt/cdmx-radxa-flash" -xf -
chown -R root:root "$rootfs/opt/cdmx-radxa-flash"

find "$rootfs/opt/cdmx-radxa-flash/device" "$rootfs/opt/cdmx-radxa-flash/host" \
    -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 \
    "$rootfs/opt/cdmx-radxa-flash/device/network/cdmx-network" \
    "$rootfs/opt/cdmx-radxa-flash/device/network/network_portal.py"

install -m 0755 "$source_root/device/network/cdmx-network" \
    "$rootfs/usr/local/sbin/cdmx-network"
install -m 0755 "$source_root/device/network/network_portal.py" \
    "$rootfs/usr/local/lib/cdmx/network_portal.py"
install -m 0644 "$source_root/device/network/matter-lab-logo.svg" \
    "$rootfs/usr/local/share/cdmx/matter-lab-logo.svg"
install -m 0755 "$source_root/device/network/usb_rescue.sh" \
    "$rootfs/usr/local/lib/cdmx/usb_rescue.sh"
install -m 0755 "$source_root/device/personalize.sh" \
    "$rootfs/usr/local/sbin/cdmx-personalize"
install -m 0755 "$source_root/device/apply-resource-limits.sh" \
    "$rootfs/usr/local/sbin/cdmx-apply-resource-limits"
install -m 0755 "$source_root/device/configure-firewall.sh" \
    "$rootfs/usr/local/sbin/cdmx-configure-firewall"
install -m 0755 "$source_root/device/first-boot.sh" \
    "$rootfs/usr/local/sbin/cdmx-first-boot"

for unit in "$source_root"/device/systemd/*.service "$source_root"/device/systemd/*.timer; do
    [[ -e $unit ]] || continue
    install -m 0644 "$unit" "$rootfs/etc/systemd/system/$(basename "$unit")"
done

# Keep only the runtime executables installed in the proven base. The Local AI
# repository, its skills/tools, legacy service configuration, and participant
# state must be created on demand rather than baked into a freshly flashed SD.
if [[ -L $rootfs/opt/cdmx-local-ai ]]; then
    unlink "$rootfs/opt/cdmx-local-ai"
elif [[ -d $rootfs/opt/cdmx-local-ai ]]; then
    find "$rootfs/opt/cdmx-local-ai" -mindepth 1 -delete
    rmdir "$rootfs/opt/cdmx-local-ai"
elif [[ -e $rootfs/opt/cdmx-local-ai ]]; then
    rm -f -- "$rootfs/opt/cdmx-local-ai"
fi
rm -f -- \
    "$rootfs/usr/local/sbin/cdmx-agent-setup" \
    "$rootfs/etc/systemd/system/cdmx-picoclaw.service" \
    "$rootfs/etc/systemd/system/multi-user.target.wants/cdmx-picoclaw.service"
if [[ -d $rootfs/etc/systemd/system/cdmx-picoclaw.service.d ]]; then
    find "$rootfs/etc/systemd/system/cdmx-picoclaw.service.d" -mindepth 1 -delete
    rmdir "$rootfs/etc/systemd/system/cdmx-picoclaw.service.d"
fi
if [[ -d $rootfs/etc/cdmx-picoclaw ]]; then
    find "$rootfs/etc/cdmx-picoclaw" -mindepth 1 -delete
fi

workshop_workspace=$rootfs/var/lib/cdmx-picoclaw/workspace
[[ -d $workshop_workspace && ! -L $workshop_workspace ]] || {
    printf 'The base image is missing the participant workspace.\n' >&2
    exit 65
}
workshop_uid=$(awk -F: '$1 == "cdmx" { print $3 }' "$rootfs/etc/passwd")
workshop_gid=$(awk -F: '$1 == "cdmx" { print $4 }' "$rootfs/etc/passwd")
workspace_gid=$(awk -F: '$1 == "cdmx-workspace" { print $3 }' "$rootfs/etc/group")
[[ $workshop_uid =~ ^[0-9]+$ && $workshop_gid =~ ^[0-9]+$ && $workspace_gid =~ ^[0-9]+$ ]] || {
    printf 'Could not resolve the workshop workspace ownership.\n' >&2
    exit 65
}

geany_config_dir=$rootfs/home/cdmx/.config/geany
install -d -m 0755 -o "$workshop_uid" -g "$workshop_gid" \
    "$geany_config_dir" "$geany_config_dir/filedefs"
install -m 0644 -o "$workshop_uid" -g "$workshop_gid" \
    "$source_root/device/desktop/geany.conf" \
    "$geany_config_dir/geany.conf"
install -m 0644 -o "$workshop_uid" -g "$workshop_gid" \
    "$source_root/device/desktop/filetypes.python" \
    "$geany_config_dir/filedefs/filetypes.python"

find "$workshop_workspace" -mindepth 1 -delete
install -m 0644 -o "$workshop_uid" -g "$workspace_gid" \
    "$source_root/device/desktop/WORKSHOP-README.txt" \
    "$workshop_workspace/README.md"
install -m 0755 -o "$workshop_uid" -g "$workspace_gid" \
    "$source_root/device/desktop/get-bayesopt-code" \
    "$workshop_workspace/get-bayesopt-code"
install -m 0755 -o "$workshop_uid" -g "$workspace_gid" \
    "$source_root/device/desktop/get-localai-code" \
    "$workshop_workspace/get-localai-code"

for state_dir in "$rootfs/home/cdmx/.picoclaw" "$rootfs/home/cdmx/.pi"; do
    if [[ -d $state_dir && ! -L $state_dir ]]; then
        find "$state_dir" -mindepth 1 -delete
    fi
done
agent_state=$rootfs/var/lib/cdmx-picoclaw
if [[ -d $agent_state ]]; then
    while IFS= read -r -d '' state_entry; do
        if [[ -d $state_entry && ! -L $state_entry ]]; then
            find "$state_entry" -mindepth 1 -delete
            rmdir "$state_entry"
        else
            rm -f -- "$state_entry"
        fi
    done < <(find "$agent_state" -mindepth 1 -maxdepth 1 ! -name workspace -print0)
fi

cat > "$rootfs/etc/cdmx/image-release" <<EOF
IMAGE_VERSION=$image_version
BASE_IMAGE_VERSION=$base_image_version
SOURCE_COMMIT=$source_commit
IDENTITY_RANGE=0-98
ADMIN_NETWORK_INDEX=99
EOF
chmod 0644 "$rootfs/etc/cdmx/image-release"

sync
umount "$rootfs"
e2fsck -fy "$root_loop" >/dev/null
losetup -d "$root_loop"
root_loop=""
