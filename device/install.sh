#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
team=""
skip_upgrade=false
install_agents=true
enable_usb_ncm=false
offline_image=false
workshop_user=cdmx
authorized_key_file=""
# shellcheck source=image/cdmx-local-ai.env
source "$repo_root/image/cdmx-local-ai.env"
agent_repo=$AGENT_REPO_URL
agent_ref=$AGENT_REPO_REF

usage() {
    cat <<'EOF'
Usage: sudo ./device/install.sh --team N [options]

Install the workshop stack on a booted Radxa ZERO 3W running the pinned RadxaOS.
Local workshop services are passwordless. SSH accepts public keys only.

Options:
  --team ID             Initial identity: 0-9 or admin
  --skip-upgrade        Skip apt full-upgrade (package lists are still refreshed)
  --skip-agents         Do not download PicoClaw/Pi now
  --enable-usb-ncm      Enable radxa-ncm if the OTG overlay was already selected
  --offline-image       Prepare a mounted image without starting host services
  --authorized-key-file PATH
                        Install an instructor SSH public key (recommended)
  -h, --help            Show this help
EOF
}

while (($#)); do
    case "$1" in
        --team) team=${2:-}; shift 2 ;;
        --skip-upgrade) skip_upgrade=true; shift ;;
        --skip-agents) install_agents=false; shift ;;
        --enable-usb-ncm) enable_usb_ncm=true; shift ;;
        --offline-image) offline_image=true; shift ;;
        --authorized-key-file) authorized_key_file=${2:-}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    printf 'Run this installer with sudo.\n' >&2
    exit 77
fi
case "$team" in
    0|1|2|3|4|5|6|7|8|9)
        device_hostname="equipo$team"; network_index=$team
        desktop_memory_high=256M; desktop_memory_max=320M
        agent_memory_high=192M; agent_memory_max=256M
        ;;
    admin)
        device_hostname='admin'; network_index=10
        desktop_memory_high=384M; desktop_memory_max=512M
        agent_memory_high=384M; agent_memory_max=512M
        ;;
    *) printf '%s\n' '--team must be 0-9 or admin' >&2; exit 64 ;;
esac

if [[ $(dpkg --print-architecture) != arm64 ]]; then
    printf 'This installer targets RadxaOS arm64; detected %s.\n' "$(dpkg --print-architecture)" >&2
    exit 69
fi

if [[ -n $authorized_key_file ]]; then
    [[ -r $authorized_key_file ]] || { printf 'Cannot read SSH public key: %s\n' "$authorized_key_file" >&2; exit 66; }
    if ! awk '
        NF == 0 { next }
        $1 ~ /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))$/ && NF >= 2 { found=1; next }
        { exit 1 }
        END { if (!found) exit 1 }
    ' "$authorized_key_file"; then
        printf 'The SSH key file must contain one or more public keys.\n' >&2
        exit 65
    fi
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
if ! $skip_upgrade; then
    apt-get -y full-upgrade
fi
apt-get install -y --no-install-recommends \
    avahi-daemon bash build-essential ca-certificates curl feh geany git device-tree-compiler i2c-tools jq kmod locales nano \
    network-manager novnc openbox openssh-server python3 python3-matplotlib \
    python3-numpy python3-pil python3-pip python3-smbus python3-spidev \
    python3-venv rfkill sudo tigervnc-standalone-server \
    tint2 tmux ufw unattended-upgrades websockify x11-xserver-utils xauth xdotool xterm \
    zram-tools

if ! id "$workshop_user" >/dev/null 2>&1; then
    adduser --disabled-password --gecos 'CDMX workshop team' "$workshop_user"
fi
usermod -aG audio,video,render,plugdev,sudo,systemd-journal "$workshop_user"
passwd --lock "$workshop_user" >/dev/null
install -d -m 0755 /etc/sudoers.d
cat > /etc/sudoers.d/90-cdmx-workshop <<EOF
$workshop_user ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/90-cdmx-workshop
visudo -cf /etc/sudoers.d/90-cdmx-workshop >/dev/null
install -d -m 0700 -o "$workshop_user" -g "$workshop_user" "/home/$workshop_user/.ssh"
if [[ -n $authorized_key_file ]]; then
    install -m 0600 -o "$workshop_user" -g "$workshop_user" \
        "$authorized_key_file" "/home/$workshop_user/.ssh/authorized_keys"
else
    rm -f "/home/$workshop_user/.ssh/authorized_keys"
    printf 'WARNING: no instructor SSH public key was installed; SSH login will remain unavailable.\n' >&2
fi

