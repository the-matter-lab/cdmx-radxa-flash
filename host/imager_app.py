#!/usr/bin/env python3
"""Cross-platform, loopback-only SD-card imager for the CDMX workshop."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import lzma
import os
import platform
import re
import secrets
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import BinaryIO


HOST_SYSTEM = platform.system()
SOURCE_ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ROOT = Path(getattr(sys, "_MEIPASS", SOURCE_ROOT))
LOCAL_MANIFEST = BUNDLE_ROOT / "site" / "manifest.json"
DEFAULT_MANIFEST_URL = "https://cdmx-radxaflash.mantilla.ca/manifest.json"
TRUSTED_WEB_ORIGIN = "https://cdmx-radxaflash.mantilla.ca"
PUBLIC_SITE_URL = TRUSTED_WEB_ORIGIN + "/"
LOCAL_GOLDEN_IMAGE = SOURCE_ROOT / "image" / "cdmx-workshop-golden.img.xz"
MAC_DISK_PATTERN = re.compile(r"^/dev/disk[0-9]+$")
LINUX_DISK_PATTERN = re.compile(r"^/dev/(?:sd[a-z]+|mmcblk[0-9]+)$")
WINDOWS_DISK_PATTERN = re.compile(r"^\\\\\.\\PhysicalDrive([0-9]+)$", re.IGNORECASE)
SHA512_PATTERN = re.compile(r"^[0-9a-f]{128}$")
WINDOWS_SAFE_BUS_TYPES = {"USB", "SD", "MMC"}
CHUNK_SIZE = 4 * 1024 * 1024
RUNTIME: dict[str, object] = {}
DISK_CACHE: tuple[float, list[dict[str, object]]] = (0.0, [])
DISK_CACHE_LOCK = threading.Lock()


def command(arguments: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, check=check, text=True, capture_output=True)


def parse_diskutil_info(output: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in output.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        result[key.strip()] = value.strip()
    return result


def mac_disk_size(info: dict[str, str]) -> int:
    match = re.search(r"\(([0-9]+) Bytes", info.get("Disk Size", ""))
    return int(match.group(1)) if match else 0


def mac_disk_is_safe(disk: str, info: dict[str, str]) -> bool:
    if not MAC_DISK_PATTERN.fullmatch(disk) or disk == "/dev/disk0":
        return False
    if info.get("Whole") != "Yes" or mac_disk_size(info) < 4_000_000_000:
        return False
    removable = info.get("Removable Media", "").strip().lower() in {"yes", "removable"}
    external = info.get("Device Location", "").strip().lower() == "external"
    usb = info.get("Protocol", "").strip().lower() == "usb"
    internal = (
        info.get("Device Location", "").strip().lower() == "internal"
        or info.get("Internal", "").strip().lower() == "yes"
    )
    return not (internal and not removable) and (removable or external or usb)


# Backwards-compatible names used by the focused unit tests.
disk_size = mac_disk_size
disk_is_safe = mac_disk_is_safe


def mac_disk_info(disk: str) -> dict[str, str]:
    if not MAC_DISK_PATTERN.fullmatch(disk):
        raise ValueError("invalid whole-disk identifier")
    return parse_diskutil_info(command(["diskutil", "info", disk]).stdout)


def list_macos_disks() -> list[dict[str, object]]:
    listing = command(["diskutil", "list"], check=False).stdout
    candidates = re.findall(r"^(/dev/disk[0-9]+) \([^\n]*physical\):", listing, re.MULTILINE)
    disks: list[dict[str, object]] = []
    for disk in candidates:
        try:
            info = mac_disk_info(disk)
        except (OSError, subprocess.SubprocessError, ValueError):
            continue
        if mac_disk_is_safe(disk, info):
            disks.append(
                {
                    "id": disk,
                    "name": info.get("Device / Media Name", "Removable disk"),
                    "size": mac_disk_size(info),
                    "protocol": info.get("Protocol", "Unknown"),
                    "removable": info.get("Removable Media", "Unknown"),
                }
            )
    return disks


def powershell(script: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    executable = "powershell.exe"
    return command(
        [executable, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
        check=check,
    )


def windows_disk_is_safe(item: dict[str, object]) -> bool:
    try:
        size = int(item.get("size") or 0)
    except (TypeError, ValueError):
        return False
    bus_type = str(item.get("protocol") or "").strip().upper()
    disk = str(item.get("id") or "")
    return (
        bool(WINDOWS_DISK_PATTERN.fullmatch(disk))
        and not bool(item.get("is_boot"))
        and not bool(item.get("is_system"))
        and size >= 4_000_000_000
        and bus_type in WINDOWS_SAFE_BUS_TYPES
    )


def list_windows_disks() -> list[dict[str, object]]:
    script = r"""
