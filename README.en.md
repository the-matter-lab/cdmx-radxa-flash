# CDMX workshop Radxa image and flasher

🇲🇽 [![Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README.md) ·
🇬🇧 [![English](https://img.shields.io/badge/lang-English-blue.svg)](README.en.md)

This is the workshop infrastructure repository. It builds the reproducible
RadxaOS image for the ZERO 3W boards, personalizes `equipo0`–`equipo9` and
`admin`, and contains the Wi-Fi portal, Openbox/noVNC desktop, and macOS and
Windows flashing helpers.

Participants work in two separate repositories:

- [`the-matter-lab/cdmx-local-ai`](https://github.com/the-matter-lab/cdmx-local-ai): Pi/PicoClaw agent and Telegram/Discord channels.
- [`the-matter-lab/cdmx-bayesopt`](https://github.com/the-matter-lab/cdmx-bayesopt): Bayesian-optimization lab.

## Flash a card

Open **[cdmx-radxaflash.mantilla.ca](https://cdmx-radxaflash.mantilla.ca)** and
download the helper for your system:

1. Insert an SD card of at least 8 GB.
2. On macOS, open `Start-CDMX-Radxa-Flasher.command` from the ZIP. On Windows,
   run `CDMX-Radxa-Flasher.exe` as Administrator.
3. Select the removable drive and `equipo0`–`equipo9` or `admin`.
4. Confirm the erase and wait for both writing **and read-back verification** to
   reach 100%.

The public website can never access a laptop's disks directly. The privileged
helper listens only on `127.0.0.1`, shows only removable USB/SD disks, rechecks
the target before erasing, and downloads the version declared in
[`site/manifest.json`](site/manifest.json). It caches the image and SHA-512 for
subsequent cards.

The binaries are not commercially code-signed yet, so Gatekeeper or SmartScreen
may require an additional confirmation. GitHub Actions builds them publicly
from this repository.

### Run from source on macOS

```bash
git clone https://github.com/the-matter-lab/cdmx-radxa-flash.git
cd cdmx-radxa-flash
open host/start-imager.command
```

The launcher creates a local Python environment, installs the pinned FAT writer,
and asks for one administrator authorization. The existing
`host/flash-team.sh` CLI is also available.

## Image contents

- Pinned RadxaOS Debian 12 Bookworm arm64 for ZERO 3, release `rsdk-b1`.
- Lightweight 1280×720 Openbox desktop with three workspaces, terminal, Geany,
  CPU/RAM/temperature monitor, and Matter Lab wallpaper.
- Shared noVNC desktop: control through `control.html`, observation through
  `view.html`.
- Captive Wi-Fi portal for keyboard-free venue onboarding.
- Public-key SSH, passwordless local `sudo`, and systemd services that recover
  after normal power cycles.
- Python dependencies and I2C4-M0/SPI3-M1 overlays for the color lab.
- An exact `cdmx-local-ai` version pinned in
  [`image/cdmx-local-ai.env`](image/cdmx-local-ai.env); agent code is not
  duplicated here.
- A launcher that clones or updates `cdmx-local-ai` and `cdmx-bayesopt` when a
  participant chooses it. Exercise repositories are not pre-cloned.

Samba is not part of the workshop cards. The image removes KDE, local browsers,
and Samba packages to conserve storage and RAM on the 1 GB boards.

## Workshop-day network and access

With no saved venue network, each board advertises `equipoN-setup` (or
`admin-setup`). The portal should open automatically on iPhone/iPad, macOS,
Windows, and Android. If the OS does not open it, use:

```text
equipoN: http://10.42.N.1:8080/
admin:   http://10.42.10.1:8080/
```

After saving Wi-Fi, reconnect the laptop or phone to that LAN:

If the saved network becomes unavailable, the board retries it and, after
approximately 60–75 seconds offline, advertises `equipoN-setup` (or
`admin-setup`) again. Rejoin that network to enter a new SSID and password; the
card does not need to be reflashed.

| Purpose | Address |
|---|---|
| noVNC control | `http://equipoN.local:6080/control.html` |
| Read-only noVNC | `http://equipoN.local:6080/view.html` |
| SSH | `ssh cdmx@equipoN.local` |
| Restart onboarding | `sudo cdmx-network reset` |

The ZERO 3W has one radio. The `-setup` access point is for onboarding and
recovery, not a simultaneous second network. A dedicated router without client
isolation is recommended for 50 participants.

## Build a new image

On a Mac with Docker Desktop and an SSH public key:

```bash
./host/download-stock-image.sh
./host/build-workshop-image.sh
make test
```

The build uses a snapshot of the current commit, downloads the agent at its
pinned commit, modifies a copy of the official image in an ARM64 container,
cleans identifiers and host keys, and produces:

```text
image/cdmx-workshop-golden.img.xz
image/cdmx-workshop-golden.img.xz.sha512
```

Before publishing, update `version`, sizes, SHA-512, and `docker` in
`site/manifest.json`. The public site and both helpers consume that same file,
so every operator flashes exactly the same version.

## Docker and publication

The image is also split into layers and published at
[`bestquark/cdmx-radxa-zero3w`](https://hub.docker.com/r/bestquark/cdmx-radxa-zero3w):

```bash
./docker/prepare-image-parts.sh
docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg IMAGE_VERSION=VERSION \
  -f docker/Dockerfile.sd-image image \
  -t bestquark/cdmx-radxa-zero3w:VERSION \
  -t bestquark/cdmx-radxa-zero3w:latest --push
```

`host/pull-workshop-image.sh` reconstructs the image from Docker and verifies
its checksum. Multi-gigabyte artifacts stay outside Git; only code, metadata,
and checksums are versioned.

Any `v*` tag automatically builds the macOS and Windows helpers and creates a
GitHub Release. Lepton serves `site/` and the verified image through Caddy and
Cloudflare Tunnel. Reproducible site configuration lives in
[`deploy/`](deploy/README.md).

microSD readers connected through USB-A or USB-C are detected as USB disks,
including adapters that report the card as fixed media. Boot and system disks
remain excluded.

The public page talks only to the privileged helper on `127.0.0.1:8766`: it
shows removable disks, identities, and progress, while physical reads and
writes always happen on the laptop. The CORS bridge accepts only the Matter Lab
public origin and preserves the per-process confirmation token.

## Security and reliability

- Disk selection rejects the system disk, individual partitions, fixed internal
  drives, targets smaller than 4 GB, and disks that stop being removable before
  writing.
- Every card is verified by reading the written bytes and comparing them with
  the decompressed source stream. The identity is then written to the FAT
  partition and read back.
- SSH host keys and machine identity regenerate after cloning. Volatile bounded
  logs, journaled ext4, zram, and restartable services reduce wear and recover
  after power returns.
- Power loss during a write can corrupt any SD card. Use `sudo poweroff` when
  possible and keep verified spare cards.
- noVNC and setup Wi-Fi are deliberately open on the workshop LAN; never expose
  either directly to the public Internet.

See [`host/WORKFLOW.md`](host/WORKFLOW.md) for operator details and
[`docs/INSTRUCTOR-CHECKLIST.md`](docs/INSTRUCTOR-CHECKLIST.md) for the event
checklist.
