from __future__ import annotations

import argparse
import hashlib
import importlib.util
import http.client
from pathlib import Path
import struct
import tempfile
import threading
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).parents[1] / "host" / "imager_app.py"
SPEC = importlib.util.spec_from_file_location("imager_app", MODULE_PATH)
assert SPEC and SPEC.loader
imager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(imager)


REMOVABLE_SD = """
   Device Identifier:         disk10
   Device Node:               /dev/disk10
   Whole:                     Yes
   Device / Media Name:       Built In SDXC Reader
   Protocol:                  Secure Digital
   Disk Size:                 15.6 GB (15635841024 Bytes)
   Device Location:           Internal
   Removable Media:           Removable
"""

FIXED_INTERNAL = """
   Device Identifier:         disk0
   Whole:                     Yes
   Protocol:                  Apple Fabric
   Disk Size:                 1.0 TB (1000555581440 Bytes)
   Device Location:           Internal
   Removable Media:           Fixed
"""

USB_MICROSD_ADAPTER = """
   Device Identifier:         disk12
   Device Node:               /dev/disk12
   Whole:                     Yes
   Device / Media Name:       Generic USB3.0 Card Reader
   Protocol:                  USB
   Disk Size:                 512.1 GB (512110190592 Bytes)
   Device Location:           External
   Removable Media:           Fixed
"""


