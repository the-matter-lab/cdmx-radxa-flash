from __future__ import annotations

import importlib.util
import http.client
from pathlib import Path
import tempfile
import threading
import unittest


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
        for invalid in (-1, 10, "0", True, None):
            with self.assertRaises(ValueError):
                imager.validate_team(invalid)

    def test_raw_disk_path_has_no_shell_escapes(self):
        original = imager.HOST_SYSTEM
        try:
            imager.HOST_SYSTEM = "Darwin"
            self.assertEqual(imager.raw_disk_path("/dev/disk10"), "/dev/rdisk10")
            with self.assertRaises(ValueError):
                imager.raw_disk_path("/dev/disk10s1")
            imager.HOST_SYSTEM = "Windows"
            self.assertEqual(imager.raw_disk_path(r"\\.\PhysicalDrive12"), r"\\.\PhysicalDrive12")
            with self.assertRaises(ValueError):
                imager.raw_disk_path(r"C:\\")
        finally:
            imager.HOST_SYSTEM = original

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

    def test_ui_has_all_teams_and_progress_semantics(self):
        public_html = (MODULE_PATH.parents[1] / "site" / "index.html").read_text(encoding="utf-8")
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
        self.assertIn("SOURCE_COMMIT=3ecbf3467f8fb5f140d89336b798ea17d47abbcd", mac_launcher)
        self.assertIn("ARCHIVE_SHA256=65efe3a87175a1aab45e29b9ec2702bffa29de6ff8046b515cf5bc411e4fbee4", mac_launcher)
        self.assertIn("codeload.github.com/the-matter-lab/cdmx-radxa-flash", mac_launcher)
        self.assertIn("shasum -a 256", mac_launcher)

        linux_launcher = (MODULE_PATH.parents[1] / "site" / "start-linux.sh").read_text(encoding="utf-8")
        self.assertIn("SOURCE_COMMIT=3ecbf3467f8fb5f140d89336b798ea17d47abbcd", linux_launcher)
        self.assertIn("sha256sum", linux_launcher)
        self.assertIn("exec sudo", linux_launcher)

        windows_launcher = (MODULE_PATH.parents[1] / "site" / "start-windows.ps1").read_text(encoding="utf-8")
        self.assertIn('$SourceCommit = "3ecbf3467f8fb5f140d89336b798ea17d47abbcd"', windows_launcher)
        self.assertIn("Get-FileHash -Algorithm SHA256", windows_launcher)
        self.assertIn("WindowsBuiltInRole]::Administrator", windows_launcher)

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