$items = Get-Disk | ForEach-Object {
  [pscustomobject]@{
    id = "\\.\PhysicalDrive$($_.Number)"
    name = $_.FriendlyName
    size = [int64]$_.Size
    protocol = $_.BusType.ToString()
    is_boot = [bool]$_.IsBoot
    is_system = [bool]$_.IsSystem
  }
}
ConvertTo-Json -InputObject @($items) -Compress
"""
    output = powershell(script).stdout.strip() or "[]"
    payload = json.loads(output)
    disks: list[dict[str, object]] = []
    for item in payload:
        if not isinstance(item, dict) or not windows_disk_is_safe(item):
            continue
        disks.append(
            {
                "id": item.get("id"),
                "name": item.get("name") or "USB/SD card reader",
                "size": int(item.get("size") or 0),
                "protocol": str(item.get("protocol") or "Unknown"),
                "removable": True,
            }
        )
    return disks


def linux_disk_is_safe(item: dict[str, object], root_chain: set[str]) -> bool:
    path = str(item.get("path") or "")
    transport = str(item.get("tran") or "").strip().lower()
    removable = item.get("rm") is True or str(item.get("rm") or "").strip().lower() in {"1", "true", "yes"}
    try:
        size = int(item.get("size") or 0)
    except (TypeError, ValueError):
        return False
    return (
        item.get("type") == "disk"
        and bool(LINUX_DISK_PATTERN.fullmatch(path))
        and size >= 4_000_000_000
        and path not in root_chain
        and (removable or transport in {"usb", "mmc"})
    )


def list_linux_disks() -> list[dict[str, object]]:
    payload = json.loads(
        command(["lsblk", "-J", "-b", "-d", "-o", "NAME,PATH,SIZE,MODEL,TRAN,RM,TYPE"]).stdout
    )
    disks: list[dict[str, object]] = []
    root_source = command(["findmnt", "-nro", "SOURCE", "/"], check=False).stdout.strip()
    root_chain = set(
        command(["lsblk", "-sno", "PATH", root_source], check=False).stdout.split()
    ) if root_source else set()
    for item in payload.get("blockdevices", []):
        path = str(item.get("path", ""))
        transport = str(item.get("tran") or "")
        removable = bool(item.get("rm"))
        if linux_disk_is_safe(item, root_chain):
            disks.append(
                {
                    "id": path,
                    "name": str(item.get("model") or "Removable disk").strip(),
                    "size": int(item.get("size") or 0),
                    "protocol": transport or "Unknown",
                    "removable": removable,
                }
            )
    return disks


def list_safe_disks(*, cached: bool = True) -> list[dict[str, object]]:
    global DISK_CACHE
    with DISK_CACHE_LOCK:
        now = time.monotonic()
        if cached and now - DISK_CACHE[0] < 1.5:
            return [dict(item) for item in DISK_CACHE[1]]
        if HOST_SYSTEM == "Darwin":
            disks = list_macos_disks()
        elif HOST_SYSTEM == "Windows":
            disks = list_windows_disks()
        elif HOST_SYSTEM == "Linux":
            disks = list_linux_disks()
        else:
            raise OSError(f"unsupported host operating system: {HOST_SYSTEM}")
        DISK_CACHE = (now, disks)
        return [dict(item) for item in disks]


def valid_disk_identifier(disk: str) -> bool:
    if HOST_SYSTEM == "Darwin":
        return bool(MAC_DISK_PATTERN.fullmatch(disk))
    if HOST_SYSTEM == "Windows":
        return bool(WINDOWS_DISK_PATTERN.fullmatch(disk))
    if HOST_SYSTEM == "Linux":
        return bool(LINUX_DISK_PATTERN.fullmatch(disk))
    return False


def raw_disk_path(disk: str) -> str:
    if not valid_disk_identifier(disk):
        raise ValueError("invalid whole-disk identifier")
    if HOST_SYSTEM == "Darwin":
        return "/dev/r" + disk.removeprefix("/dev/")
    return disk


def provisioning_disk_path(disk: str) -> str:
    """Return a device that permits the small, unaligned FAT metadata writes."""
    if not valid_disk_identifier(disk):
        raise ValueError("invalid whole-disk identifier")
    # macOS raw character devices (/dev/rdiskN) require sector-aligned I/O.
    # PyFatFS performs small directory-entry reads and writes, so provisioning
    # uses the buffered block device after the fast bulk transfer has finished.
    return disk


def windows_disk_number(disk: str) -> int:
    match = WINDOWS_DISK_PATTERN.fullmatch(disk)
    if not match:
        raise ValueError("invalid Windows physical-disk identifier")
    return int(match.group(1))


def ensure_disk(disk: str, required_bytes: int = 0) -> dict[str, object]:
    if not valid_disk_identifier(disk):
        raise ValueError("invalid whole-disk identifier")
    for item in list_safe_disks(cached=False):
        if item.get("id") == disk:
            if required_bytes and int(item.get("size") or 0) < required_bytes:
                raise ValueError("selected SD card is smaller than the image")
            return item
    raise ValueError("selected disk is not a safe removable whole disk")


def validate_team(team: object) -> int | str:
    if team == "admin":
        return "admin"
    if isinstance(team, bool) or not isinstance(team, int) or team not in range(10):
        raise ValueError("identity must be admin or an integer from 0 through 9")
    return team


def parse_cli_team(value: str) -> int | str:
    if value == "admin":
        return value
    try:
        return validate_team(int(value))
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError("team must be 0 through 9 or admin") from exc


def identity_name(identity: object) -> str:
    validated = validate_team(identity)
    return "admin" if validated == "admin" else f"equipo{validated}"


def validate_manifest(payload: object) -> dict[str, object]:
    if not isinstance(payload, dict) or payload.get("schema") != 1:
        raise ValueError("unsupported image manifest")
    image = payload.get("image")
    if not isinstance(image, dict):
        raise ValueError("manifest has no image")
    required = ("filename", "url", "sha512", "compressed_bytes", "uncompressed_bytes")
    if any(key not in image for key in required):
        raise ValueError("manifest image metadata is incomplete")
    filename = image["filename"]
    if not isinstance(filename, str) or Path(filename).name != filename:
        raise ValueError("manifest image filename is invalid")
    digest = str(image["sha512"]).lower()
    if not SHA512_PATTERN.fullmatch(digest):
        raise ValueError("manifest SHA-512 is invalid")
    parsed = urllib.parse.urlparse(str(image["url"]))
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("manifest image URL must use HTTPS")
    if int(image["compressed_bytes"]) < 1 or int(image["uncompressed_bytes"]) < 4_000_000_000:
        raise ValueError("manifest image sizes are invalid")
    result = dict(payload)
    result["image"] = dict(image, sha512=digest)
    return result


def load_manifest(source: str) -> dict[str, object]:
    parsed = urllib.parse.urlparse(source)
    if parsed.scheme in {"https", "http"}:
        if parsed.scheme != "https" and parsed.hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("remote manifest must use HTTPS")
        request = urllib.request.Request(source, headers={"User-Agent": "CDMX-Radxa-Flasher/2"})
        with urllib.request.urlopen(request, timeout=15) as response:
            data = response.read(1_000_001)
            if len(data) > 1_000_000:
                raise ValueError("manifest is unexpectedly large")
    else:
        data = Path(source).read_bytes()
    return validate_manifest(json.loads(data))


def cache_directory() -> Path:
    override = os.environ.get("CDMX_IMAGE_CACHE")
    if override:
        return Path(override).expanduser()
    if HOST_SYSTEM == "Windows":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return base / "CDMXRadxaFlash" / "cache"
    if HOST_SYSTEM == "Darwin":
        return Path.home() / "Library" / "Caches" / "CDMXRadxaFlash"
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "cdmx-radxa-flash"


class JobState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.running_lock = threading.Lock()
        self.data: dict[str, object] = {
            "running": False,
            "phase": "idle",
            "label": "Ready",
            "progress": 0.0,
            "stage_percent": 0.0,
            "bytes_done": 0,
            "bytes_total": 0,
            "speed_mbps": 0.0,
            "eta_seconds": None,
            "disk": None,
            "team": None,
            "error": None,
            "logs": [],
        }

    def update(self, **changes: object) -> None:
        with self.lock:
            self.data.update(changes)

    def log(self, message: str) -> None:
        with self.lock:
            logs = list(self.data.get("logs", []))
            logs.append(message)
            self.data["logs"] = logs[-40:]

    def reserve(self) -> bool:
        with self.lock:
            if self.data.get("running"):
                return False
            self.data.update(running=True, phase="queued", label="Queued", error=None)
            return True

    def snapshot(self) -> dict[str, object]:
        with self.lock:
            snapshot = dict(self.data)
            snapshot["logs"] = list(self.data.get("logs", []))
        manifest = RUNTIME.get("manifest")
        image: dict[str, object] = manifest.get("image", {}) if isinstance(manifest, dict) else {}
        cached_path = cached_image_path(image) if image else None
        snapshot["disks"] = list_safe_disks()
        snapshot["images"] = {
            "golden": {
                "ready": bool(image),
                "cached": bool(cached_path and cached_path.is_file()),
                "name": image.get("filename", ""),
                "size": image.get("compressed_bytes", 0),
                "version": manifest.get("version", "") if isinstance(manifest, dict) else "",
            }
        }
        return snapshot


STATE = JobState()


def progress_values(done: int, total: int, start: float) -> tuple[float, float, float | None]:
    elapsed = max(time.monotonic() - start, 0.001)
    speed = done / elapsed
    percent = min(100.0, done * 100.0 / max(total, 1))
    eta = (total - done) / speed if speed > 0 and done < total else None
    return percent, speed / 1_000_000, eta


def update_transfer(phase: str, label: str, done: int, total: int, start: float, base: float, weight: float) -> None:
    stage, speed, eta = progress_values(done, total, start)
    STATE.update(
        phase=phase,
        label=label,
        progress=base + stage * weight,
        stage_percent=stage,
        bytes_done=done,
        bytes_total=total,
        speed_mbps=speed,
        eta_seconds=eta,
    )


def cached_image_path(image: dict[str, object]) -> Path:
    digest = str(image["sha512"]).lower()
    return cache_directory() / f"{digest[:16]}-{image['filename']}"


def discard_cached_image(path: Path) -> None:
    for candidate in (path, Path(str(path) + ".sha512"), path.with_name(path.name + ".partial")):
        candidate.unlink(missing_ok=True)


def migrate_legacy_cache(image: dict[str, object], destination: Path) -> None:
    legacy = cache_directory() / str(image["filename"])
    if legacy == destination or not legacy.exists():
        return
    expected_digest = str(image["sha512"])
    expected_size = int(image["compressed_bytes"])
    legacy_sidecar = Path(str(legacy) + ".sha512")
    if (
        not destination.exists()
        and legacy.is_file()
        and legacy.stat().st_size == expected_size
        and sidecar_digest(legacy) == expected_digest
    ):
        destination.parent.mkdir(parents=True, exist_ok=True)
        os.replace(legacy, destination)
        if legacy_sidecar.is_file():
            os.replace(legacy_sidecar, Path(str(destination) + ".sha512"))
        STATE.log("Reused the verified legacy image cache")
        return
    STATE.log("Removed an image cached for an older release")
    discard_cached_image(legacy)


def sidecar_digest(path: Path) -> str | None:
    sidecar = Path(str(path) + ".sha512")
    if not sidecar.is_file():
        return None
    value = sidecar.read_text(encoding="utf-8").split()[0].lower()
    return value if SHA512_PATTERN.fullmatch(value) else None


def hash_compressed_image(path: Path, expected: str) -> None:
    total = path.stat().st_size
    done = 0
    digest = hashlib.sha512()
    start = time.monotonic()
    with path.open("rb") as source:
        while chunk := source.read(CHUNK_SIZE):
            digest.update(chunk)
            done += len(chunk)
            update_transfer("checksum", "Checking image", done, total, start, 0.0, 0.10)
    if digest.hexdigest().lower() != expected:
        raise ValueError("compressed-image checksum mismatch")


def download_image(image: dict[str, object], destination: Path) -> None:
    expected_size = int(image["compressed_bytes"])
    expected_digest = str(image["sha512"])
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(destination.name + ".partial")
    request = urllib.request.Request(str(image["url"]), headers={"User-Agent": "CDMX-Radxa-Flasher/2"})
    digest = hashlib.sha512()
    done = 0
    start = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=60) as response, partial.open("wb") as output:
            while chunk := response.read(CHUNK_SIZE):
                output.write(chunk)
                digest.update(chunk)
                done += len(chunk)
                update_transfer("download", "Downloading workshop image", done, expected_size, start, 0.0, 0.10)
            output.flush()
            os.fsync(output.fileno())
        if done != expected_size:
            raise OSError(f"downloaded {done} bytes; expected {expected_size}")
        if digest.hexdigest().lower() != expected_digest:
            raise ValueError("downloaded image checksum mismatch")
        os.replace(partial, destination)
        Path(str(destination) + ".sha512").write_text(
            f"{expected_digest}  {destination.name}\n", encoding="utf-8"
        )
    except BaseException:
        partial.unlink(missing_ok=True)
        raise


def prepare_image() -> tuple[Path, dict[str, object]]:
    manifest = RUNTIME.get("manifest")
    if not isinstance(manifest, dict) or not isinstance(manifest.get("image"), dict):
        raise ValueError("no valid workshop image manifest is loaded")
    image = dict(manifest["image"])
    expected = str(image["sha512"])
    override = RUNTIME.get("image_override")
    if isinstance(override, Path):
        path = override
    elif LOCAL_GOLDEN_IMAGE.is_file() and sidecar_digest(LOCAL_GOLDEN_IMAGE) == expected:
        path = LOCAL_GOLDEN_IMAGE
    else:
        path = cached_image_path(image)
        migrate_legacy_cache(image, path)
        if path.is_file():
            try:
                if path.stat().st_size != int(image["compressed_bytes"]):
                    raise ValueError("cached image size mismatch")
                hash_compressed_image(path, expected)
            except (OSError, ValueError) as error:
                STATE.log(f"Discarded invalid cached image: {error}")
                discard_cached_image(path)
            else:
                STATE.log("Compressed checksum passed")
                return path, image
        STATE.log(f"Downloading image version {manifest.get('version', 'latest')}")
        download_image(image, path)
        STATE.log("Download checksum passed")
        return path, image
    if not path.is_file():
        raise FileNotFoundError(f"image not found: {path}")
    hash_compressed_image(path, expected)
    STATE.log("Compressed checksum passed")
    return path, image


def write_all(destination: BinaryIO, chunk: bytes) -> None:
    view = memoryview(chunk)
    while view:
        written = destination.write(view)
        if written is None or written <= 0:
            raise OSError("SD-card write returned no data")
        view = view[written:]


def prepare_disk_for_write(disk: str) -> None:
    if HOST_SYSTEM == "Darwin":
        command(["diskutil", "unmountDisk", disk])
    elif HOST_SYSTEM == "Windows":
        number = windows_disk_number(disk)
        powershell(f"Set-Disk -Number {number} -IsReadOnly $false; Set-Disk -Number {number} -IsOffline $true")
    elif HOST_SYSTEM == "Linux":
        output = command(["lsblk", "-lnpo", "NAME,MOUNTPOINT", disk]).stdout
        for line in output.splitlines()[1:]:
            fields = line.split(maxsplit=1)
            if len(fields) == 2 and fields[1]:
                command(["umount", fields[0]])


def flush_device(destination: BinaryIO | None = None) -> None:
    if destination is not None:
        destination.flush()
        os.fsync(destination.fileno())
    if HOST_SYSTEM != "Windows":
        command(["sync"])


def write_image(image: Path, raw_disk: str, total: int) -> str:
    digest = hashlib.sha512()
    done = 0
    start = time.monotonic()
    with lzma.open(image, "rb") as source, open(raw_disk, "r+b", buffering=0) as destination:
        destination.seek(0)
        while chunk := source.read(CHUNK_SIZE):
            write_all(destination, chunk)
            digest.update(chunk)
            done += len(chunk)
            update_transfer("write", "Writing RadxaOS", done, total, start, 10.0, 0.55)
        flush_device(destination)
    if done != total:
        raise OSError(f"image produced {done} bytes; expected {total}")
    return digest.hexdigest()


def verify_image(raw_disk: str, total: int, expected: str) -> None:
    digest = hashlib.sha512()
    done = 0
    start = time.monotonic()
    with open(raw_disk, "rb", buffering=0) as source:
        while done < total:
            chunk = source.read(min(CHUNK_SIZE, total - done))
            if not chunk:
                raise OSError("SD card ended before verification completed")
            digest.update(chunk)
            done += len(chunk)
            update_transfer("verify", "Verifying written bytes", done, total, start, 65.0, 0.33)
    if digest.hexdigest() != expected:
        raise OSError("read-back verification failed")


def gpt_partition_offsets(raw_disk: str) -> list[tuple[int, int]]:
    with open(raw_disk, "rb", buffering=0) as source:
        header = b""
        sector_size = 0
        for candidate in (512, 4096):
            source.seek(candidate)
            candidate_header = source.read(candidate)
            if candidate_header.startswith(b"EFI PART"):
                header = candidate_header
                sector_size = candidate
                break
        if not header:
            raise ValueError("written image has no readable GPT header")
        entry_lba = struct.unpack_from("<Q", header, 72)[0]
        entry_count = struct.unpack_from("<I", header, 80)[0]
        entry_size = struct.unpack_from("<I", header, 84)[0]
        if not (1 <= entry_count <= 1024 and 128 <= entry_size <= 1024):
            raise ValueError("written image has invalid GPT entries")
        source.seek(entry_lba * sector_size)
        table_bytes = entry_count * entry_size
        aligned_bytes = ((table_bytes + sector_size - 1) // sector_size) * sector_size
        table = source.read(aligned_bytes)
        if len(table) < table_bytes:
            raise ValueError("written image has a truncated GPT")
        offsets: list[tuple[int, int]] = []
        for index in range(entry_count):
            start = index * entry_size
            entry = table[start : start + entry_size]
            if entry[:16] == bytes(16):
                continue
            first_lba, last_lba = struct.unpack_from("<QQ", entry, 32)
            if first_lba and last_lba >= first_lba:
                offsets.append((first_lba * sector_size, (last_lba - first_lba + 1) * sector_size))
        return offsets


def provision_identity(raw_disk: str, team: int | str) -> None:
    try:
        from pyfatfs.PyFatFS import PyFatFS
    except ImportError as exc:
        raise RuntimeError("the packaged FAT writer is unavailable") from exc

    marker = (
        "# Generated by cdmx-radxa-flash; contains no secrets.\n"
        f"CDMX_TEAM={team}\n"
        f"CDMX_HOSTNAME={identity_name(team)}\n"
    )
    candidates = [item for item in gpt_partition_offsets(raw_disk) if item[1] <= 64 * 1024 * 1024]
    for offset, _size in candidates:
        filesystem = None
        try:
            filesystem = PyFatFS(raw_disk, offset=offset, read_only=False)
            if not filesystem.exists("before.txt"):
                filesystem.close()
                filesystem = None
                continue
            filesystem.writetext("cdmx-team.env", marker)
            filesystem.close()
            filesystem = None
            filesystem = PyFatFS(raw_disk, offset=offset, read_only=True)
            if filesystem.readtext("cdmx-team.env") != marker:
                raise OSError("team marker verification failed")
            filesystem.close()
            filesystem = None
            flush_device()
            return
        except Exception:
            if filesystem is not None:
                try:
                    filesystem.close()
                except Exception:
                    pass
    raise OSError("could not write the team marker to the Radxa config partition")


def eject_disk(disk: str) -> None:
    if HOST_SYSTEM == "Darwin":
        command(["diskutil", "eject", disk])
    elif HOST_SYSTEM == "Windows":
        # The disk remains offline after verification, so Windows has no mounted
        # filesystem to flush. Unplugging it is safe at this point.
        return
    elif HOST_SYSTEM == "Linux":
        if command(["sh", "-c", "command -v udisksctl"], check=False).returncode == 0:
            command(["udisksctl", "power-off", "-b", disk], check=False)


def provision_existing_card(disk: str, team: int | str) -> None:
    """Assign an identity after a completed image write/read-back cycle."""
    ensure_disk(disk)
    prepare_disk_for_write(disk)
    provision_identity(provisioning_disk_path(disk), validate_team(team))
    eject_disk(disk)


def is_administrator() -> bool:
    if HOST_SYSTEM == "Windows":
        return bool(ctypes.windll.shell32.IsUserAnAdmin())  # type: ignore[attr-defined]
    return os.geteuid() == 0


def flash_job(disk: str, team: int | str) -> None:
    with STATE.running_lock:
        try:
            team = validate_team(team)
            STATE.update(
                running=True,
                phase="starting",
                label="Preparing",
                progress=0.0,
                stage_percent=0.0,
                bytes_done=0,
                bytes_total=0,
                speed_mbps=0.0,
                eta_seconds=None,
                disk=disk,
                team=team,
                error=None,
                logs=[],
            )
            if not is_administrator():
                raise PermissionError("start the imager with administrator privileges")
            image_path, image = prepare_image()
            total = int(image["uncompressed_bytes"])
            ensure_disk(disk, total)
            STATE.log(f"Target: {disk}")
            STATE.log(f"Image: {image_path.name}")
            ensure_disk(disk, total)
            prepare_disk_for_write(disk)
            raw = raw_disk_path(disk)
            source_sha = write_image(image_path, raw, total)
            STATE.log("Write completed; starting read-back")
            verify_image(raw, total, source_sha)
            STATE.log("Read-back checksum passed")
            STATE.update(phase="provision", label=f"Assigning {identity_name(team)}", progress=98.5)
            prepare_disk_for_write(disk)
            provision_identity(provisioning_disk_path(disk), team)
            STATE.log(f"Assigned {identity_name(team)}")
            STATE.update(phase="eject", label="Finishing safely", progress=99.5)
            eject_disk(disk)
            STATE.log("Safe to remove the SD card")
            STATE.update(
                running=False,
                phase="done",
                label=f"{identity_name(team)} ready",
                progress=100.0,
                stage_percent=100.0,
                bytes_done=total,
                bytes_total=total,
                speed_mbps=0.0,
                eta_seconds=0.0,
            )
        except Exception as exc:
            STATE.log(f"ERROR: {exc}")
            STATE.update(
                running=False,
                phase="error",
                label="Flash failed",
                error=str(exc),
                speed_mbps=0.0,
                eta_seconds=None,
            )


class ImagerHandler(BaseHTTPRequestHandler):
    server_version = "CDMXImager/2.1"

    def log_message(self, fmt: str, *args: object) -> None:
        return

    @property
    def token(self) -> str:
        return self.server.token  # type: ignore[attr-defined]

    def response(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def trusted_web_origin(self) -> bool:
        return self.headers.get("Origin", "") == TRUSTED_WEB_ORIGIN

    def cors_headers(self) -> None:
        if self.trusted_web_origin():
            self.send_header("Access-Control-Allow-Origin", TRUSTED_WEB_ORIGIN)
            self.send_header("Access-Control-Allow-Private-Network", "true")
            self.send_header("Vary", "Origin")

    def valid_host(self) -> bool:
        host = self.headers.get("Host", "").lower()
        port = self.server.server_address[1]
        return host in {f"127.0.0.1:{port}", f"localhost:{port}"}

    def json_response(self, status: int, payload: object) -> None:
        self.response(status, "application/json; charset=utf-8", (json.dumps(payload, separators=(",", ":")) + "\n").encode())

    def do_OPTIONS(self) -> None:  # noqa: N802
        if not self.valid_host() or not self.path.startswith("/api/") or not self.trusted_web_origin():
            self.json_response(HTTPStatus.FORBIDDEN, {"error": "origin not allowed"})
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-CDMX-Token")
        self.send_header("Access-Control-Max-Age", "600")
        self.cors_headers()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if not self.valid_host():
            self.json_response(HTTPStatus.FORBIDDEN, {"error": "invalid host"})
            return
        if self.path == "/":
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Location", PUBLIC_SITE_URL)
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/api/session":
            if not self.trusted_web_origin():
                self.json_response(HTTPStatus.FORBIDDEN, {"error": "origin not allowed"})
                return
            self.json_response(HTTPStatus.OK, {"token": self.token, "api": 2})
        elif self.path == "/api/state":
            self.json_response(HTTPStatus.OK, STATE.snapshot())
        else:
            self.json_response(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self.valid_host():
            self.json_response(HTTPStatus.FORBIDDEN, {"error": "invalid host"})
            return
        if self.path != "/api/flash":
            self.json_response(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return
        if not secrets.compare_digest(self.headers.get("X-CDMX-Token", ""), self.token):
            self.json_response(HTTPStatus.FORBIDDEN, {"error": "invalid request token"})
            return
        if self.headers.get_content_type() != "application/json":
            self.json_response(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, {"error": "JSON required"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 2 or length > 4096:
                raise ValueError("invalid request size")
            payload = json.loads(self.rfile.read(length))
            disk = payload.get("disk")
            team = validate_team(payload.get("team"))
            if not isinstance(disk, str) or not valid_disk_identifier(disk):
                raise ValueError("invalid disk")
            ensure_disk(disk)
        except (json.JSONDecodeError, OSError, subprocess.SubprocessError, ValueError) as exc:
            self.json_response(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        if not STATE.reserve():
            self.json_response(HTTPStatus.CONFLICT, {"error": "a flash is already running"})
            return
        thread = threading.Thread(target=flash_job, args=(disk, team), daemon=True)
        try:
            thread.start()
        except Exception:
            STATE.update(running=False, phase="error", label="Could not start flash")
            raise
        self.json_response(HTTPStatus.ACCEPTED, {"started": True})


class ImagerServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], token: str):
        self.token = token
        super().__init__(address, ImagerHandler)


def initialize_runtime(manifest_source: str, image_override: str | None) -> None:
    try:
        manifest = load_manifest(manifest_source)
    except Exception as remote_error:
        if not LOCAL_MANIFEST.is_file() or Path(manifest_source).resolve() == LOCAL_MANIFEST.resolve():
            raise remote_error
        manifest = load_manifest(str(LOCAL_MANIFEST))
        print(f"Remote manifest unavailable ({remote_error}); using bundled metadata.", flush=True)
    RUNTIME["manifest"] = manifest
    if image_override:
        RUNTIME["image_override"] = Path(image_override).expanduser().resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--manifest", default=os.environ.get("CDMX_MANIFEST_URL", DEFAULT_MANIFEST_URL))
    parser.add_argument("--image", help="Use a local image that matches the manifest checksum")
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--provision-only", metavar="DISK", help="Finish identity assignment on an already verified card")
    parser.add_argument("--team", type=parse_cli_team, help="Identity for --provision-only: 0 through 9 or admin")
    args = parser.parse_args()
    if not is_administrator():
        print("Start this helper as Administrator so it can access the removable SD card.")
        return 77
    if bool(args.provision_only) != (args.team is not None):
        parser.error("--provision-only and --team must be used together")
    if args.provision_only:
        try:
            provision_existing_card(args.provision_only, args.team)
        except Exception as exc:
            print(f"Could not assign the card identity: {exc}")
            return 74
        print(f"Assigned {identity_name(args.team)}; the SD card is verified and safe to remove.")
        return 0
    try:
        initialize_runtime(args.manifest, args.image)
    except Exception as exc:
        print(f"Could not load image metadata: {exc}")
        return 69
    token = secrets.token_urlsafe(32)
    server = ImagerServer(("127.0.0.1", args.port), token)
    print("CDMX Radxa Flasher is ready.", flush=True)
    print(f"Open: {PUBLIC_SITE_URL}", flush=True)
    print("Keep this window open while flashing cards.", flush=True)
    if not args.no_browser:
        threading.Timer(0.8, lambda: webbrowser.open(PUBLIC_SITE_URL)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping CDMX Radxa Flasher.", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