class ImagerTests(unittest.TestCase):
    def test_team_range_and_admin_identity(self):
        self.assertEqual(imager.validate_team(0), 0)
        self.assertEqual(imager.validate_team(9), 9)
        self.assertEqual(imager.validate_team("admin"), "admin")
        self.assertEqual(imager.identity_name("admin"), "admin")
        self.assertEqual(imager.identity_name(4), "equipo4")
        self.assertEqual(imager.parse_cli_team("0"), 0)
        self.assertEqual(imager.parse_cli_team("admin"), "admin")
        for invalid in (-1, 10, "0", True, None):
            with self.assertRaises(ValueError):
                imager.validate_team(invalid)
        with self.assertRaises(argparse.ArgumentTypeError):
            imager.parse_cli_team("equipo0")

    def test_raw_disk_path_has_no_shell_escapes(self):
        original = imager.HOST_SYSTEM
        try:
            imager.HOST_SYSTEM = "Darwin"
            self.assertEqual(imager.raw_disk_path("/dev/disk10"), "/dev/rdisk10")
            self.assertEqual(imager.provisioning_disk_path("/dev/disk10"), "/dev/disk10")
            with self.assertRaises(ValueError):
                imager.raw_disk_path("/dev/disk10s1")
            imager.HOST_SYSTEM = "Windows"
            self.assertEqual(imager.raw_disk_path(r"\\.\PhysicalDrive12"), r"\\.\PhysicalDrive12")
            with self.assertRaises(ValueError):
                imager.raw_disk_path(r"C:\\")
        finally:
            imager.HOST_SYSTEM = original

    def test_gpt_parser_uses_sector_aligned_reads(self):
        image = bytearray(3 * 512)
        header = memoryview(image)[512:1024]
        header[:8] = b"EFI PART"
        struct.pack_into("<Q", header, 72, 2)
        struct.pack_into("<I", header, 80, 4)
        struct.pack_into("<I", header, 84, 128)
        image[1024:1040] = b"\x01" * 16
        struct.pack_into("<QQ", image, 1024 + 32, 2048, 4095)

        class SectorAlignedDevice:
            def __init__(self, payload):
                self.payload = payload
                self.position = 0

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def seek(self, offset):
                self.position = offset

            def read(self, size):
                if self.position % 512 or size % 512:
                    raise OSError(22, "Invalid argument")
                result = self.payload[self.position : self.position + size]
                self.position += len(result)
                return bytes(result)

        with mock.patch("builtins.open", return_value=SectorAlignedDevice(image)):
            self.assertEqual(imager.gpt_partition_offsets("/dev/rdisk10"), [(1_048_576, 1_048_576)])

    def test_builtin_sd_reader_is_safe_but_fixed_disk_is_not(self):
        sd = imager.parse_diskutil_info(REMOVABLE_SD)
        fixed = imager.parse_diskutil_info(FIXED_INTERNAL)
        self.assertTrue(imager.disk_is_safe("/dev/disk10", sd))
        self.assertFalse(imager.disk_is_safe("/dev/disk0", fixed))
        self.assertEqual(imager.disk_size(sd), 15_635_841_024)

    def test_usb_microsd_adapter_is_safe_even_if_reported_fixed(self):
        adapter = imager.parse_diskutil_info(USB_MICROSD_ADAPTER)
        self.assertTrue(imager.disk_is_safe("/dev/disk12", adapter))
        self.assertEqual(imager.disk_size(adapter), 512_110_190_592)

    def test_windows_usb_adapter_is_safe_but_system_disk_is_not(self):
        adapter = {
            "id": r"\\.\PhysicalDrive8",
            "name": "USB SD Reader",
            "size": 512_110_190_592,
            "protocol": "usb",
            "is_boot": False,
            "is_system": False,
        }
        self.assertTrue(imager.windows_disk_is_safe(adapter))
        self.assertFalse(imager.windows_disk_is_safe(dict(adapter, is_system=True)))
        self.assertFalse(imager.windows_disk_is_safe(dict(adapter, protocol="NVMe")))

    def test_windows_native_sd_and_mmc_readers_are_safe(self):
        base = {
            "id": r"\\.\PhysicalDrive3",
            "name": "Built-in card reader",
            "size": 64_000_000_000,
            "is_boot": False,
            "is_system": False,
        }
        self.assertTrue(imager.windows_disk_is_safe(dict(base, protocol="SD")))
        self.assertTrue(imager.windows_disk_is_safe(dict(base, protocol="MMC")))
        self.assertTrue(imager.windows_disk_is_safe(dict(base, protocol="USB")))

    def test_windows_prepare_uses_state_aware_script(self):
        original = imager.HOST_SYSTEM
        try:
            imager.HOST_SYSTEM = "Windows"
            with mock.patch.object(imager, "powershell_file") as run_script:
                imager.prepare_disk_for_write(r"\\.\PhysicalDrive12")
            run_script.assert_called_once_with(
                imager.WINDOWS_PREPARE_SCRIPT,
                "-DiskNumber",
                "12",
            )
        finally:
            imager.HOST_SYSTEM = original

    def test_powershell_error_exposes_windows_reason(self):
        failed = mock.Mock(returncode=1, stdout="", stderr="Access is denied")
        with mock.patch.object(imager, "command", return_value=failed):
            with self.assertRaisesRegex(OSError, "Access is denied"):
                imager.powershell("Get-Disk")

    def test_linux_usb_adapter_is_safe_even_if_not_marked_removable(self):
        adapter = {
            "name": "sdb",
            "path": "/dev/sdb",
            "size": 512_110_190_592,
            "model": "USB SD Reader",
            "tran": "usb",
            "rm": False,
            "type": "disk",
        }
        self.assertTrue(imager.linux_disk_is_safe(adapter, {"/dev/nvme0n1"}))
        self.assertFalse(imager.linux_disk_is_safe(adapter, {"/dev/sdb"}))
        self.assertFalse(imager.linux_disk_is_safe(dict(adapter, tran="nvme"), set()))

    def test_env_parser_does_not_execute_shell(self):
        manifest = {
            "schema": 1,
            "version": "test",
            "image": {
                "filename": "image.img.xz",
                "url": "https://example.test/image.img.xz",
                "sha512": "a" * 128,
                "compressed_bytes": 10,
                "uncompressed_bytes": 8_000_000_000,
            },
        }
        self.assertEqual(imager.validate_manifest(manifest)["version"], "test")
        manifest["image"]["url"] = "http://example.test/image.img.xz"
        with self.assertRaises(ValueError):
            imager.validate_manifest(manifest)

    def test_stale_legacy_cache_is_removed_and_redownloaded(self):
        payload = b"current image"
        digest = hashlib.sha512(payload).hexdigest()
        manifest = {
            "schema": 1,
            "version": "current",
            "image": {
                "filename": "workshop.img.xz",
                "url": "https://example.test/workshop-current.img.xz",
                "sha512": digest,
                "compressed_bytes": len(payload),
                "uncompressed_bytes": 8_000_000_000,
            },
        }
        previous_runtime = dict(imager.RUNTIME)
        try:
            with tempfile.TemporaryDirectory() as temporary:
                cache = Path(temporary)
                legacy = cache / "workshop.img.xz"
                legacy.write_bytes(b"previous image")
                Path(str(legacy) + ".sha512").write_text(f"{'0' * 128}  {legacy.name}\n")

                def fake_download(_image, destination):
                    self.assertFalse(legacy.exists())
                    destination.write_bytes(payload)

                imager.RUNTIME.clear()
                imager.RUNTIME["manifest"] = manifest
                with (
                    mock.patch.object(imager, "cache_directory", return_value=cache),
                    mock.patch.object(imager, "download_image", side_effect=fake_download) as download,
                ):
                    path, _ = imager.prepare_image()
                self.assertEqual(path.name, f"{digest[:16]}-workshop.img.xz")
                self.assertEqual(path.read_bytes(), payload)
                self.assertFalse(legacy.exists())
                download.assert_called_once()
        finally:
            imager.RUNTIME.clear()
            imager.RUNTIME.update(previous_runtime)

    def test_corrupt_versioned_cache_self_heals(self):
        payload = b"current image"
        digest = hashlib.sha512(payload).hexdigest()
        image = {
            "filename": "workshop.img.xz",
            "url": "https://example.test/workshop-current.img.xz",
            "sha512": digest,
            "compressed_bytes": len(payload),
            "uncompressed_bytes": 8_000_000_000,
        }
        previous_runtime = dict(imager.RUNTIME)
        try:
            with tempfile.TemporaryDirectory() as temporary:
                cache = Path(temporary)
                cached = cache / f"{digest[:16]}-workshop.img.xz"
                cached.write_bytes(b"broken image!")

                def fake_download(_image, destination):
                    self.assertFalse(destination.exists())
                    destination.write_bytes(payload)

                imager.RUNTIME.clear()
                imager.RUNTIME["manifest"] = {"schema": 1, "version": "current", "image": image}
                with (
                    mock.patch.object(imager, "cache_directory", return_value=cache),
                    mock.patch.object(imager, "download_image", side_effect=fake_download) as download,
                ):
                    path, _ = imager.prepare_image()
                self.assertEqual(path.read_bytes(), payload)
                download.assert_called_once()
        finally:
            imager.RUNTIME.clear()
            imager.RUNTIME.update(previous_runtime)

    def test_ui_has_all_teams_and_progress_semantics(self):
        public_html = (MODULE_PATH.parents[1] / "site" / "index.html").read_text(encoding="utf-8")
        self.assertLess(public_html.index('id="offline"'), public_html.index('id="devicePanel"'))
        self.assertIn("Inicia el lector local, inserta la tarjeta", public_html)
        self.assertIn("role=\"progressbar\"", public_html)
        self.assertIn("'admin'", public_html)
        self.assertIn("http://127.0.0.1:8766", public_html)
        self.assertIn("/api/session", public_html)
        self.assertIn("/api/flash", public_html)
        self.assertIn("IDENTITIES", public_html)
        self.assertIn("Reintentar", public_html)
        self.assertIn("Copiar comando", public_html)
        self.assertIn("lector SD integrado", public_html)
        self.assertIn('data-platform="windows"', public_html)
        self.assertIn('data-platform="linux"', public_html)
        self.assertIn("Ver script para", public_html)
        self.assertIn("Desinstalar", public_html)
        self.assertIn("Copiar desinstalador", public_html)
        self.assertIn("uninstall-macos.sh", public_html)
        self.assertIn("uninstall-windows.ps1", public_html)
        self.assertIn("uninstall-linux.sh", public_html)
        self.assertNotIn('id="mac"', public_html)
        self.assertIn(imager.PUBLIC_SITE_URL, (MODULE_PATH.parents[1] / "host" / "start-imager.command").read_text())

        mac_launcher = (MODULE_PATH.parents[1] / "site" / "start-macos.sh").read_text(encoding="utf-8")
        self.assertIn("SOURCE_COMMIT=c09d98c424d8ddf9d97ee2832ad0489ea4adb587", mac_launcher)
        self.assertIn("ARCHIVE_SHA256=b749b31ffe17cfaf14ad7c79e424f107c673afd8406dedde464d9b1a11b36008", mac_launcher)
        self.assertIn("codeload.github.com/the-matter-lab/cdmx-radxa-flash", mac_launcher)
        self.assertIn("shasum -a 256", mac_launcher)

        linux_launcher = (MODULE_PATH.parents[1] / "site" / "start-linux.sh").read_text(encoding="utf-8")
        self.assertIn("SOURCE_COMMIT=c09d98c424d8ddf9d97ee2832ad0489ea4adb587", linux_launcher)
        self.assertIn("sha256sum", linux_launcher)
        self.assertIn("exec sudo", linux_launcher)

        windows_launcher = (MODULE_PATH.parents[1] / "site" / "start-windows.ps1").read_text(encoding="utf-8")
        self.assertIn('$SourceCommit = "c09d98c424d8ddf9d97ee2832ad0489ea4adb587"', windows_launcher)
        self.assertIn("Get-FileHash -Algorithm SHA256", windows_launcher)
        self.assertIn("WindowsBuiltInRole]::Administrator", windows_launcher)

        windows_prepare = (MODULE_PATH.parents[1] / "host" / "windows" / "prepare-disk.ps1").read_text(encoding="utf-8")
        self.assertIn('@("USB", "SD", "MMC")', windows_prepare)
        self.assertIn("$Disk.IsOffline -and -not $Disk.IsReadOnly", windows_prepare)
        self.assertIn("Dismount-CDMXTargetVolumes", windows_prepare)
        self.assertIn("mountvol.exe $MountPoints[0] /p", windows_prepare)

        mac_uninstaller = (MODULE_PATH.parents[1] / "site" / "uninstall-macos.sh").read_text(encoding="utf-8")
        self.assertIn("/var/root/Library/Caches/CDMXRadxaFlash", mac_uninstaller)
        self.assertIn('APP_DIR="${HOME}/Library/Application Support/CDMXRadxaFlash"', mac_uninstaller)
        self.assertIn("No se modificó ninguna tarjeta SD", mac_uninstaller)

        linux_uninstaller = (MODULE_PATH.parents[1] / "site" / "uninstall-linux.sh").read_text(encoding="utf-8")
        self.assertIn("/root/.cache/cdmx-radxa-flash", linux_uninstaller)
        self.assertIn("No se modificó ninguna tarjeta SD", linux_uninstaller)

        windows_uninstaller = (MODULE_PATH.parents[1] / "site" / "uninstall-windows.ps1").read_text(encoding="utf-8")
        self.assertIn('Join-Path $env:LOCALAPPDATA "CDMXRadxaFlash"', windows_uninstaller)
        self.assertIn("Get-CimInstance Win32_Process", windows_uninstaller)
        self.assertIn("No se modificó ninguna tarjeta SD", windows_uninstaller)

    def test_job_reservation_is_atomic(self):
        state = imager.JobState()
        self.assertTrue(state.reserve())
        self.assertFalse(state.reserve())
        state.update(running=False)
        self.assertTrue(state.reserve())

    def test_public_site_bridge_is_origin_locked(self):
        server = imager.ImagerServer(("127.0.0.1", 0), "test-token")
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        port = server.server_address[1]
        try:
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
            connection.request("GET", "/")
            response = connection.getresponse()
            self.assertEqual(response.status, 302)
            self.assertEqual(response.getheader("Location"), imager.PUBLIC_SITE_URL)
            self.assertEqual(response.read(), b"")
            connection.close()

            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
            connection.request("GET", "/api/session", headers={"Origin": imager.TRUSTED_WEB_ORIGIN})
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(response.getheader("Access-Control-Allow-Origin"), imager.TRUSTED_WEB_ORIGIN)
            self.assertEqual(response.getheader("Access-Control-Allow-Private-Network"), "true")
            self.assertEqual(__import__("json").loads(response.read())["token"], "test-token")
            connection.close()

            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
            connection.request("GET", "/api/session", headers={"Origin": "https://example.invalid"})
            response = connection.getresponse()
            self.assertEqual(response.status, 403)
            response.read()
            connection.close()

            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
            connection.request(
                "OPTIONS",
                "/api/flash",
                headers={
                    "Origin": imager.TRUSTED_WEB_ORIGIN,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Private-Network": "true",
                },
            )
            response = connection.getresponse()
            self.assertEqual(response.status, 204)
            self.assertIn("POST", response.getheader("Access-Control-Allow-Methods", ""))
            response.read()
            connection.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
