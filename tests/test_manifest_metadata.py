import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class ManifestMetadataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / "site" / "manifest.json").read_text())

    def test_simulator_uses_production_https_url(self):
        self.assertEqual(
            self.manifest["simulator"]["url"],
            "https://radxa-simulator.mantilla.ca",
        )

    def test_simulator_sources_are_immutable_commits(self):
        simulator = self.manifest["simulator"]
        self.assertRegex(simulator["source_commit"], r"^[0-9a-f]{40}$")
        self.assertRegex(simulator["bayesopt_commit"], r"^[0-9a-f]{40}$")
        self.assertRegex(
            simulator["bayesopt_source"],
            r"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$",
        )

    def test_manifest_image_checksum_is_immutable(self):
        self.assertTrue(re.fullmatch(r"[0-9a-f]{128}", self.manifest["image"]["sha512"]))


if __name__ == "__main__":
    unittest.main()
