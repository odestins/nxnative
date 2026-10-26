"""Exercise replacement and rollback without signing or modifying installed apps."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("build_app", Path(__file__).parents[1] / "build_app.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.bundle("built/reSwitch.app", "new")
        self.destination = self.bundle("installed/reSwitch.app", "old")
        self.previous = self.root / "archive"

    def bundle(self, path, marker, identity=build.APP_ID):
        root = self.root / path
        (root / "Contents").mkdir(parents=True)
        with (root / "Contents/Info.plist").open("wb") as output:
            plistlib.dump({"CFBundleIdentifier": identity}, output)
        (root / "marker").write_text(marker)
        (root / "marker").chmod(0o755)
        return root

    def install(self, verify=lambda _: None):
        return build.install_bundle(self.source, self.destination, self.previous, verify)

    def test_success_preserves_executable_mode_and_previous_app(self):
        backup = self.install()
        self.assertEqual((self.destination / "marker").read_text(), "new")
        self.assertEqual((backup / "marker").read_text(), "old")
        self.assertEqual((self.destination / "marker").stat().st_mode & 0o777, 0o755)

    def test_verification_failure_never_moves_current_app(self):
        def reject(_):
            raise ValueError("Invalid signature")
        with self.assertRaises(ValueError):
            self.install(reject)
        self.assertEqual((self.destination / "marker").read_text(), "old")
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_failed_swap_restores_current_app(self):
        rename = Path.rename
        def fail_stage(path, destination):
            if ".installing-" in path.name:
                raise OSError("Interrupted replacement")
            return rename(path, destination)
        with patch.object(Path, "rename", fail_stage), self.assertRaises(OSError):
            self.install()
        self.assertEqual((self.destination / "marker").read_text(), "old")
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_unavailable_archive_retains_sibling_backup(self):
        with patch.object(build.shutil, "move", side_effect=OSError("Archive unavailable")):
            backup = self.install()
        self.assertEqual((self.destination / "marker").read_text(), "new")
        self.assertEqual((backup / "marker").read_text(), "old")
        self.assertEqual(backup.parent, self.destination.parent)

    def test_unrelated_app_is_never_replaced(self):
        with (self.destination / "Contents/Info.plist").open("wb") as output:
            plistlib.dump({"CFBundleIdentifier": "com.example.other"}, output)
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual((self.destination / "marker").read_text(), "old")


if __name__ == "__main__":
    unittest.main()