# The color sensor uses a workshop-specific software-I2C mapping because
# physical pins 8/10 default to FIQ/UART2 on the ZERO 3W. The overlay disables
# those consumers and creates i2c-gpio-cdmx (pin 8 SCL, pin 10 SDA). Keep the
# legacy I2C4 overlay disabled so auto-detection cannot select the wrong pins.
legacy_i2c=/boot/dtbo/rk3568-i2c4-m0.dtbo
if [[ -e $legacy_i2c && ! -e $legacy_i2c.disabled ]]; then
    mv -- "$legacy_i2c" "$legacy_i2c.disabled"
fi
install -d -m 0755 /boot/dtbo
dtc -@ -I dts -O dtb \
    -o /boot/dtbo/cdmx-zero3w-i2c-gpio.dtbo \
    "$repo_root/device/overlays/cdmx-zero3w-i2c-gpio.dts"

# RadxaOS 6.1.84-10 deliberately ships CONFIG_I2C_GPIO disabled. Build the
# upstream v6.1.84 driver against the exact installed Radxa headers; never load
# a module compiled for a merely similar kernel ABI.
supported_kernel_release=6.1.84-10-rk2410-nocsf
kernel_config="/boot/config-$supported_kernel_release"
kernel_build="/lib/modules/$supported_kernel_release/build"
if [[ ! -r $kernel_config || ! -d $kernel_build ]]; then
    printf 'Required RadxaOS kernel/header pair %s is not installed.\n' \
        "$supported_kernel_release" >&2
    exit 69
fi
if grep -qx 'CONFIG_I2C_GPIO=y' "$kernel_config"; then
    : # A future rebuild may include the driver in-kernel.
elif grep -qx 'CONFIG_I2C_GPIO=m' "$kernel_config" && \
        modinfo -k "$supported_kernel_release" i2c-gpio >/dev/null 2>&1; then
    : # Or Radxa may begin shipping its own version-matched module.
elif grep -qx '# CONFIG_I2C_GPIO is not set' "$kernel_config"; then
    module_build_dir=$(mktemp -d)
    trap 'rm -rf -- "$module_build_dir"' EXIT
    install -m 0644 "$repo_root/device/modules/i2c-gpio/Makefile" \
        "$repo_root/device/modules/i2c-gpio/i2c-gpio.c" "$module_build_dir/"
    make -s -C "$kernel_build" M="$module_build_dir" modules
    module_vermagic=$(modinfo -F vermagic "$module_build_dir/i2c-gpio.ko")
    case "$module_vermagic" in
        "$supported_kernel_release "*) ;;
        *)
            printf 'Refusing i2c-gpio module with mismatched vermagic: %s\n' \
                "$module_vermagic" >&2
            exit 65
            ;;
    esac
    install -d -m 0755 \
        "/lib/modules/$supported_kernel_release/updates/cdmx"
    install -m 0644 "$module_build_dir/i2c-gpio.ko" \
        "/lib/modules/$supported_kernel_release/updates/cdmx/i2c-gpio.ko"
    depmod -a "$supported_kernel_release"
    rm -rf -- "$module_build_dir"
    trap - EXIT
else
    printf 'Unsupported I2C_GPIO state in %s.\n' "$kernel_config" >&2
    exit 69
fi

# The NeoPixel remains on SPI3-M1 MOSI (physical pin 19). RadxaOS ships the
# SPI3 spidev overlay disabled by filename, so enable it without rsetup.
overlay=rk3568-spi3-m1-cs0-spidev.dtbo
if [[ -e /boot/dtbo/$overlay.disabled && ! -e /boot/dtbo/$overlay ]]; then
    mv -- "/boot/dtbo/$overlay.disabled" "/boot/dtbo/$overlay"
fi
install -d -m 0755 /etc/modules-load.d
cat > /etc/modules-load.d/cdmx-color-lab.conf <<'EOF'
i2c-dev
i2c-gpio
EOF
# Pin 8 is no longer a serial console. Remove both the FIQ console and generic
# earlycon before regenerating extlinux, otherwise firmware/kernel boot may
# still drive the software-I2C clock pin.
if [[ -r /etc/kernel/cmdline ]]; then
    read -r -a kernel_args < /etc/kernel/cmdline
    filtered_kernel_args=()
    for kernel_arg in "${kernel_args[@]}"; do
        case "$kernel_arg" in
            console=ttyFIQ0,*|earlycon|earlycon=*) ;;
            *) filtered_kernel_args+=("$kernel_arg") ;;
        esac
    done
    printf '%s\n' "${filtered_kernel_args[*]}" > /etc/kernel/cmdline
