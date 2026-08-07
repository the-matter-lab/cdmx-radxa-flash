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
        html = imager.UI_PATH.read_text(encoding="utf-8")
        self.assertIn("role=\"progressbar\"", html)
        self.assertIn("'admin'", html)
        self.assertIn("IDENTITIES", html)
        self.assertIn("__CDMX_TOKEN__", html)
        self.assertNotIn("/api/repair", html)

        public_html = (MODULE_PATH.parents[1] / "site" / "index.html").read_text(encoding="utf-8")
        self.assertIn("http://127.0.0.1:8766", public_html)
        self.assertIn("/api/session", public_html)
        self.assertIn("/api/flash", public_html)
        self.assertIn("IDENTITIES", public_html)
        self.assertIn("Volver a intentar", public_html)
        self.assertIn(imager.PUBLIC_SITE_URL, (MODULE_PATH.parents[1] / "host" / "start-imager.command").read_text())

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
