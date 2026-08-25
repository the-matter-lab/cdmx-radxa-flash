import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).parents[1] / "device" / "network" / "network_portal.py"
SPEC = importlib.util.spec_from_file_location("network_portal", MODULE_PATH)
assert SPEC and SPEC.loader
portal = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(portal)


class NetworkPortalTests(unittest.TestCase):
    def test_captive_portal_metadata(self):
        self.assertEqual(portal.portal_url(7), "http://10.42.7.1:8080/")
        self.assertEqual(
            portal.captive_api(7),
            '{"captive":true,"user-portal-url":"http://10.42.7.1:8080/"}',
        )
        self.assertEqual(portal.portal_url(11), "http://10.42.11.1:8080/")
        self.assertEqual(portal.identity_hostname(10), "equipo10")
        self.assertEqual(portal.identity_hostname(11), "equipo11")
        self.assertEqual(portal.identity_hostname(98), "equipo98")
        self.assertEqual(portal.portal_url("admin"), "http://10.42.99.1:8080/")
        self.assertEqual(
            portal.captive_api("admin"),
            '{"captive":true,"user-portal-url":"http://10.42.99.1:8080/"}',
        )
        self.assertEqual(portal.identity_hostname("admin"), "admin")
        with self.assertRaises(ValueError):
            portal.validate_identity(99)

    def test_split_nmcli_escaped_colons(self):
        self.assertEqual(
            portal.split_nmcli(r"Cafe\: downstairs:87:WPA2"),
            ["Cafe: downstairs", "87", "WPA2"],
        )

    def test_credentials(self):
        portal.validate_credentials("Venue WiFi", "12345678", False)
        portal.validate_credentials("Open", "", True)
        with self.assertRaises(ValueError):
            portal.validate_credentials("", "12345678", False)
        with self.assertRaises(ValueError):
            portal.validate_credentials("Venue", "short", False)
        with self.assertRaises(ValueError):
            portal.validate_credentials("x" * 33, "12345678", False)

    def test_allowed_client(self):
        self.assertTrue(portal.allowed_client("10.42.0.22", 0))
        self.assertTrue(portal.allowed_client("10.55.0.2", 0))
        self.assertTrue(portal.allowed_client("10.42.7.22", 7))
        self.assertTrue(portal.allowed_client("10.55.7.2", 7))
        self.assertTrue(portal.allowed_client("10.42.11.22", 11))
        self.assertTrue(portal.allowed_client("10.55.11.2", 11))
        self.assertTrue(portal.allowed_client("10.42.98.22", 98))
        self.assertTrue(portal.allowed_client("10.55.98.2", 98))
        self.assertTrue(portal.allowed_client("10.42.99.22", "admin"))
        self.assertTrue(portal.allowed_client("10.55.99.2", "admin"))
        self.assertTrue(portal.allowed_client("127.0.0.1", 7))
        self.assertFalse(portal.allowed_client("10.42.8.22", 7))
        self.assertFalse(portal.allowed_client("192.168.1.2", 7))


if __name__ == "__main__":
    unittest.main()