fi
if command -v u-boot-update >/dev/null 2>&1; then
    u-boot-update
fi

# Disable vendor defaults after the dedicated account is known to work.
for vendor_user in radxa rock; do
    if id "$vendor_user" >/dev/null 2>&1; then
        usermod --lock --shell /usr/sbin/nologin "$vendor_user" || true
    fi
done

install -d -m 0755 /etc/cdmx /etc/cdmx-radxa-flash /usr/local/lib/cdmx
getent group cdmx-workspace >/dev/null || groupadd --system cdmx-workspace
usermod -aG cdmx-workspace "$workshop_user"
install -d -m 0750 -o "$workshop_user" -g "$workshop_user" \
    "/home/$workshop_user/.pi" "/home/$workshop_user/.picoclaw"
install -d -m 2770 -o "$workshop_user" -g cdmx-workspace /var/lib/cdmx-picoclaw/workspace
home_workspace="/home/$workshop_user/workspace"
if [[ -d $home_workspace && ! -L $home_workspace ]]; then
    if find "$home_workspace" -mindepth 1 -print -quit | grep -q .; then
        printf 'Refusing to replace non-empty participant workspace: %s\n' "$home_workspace" >&2
        exit 65
    fi
    rmdir "$home_workspace"
fi
if [[ -e $home_workspace && ! -L $home_workspace ]]; then
    printf 'Refusing to replace participant workspace path: %s\n' "$home_workspace" >&2
    exit 65
fi
ln -sfn /var/lib/cdmx-picoclaw/workspace "$home_workspace"
chown -h "$workshop_user:$workshop_user" "$home_workspace"
cat > /etc/cdmx/workshop.conf <<EOF
TEAM=$team
HOSTNAME=$device_hostname
AP_SSID=${device_hostname}-setup
WIFI_COUNTRY=MX
WORKSHOP_USER=$workshop_user
OPEN_ACCESS=1
NETWORK_INDEX=$network_index
EOF
chmod 0644 /etc/cdmx/workshop.conf
rm -f /etc/cdmx/ap-password
install -d -m 0755 /etc/NetworkManager/dnsmasq-shared.d
cat > /etc/NetworkManager/dnsmasq-shared.d/10-cdmx-captive.conf <<EOF
address=/#/10.42.$network_index.1
dhcp-option-force=114,http://10.42.$network_index.1:8080/captive-api
EOF
chmod 0644 /etc/NetworkManager/dnsmasq-shared.d/10-cdmx-captive.conf

if ! $offline_image; then
    hostnamectl set-hostname "$device_hostname"
fi
printf '%s\n' "$device_hostname" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 $device_hostname
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Install a clean flasher/runtime snapshot. Generated images, git metadata, and
# secrets are deliberately not copied onto the device runtime tree.
install -d -m 0755 /opt/cdmx-radxa-flash
if [[ $(readlink -f "$repo_root") != /opt/cdmx-radxa-flash ]]; then
    tar -C "$repo_root" --exclude=.git --exclude=artifacts --exclude='*.img' --exclude='*.img.xz' -cf - . |
        tar -C /opt/cdmx-radxa-flash -xf -
fi
chown -R root:root /opt/cdmx-radxa-flash
find /opt/cdmx-radxa-flash/device /opt/cdmx-radxa-flash/host -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 /opt/cdmx-radxa-flash/device/network/cdmx-network \
    /opt/cdmx-radxa-flash/device/network/network_portal.py

install -m 0755 /opt/cdmx-radxa-flash/device/desktop/fetch-workshop-repos.sh \
    /usr/local/bin/cdmx-get-workshop-repos
ln -sfn cdmx-get-workshop-repos /usr/local/bin/cdmx-get-bayesopt
ln -sfn cdmx-get-workshop-repos /usr/local/bin/cdmx-get-local-ai
install -m 0644 -o "$workshop_user" -g "$workshop_user" \
    /opt/cdmx-radxa-flash/device/desktop/WORKSHOP-README.txt \
    "/home/$workshop_user/WORKSHOP-README.txt"

install -m 0755 /opt/cdmx-radxa-flash/device/network/cdmx-network /usr/local/sbin/cdmx-network
install -m 0755 /opt/cdmx-radxa-flash/device/network/network_portal.py /usr/local/lib/cdmx/network_portal.py
install -d -m 0755 /usr/local/share/cdmx
install -m 0644 /opt/cdmx-radxa-flash/device/network/matter-lab-logo.svg /usr/local/share/cdmx/matter-lab-logo.svg
install -m 0755 /opt/cdmx-radxa-flash/device/network/usb_rescue.sh /usr/local/lib/cdmx/usb_rescue.sh
install -m 0755 /opt/cdmx-radxa-flash/device/personalize.sh /usr/local/sbin/cdmx-personalize
install -m 0755 /opt/cdmx-radxa-flash/device/configure-firewall.sh /usr/local/sbin/cdmx-configure-firewall
install -m 0755 /opt/cdmx-radxa-flash/device/first-boot.sh /usr/local/sbin/cdmx-first-boot

