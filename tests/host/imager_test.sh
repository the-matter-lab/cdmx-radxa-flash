#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../../host/lib/imager.sh
source "$ROOT/host/lib/imager.sh"

failures=0
assert_eq() {
  local expected=$1 actual=$2 label=$3
  if [[ "$expected" != "$actual" ]]; then
    printf 'not ok - %s (expected %q, got %q)\n' "$label" "$expected" "$actual"
    failures=$((failures + 1))
  else
    printf 'ok - %s\n' "$label"
  fi
}

assert_fails() {
  local label=$1
  shift
  if ("$@") >/dev/null 2>&1; then
    printf 'not ok - %s (unexpected success)\n' "$label"
    failures=$((failures + 1))
  else
    printf 'ok - %s\n' "$label"
  fi
}

assert_eq 0 "$(validate_team 0; printf 0)" 'team 0 is valid'
assert_eq 9 "$(validate_team 9; printf 9)" 'team 9 is valid'
assert_eq admin "$(validate_team admin; printf admin)" 'admin identity is valid'
assert_fails 'team 10 is rejected' validate_team 10
assert_fails 'negative team is rejected' validate_team -1
assert_fails 'non-numeric team is rejected' validate_team one
if [[ $(host_os) == macos ]]; then
  assert_eq /dev/rdisk42 "$(raw_disk /dev/disk42)" 'macOS raw-disk path has no escapes'
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cdmx-test.XXXXXX")
write_team_config "$tmp" 7
assert_eq CDMX_TEAM=7 "$(grep '^CDMX_TEAM=' "$tmp/cdmx-team.env")" 'team marker contains number'
assert_eq CDMX_HOSTNAME=equipo7 "$(grep '^CDMX_HOSTNAME=' "$tmp/cdmx-team.env")" 'team marker contains hostname'
write_team_config "$tmp" admin
assert_eq CDMX_TEAM=admin "$(grep '^CDMX_TEAM=' "$tmp/cdmx-team.env")" 'admin marker contains identity'
assert_eq CDMX_HOSTNAME=admin "$(grep '^CDMX_HOSTNAME=' "$tmp/cdmx-team.env")" 'admin marker contains hostname'
if grep -Eqi '(password|psk|ssid|api[_-]?key)=' "$tmp/cdmx-team.env" "$tmp/before.txt"; then
  printf 'not ok - generated config appears to contain a credential\n'
  failures=$((failures + 1))
else
  printf 'ok - generated config contains no credential assignment\n'
fi
if grep -Eq '^[[:space:]]*(enable_service|disable_service|regenerate_ssh_hostkey)([[:space:]]|$)' "$tmp/before.txt"; then
  printf 'not ok - before.txt can deadlock first boot by managing ordered services\n'
  failures=$((failures + 1))
else
  printf 'ok - before.txt leaves ordered services to systemd\n'
fi

assert_eq 6f9f67df6f997bef41aac2cc568ebb4b7820216be1256a49ce472cb877684c08ad793ff726da3155a02f0eab60b2b2c9318168b3cf8fab81849ae91e8724f10d "$(bash -c 'source "$1"; printf %s "$IMAGE_SHA512"' _ "$ROOT/image/radxa-zero3-bookworm-kde-rsdk-b1.env")" 'stock image pin is unchanged'

if grep -Eq 'CDMX_WORKSHOP_PASSWORD|PasswordAuthentication yes|guest ok = no|SecurityTypes VncAuth' \
    "$ROOT/device/install.sh" "$ROOT/device/systemd/cdmx-desktop.service"; then
  printf 'not ok - workshop image still requires a shared local password\n'
  failures=$((failures + 1))
else
  printf 'ok - workshop services do not require a shared local password\n'
fi
assert_eq OPEN_ACCESS=1 "$(grep '^OPEN_ACCESS=' "$ROOT/device/personalize.sh")" 'clones keep the passwordless setup AP'
assert_eq RuntimeDirectory=cdmx "$(grep '^RuntimeDirectory=' "$ROOT/device/systemd/cdmx-network-portal.service")" 'portal runtime directory exists before sandboxing'
assert_eq 1 "$(grep -c 'cdmx-network-monitor.service' "$ROOT/device/install.sh")" \
  'image enables the runtime Wi-Fi recovery monitor'
