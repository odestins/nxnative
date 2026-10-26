import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "tools/gen_cloud_entitlements.py"


class CloudEntitlementTests(unittest.TestCase):
    def test_cloud_configuration_preserves_game_memory_capability(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Game.entitlements"
            original = {"com.apple.developer.kernel.increased-memory-limit": True, "get-task-allow": True}
            path.write_bytes(plistlib.dumps(original))
            subprocess.run([sys.executable, str(SCRIPT), str(path), "iCloud.com.odestins.iswitch"], check=True)
            value = plistlib.loads(path.read_bytes())
            self.assertTrue(value["com.apple.developer.kernel.increased-memory-limit"])
            self.assertTrue(value["get-task-allow"])
            self.assertEqual(value["com.apple.developer.ubiquity-kvstore-identifier"], "$(TeamIdentifierPrefix)com.odestins.iswitch")
            self.assertEqual(value["com.apple.developer.icloud-container-identifiers"], ["iCloud.com.odestins.iswitch"])
            before = path.read_bytes()
            invalid = subprocess.run([sys.executable, str(SCRIPT), str(path), "../wrong"], capture_output=True)
            self.assertNotEqual(invalid.returncode, 0)
            self.assertEqual(path.read_bytes(), before)