for unit in /opt/cdmx-radxa-flash/device/systemd/*.service /opt/cdmx-radxa-flash/device/systemd/*.timer; do
    [[ -e $unit ]] || continue
    install -m 0644 "$unit" "/etc/systemd/system/$(basename "$unit")"
done

rm -f /etc/cdmx-radxa-flash/vnc.passwd

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/30-cdmx-workshop.conf <<EOF
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AllowUsers $workshop_user
MaxAuthTries 4
X11Forwarding no
EOF

install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/30-cdmx-sd-card.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=32M
RateLimitIntervalSec=30s
RateLimitBurst=1000
EOF
cat > /etc/default/zramswap <<'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/apt/apt.conf.d/52cdmx-unattended <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

if $offline_image; then
    touch /etc/cdmx/needs-runtime-init
else
    /usr/local/sbin/cdmx-configure-firewall
fi

if $install_agents; then
    agent_archive=$(mktemp /tmp/cdmx-local-ai.XXXXXX.tar.gz)
    agent_source=/opt/cdmx-local-ai
    trap 'rm -f -- "${agent_archive:-}"' EXIT
    curl --fail --location --proto '=https' --tlsv1.2 \
        --output "$agent_archive" \
        "$agent_repo/archive/$agent_ref.tar.gz"
    if [[ -L $agent_source ]]; then
        printf 'Refusing to replace symbolic link: %s\n' "$agent_source" >&2
        exit 65
    fi
    if [[ -d $agent_source ]]; then
        find "$agent_source" -mindepth 1 -delete
    else
        install -d -m 0755 "$agent_source"
    fi
    tar -xzf "$agent_archive" --strip-components=1 -C "$agent_source"
    chown -R root:root "$agent_source"
    chmod 0755 "$agent_source/device/agent/install-agent.sh"
    if $offline_image; then
        CDMX_OFFLINE_IMAGE=1 "$agent_source/device/agent/install-agent.sh"
    else
        "$agent_source/device/agent/install-agent.sh"
    fi
    rm -f -- "$agent_archive"
    trap - EXIT
fi

if $enable_usb_ncm; then
    systemctl enable 'radxa-ncm@*.*.service' 2>/dev/null ||
        printf 'radxa-ncm service was not found; use rsetup to enable OTG peripheral mode and NCM.\n' >&2
fi

if ! $offline_image; then
    systemctl daemon-reload
fi
systemctl enable ssh avahi-daemon NetworkManager zramswap \
    cdmx-personalize.service cdmx-first-boot.service cdmx-network.service cdmx-network-portal.service \
    cdmx-network-monitor.service cdmx-usb-rescue.service cdmx-desktop.service cdmx-novnc.service
if [[ -f /etc/systemd/system/cdmx-picoclaw.service ]]; then
    systemctl enable cdmx-picoclaw.service
fi

# Keep one misbehaving graphical app or agent from exhausting a 1 GB team
# board. The admin image has 2 GB and receives proportionally larger ceilings.
install -d -m 0755 /etc/systemd/system/cdmx-desktop.service.d \
    /etc/systemd/system/cdmx-picoclaw.service.d
cat > /etc/systemd/system/cdmx-desktop.service.d/20-memory.conf <<EOF
[Service]
MemoryHigh=$desktop_memory_high
MemoryMax=$desktop_memory_max
TasksMax=192
EOF
cat > /etc/systemd/system/cdmx-picoclaw.service.d/20-memory.conf <<EOF
[Service]
MemoryHigh=$agent_memory_high
MemoryMax=$agent_memory_max
TasksMax=128
EOF
if ! $offline_image; then
    systemctl daemon-reload
fi

chown -R "$workshop_user:$workshop_user" "/home/$workshop_user/.pi" "/home/$workshop_user/.picoclaw"
if ! $offline_image; then
    systemctl restart ssh avahi-daemon
fi

printf '\nInstalled %s. Reboot, join %s-setup, then open http://10.42.%s.1:8080/.\n' "$device_hostname" "$device_hostname" "$network_index"
printf 'The setup Wi-Fi and noVNC have no password; SSH is public-key only.\n'