assert_eq "fallback_delay=\${CDMX_NETWORK_FALLBACK_DELAY:-60}" \
  "$(grep '^fallback_delay=' "$ROOT/device/network/cdmx-network")" \
  'offline boards restore onboarding after a bounded delay'
assert_eq f10ff6c5b0d8d306f8117091bb3760f6662f097c \
  "$(bash -c 'source "$1"; printf %s "$AGENT_REPO_REF"' _ "$ROOT/image/cdmx-local-ai.env")" \
  'image build pins the separate local-agent repository commit'
if [[ -d $ROOT/device/agent ]]; then
  printf 'not ok - agent implementation is duplicated in the flasher repository\n'
  failures=$((failures + 1))
else
  printf 'ok - agent implementation is owned only by cdmx-local-ai\n'
fi
assert_eq 1 "$(grep -c 'agent_repo/archive/\$agent_ref.tar.gz' "$ROOT/device/install.sh")" \
  'image installer fetches the pinned agent package'
assert_eq 'git -C "$ROOT" archive --format=tar HEAD > "$source_archive_partial"' \
  "$(grep '^git -C \"\$ROOT\" archive --format=tar HEAD > \"\$source_archive_partial\"$' "$ROOT/host/build-workshop-image.sh")" \
  'image builds use an immutable tracked-source snapshot'
assert_eq 'output_raw=$(mktemp "$ROOT/image/cache/cdmx-workshop-golden.XXXXXX.img")' \
  "$(grep '^output_raw=$(mktemp ' "$ROOT/host/build-workshop-image.sh")" \
  'each image build uses an isolated raw working file'
assert_eq '    "/images/$(basename "$output_raw")" /source.tar /instructor.pub' \
  "$(grep -F '    "/images/$(basename "$output_raw")" /source.tar /instructor.pub' "$ROOT/host/build-workshop-image.sh")" \
  'container receives the isolated raw image path'
assert_eq 2 "$(grep -c '<menu>root-menu</menu>' "$ROOT/device/desktop/openbox.xml")" \
  'desktop launcher is available from the keyboard and right-click'
assert_eq 3 "$(sed -n 's:.*<number>\([0-9][0-9]*\)</number>.*:\1:p' "$ROOT/device/desktop/openbox.xml")" \
  'desktop provides WORK, AGENT, and RUN workspaces'
assert_eq 1 "$(grep -c '<mousebind button="Left" action="Drag"><action name="Move"/></mousebind>' "$ROOT/device/desktop/openbox.xml")" \
  'window title bars can be dragged normally'
assert_eq 1 "$(grep -c '<keybind key="A-Tab">' "$ROOT/device/desktop/openbox.xml")" \
  'Alt-Tab switches between open applications'
assert_eq 1 "$(grep -c '<keybind key="C-A-t">' "$ROOT/device/desktop/openbox.xml")" \
  'desktop has a new-terminal shortcut'
assert_eq 1 "$(grep -c 'Code Editor — Geany' "$ROOT/device/desktop/menu.xml")" \
  'desktop menu includes a graphical code editor'
assert_eq 1 "$(grep -c 'Download/update workshop code' "$ROOT/device/desktop/menu.xml")" \
  'desktop menu includes the one-click repository downloader'
assert_eq 2 "$(grep -c '^ *update_repo cdmx-' "$ROOT/device/desktop/fetch-workshop-repos.sh")" \
  'repository downloader includes both workshop repositories'
assert_eq 2 "$(grep -c 'https://github.com/the-matter-lab/cdmx-' "$ROOT/device/desktop/fetch-workshop-repos.sh")" \
  'SD-card downloader uses the Matter Lab organization'
old_org=aspuru-guzik'-group'
if grep -Rqs --exclude-dir=.git --exclude-dir=image "$old_org" "$ROOT"; then
  printf 'not ok - old workshop GitHub organization remains in tracked source\n'
  failures=$((failures + 1))
else
  printf 'ok - tracked source contains no old workshop GitHub organization\n'
fi
assert_eq '1280 x 720' "$(file "$ROOT/device/desktop/matter-lab-workshop-wallpaper.png" | sed -n 's/.*PNG image data, \([0-9][0-9]* x [0-9][0-9]*\),.*/\1/p')" \
  'Matter Lab wallpaper has the noVNC desktop dimensions'
assert_eq 1 "$(grep -c 'Matter Lab International Conference 2026 ∙ Satellite School' "$ROOT/device/desktop/matter-lab-workshop-wallpaper.svg")" \
  'wallpaper carries the conference title'
assert_eq 1 "$(grep -c 'text-anchor="end"' "$ROOT/device/desktop/matter-lab-workshop-wallpaper.svg")" \
  'wallpaper conference title is right aligned'
if ! grep -Eq 'curl feh geany git' "$ROOT/device/install.sh" || ! grep -Eq '^[[:space:]]*tint2 tmux ' "$ROOT/device/install.sh"; then
  printf 'not ok - graphical editor or desktop task bar is missing from the workshop image\n'
  failures=$((failures + 1))
else
  printf 'ok - graphical editor and desktop task bar are guaranteed in the workshop image\n'
fi
if grep -Rq 'cdmx-demo\|show-demo.sh\|Bayesian Optimization' \
    "$ROOT/device/desktop" "$ROOT/device/systemd" "$ROOT/device/install.sh"; then
  printf 'not ok - the default desktop still starts the BayesOpt animation\n'
  failures=$((failures + 1))
else
  printf 'ok - the default desktop does not start the BayesOpt animation\n'
fi
assert_eq '$workshop_user ALL=(ALL:ALL) NOPASSWD: ALL' \
  "$(grep '^\$workshop_user ALL=(ALL:ALL) NOPASSWD: ALL$' "$ROOT/device/install.sh")" \
  'workshop user can install tools without a nonexistent password'
assert_eq 1 "$(grep -c '^overlay=rk3568-spi3-m1-cs0-spidev.dtbo$' "$ROOT/device/install.sh")" \
  'NeoPixel SPI3 overlay is enabled in the image'
assert_eq 1 "$(grep -c 'cdmx-zero3w-i2c-gpio.dtbo' "$ROOT/device/install.sh")" \
  'custom color-sensor I2C overlay is compiled into the image'
assert_eq 1 "$(grep -c '^legacy_i2c=/boot/dtbo/rk3568-i2c4-m0.dtbo$' "$ROOT/device/install.sh")" \
  'legacy I2C4 mapping is explicitly disabled'
assert_eq 1 "$(grep -c 'i2c-gpio-cdmx {' "$ROOT/device/overlays/cdmx-zero3w-i2c-gpio.dts")" \
  'software I2C adapter has a stable discoverable name'
assert_eq 1 "$(grep -c 'sda-gpios = <&gpio0 24 6>;' "$ROOT/device/overlays/cdmx-zero3w-i2c-gpio.dts")" \
  'physical pin 10 is open-drain GPIO0_D0 SDA'
assert_eq 1 "$(grep -c 'scl-gpios = <&gpio0 25 6>;' "$ROOT/device/overlays/cdmx-zero3w-i2c-gpio.dts")" \
  'physical pin 8 is open-drain GPIO0_D1 SCL'
assert_eq 2 "$(grep -c 'status = "disabled";' "$ROOT/device/overlays/cdmx-zero3w-i2c-gpio.dts")" \
  'custom I2C overlay disables FIQ debugger and UART2'
assert_eq 2 "$(sed -n '/cdmx-color-lab.conf/,/^EOF$/p' "$ROOT/device/install.sh" | grep -c '^i2c-')" \
  'software I2C kernel modules load at boot'
if command -v dtc >/dev/null 2>&1; then
  dtc -@ -I dts -O dtb -o "$tmp/cdmx-zero3w-i2c-gpio.dtbo" \
    "$ROOT/device/overlays/cdmx-zero3w-i2c-gpio.dts"
  printf 'ok - custom I2C overlay compiles\n'
else
  printf 'ok - custom I2C overlay compile skipped because dtc is unavailable\n'
fi
if ! grep -Eq 'python3-numpy python3-pil python3-pip python3-smbus python3-spidev' \
    "$ROOT/device/install.sh"; then
  printf 'not ok - color-lab Python dependencies are not preinstalled\n'
  failures=$((failures + 1))
else
  printf 'ok - color-lab Python dependencies are preinstalled\n'
fi

if (( failures > 0 )); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all host imager tests passed\n'
