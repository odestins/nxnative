"""Exercise destructive-import boundaries with synthetic keys and archives."""
import io
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/ios/tools'))
sys.path.insert(0, str(REPO / 'scripts'))
import iswitch_assets as assets
import iswitch

KEYS = ('header_key = ' + 'ab' * 32 + '\nmaster_key_00 = ' + 'cd' * 16 + '\n').encode()
NCA = 'a' * 32 + '.nca'

class AssetTests(unittest.TestCase):
    def test_key_replacement_is_private_and_invalid_input_preserves_old_file(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root / 'input.keys'; target = root / 'private/prod.keys'
            source.write_bytes(KEYS)
            self.assertEqual(assets.import_keys(source, target), 2)
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            source.write_bytes(b'invalid data')
            with self.assertRaises(ValueError): assets.import_keys(source, target)
            self.assertEqual(target.read_bytes(), KEYS)
            self.assertFalse(list(target.parent.glob('.keys-*')))

    def test_key_zip_is_bounded_and_unrelated_entries_are_not_extracted(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root / 'keys.zip'; target = root / 'prod.keys'
            with zipfile.ZipFile(source, 'w') as archive:
                archive.writestr('keys/prod.keys', KEYS)
                archive.writestr('../../Setup.exe', b'never executed or extracted')
            self.assertEqual(assets.import_keys(source, target), 2)
            with zipfile.ZipFile(source, 'a') as archive: archive.writestr('duplicate/prod.keys', KEYS)
            with self.assertRaises(ValueError): assets.import_keys(source, target)
            self.assertEqual(target.read_bytes(), KEYS)

    def test_firmware_rejects_traversal_symlinks_installers_and_duplicates(self):
        for names in [['../' + NCA], ['/absolute/' + NCA], ['Setup.exe'], [NCA, 'other/' + NCA]]:
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, 'w') as archive:
                for name in names: archive.writestr(name, bytes(1024))
            with zipfile.ZipFile(io.BytesIO(buffer.getvalue())) as archive:
                with self.assertRaises(ValueError): assets.firmware_entries(archive)
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            info = zipfile.ZipInfo(NCA); info.create_system = 3; info.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(info, bytes(1024))
        with zipfile.ZipFile(io.BytesIO(buffer.getvalue())) as archive:
            with self.assertRaises(ValueError): assets.firmware_entries(archive)

    def test_firmware_valid_container_counts_and_expansion_limits(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive: archive.writestr('Firmware/' + NCA, bytes(1024))
        with zipfile.ZipFile(io.BytesIO(buffer.getvalue())) as archive:
            entries, size = assets.firmware_entries(archive)
            self.assertEqual((len(entries), size), (1, 1024))
            entries[0].file_size = 3 * 1024**3
            with self.assertRaises(ValueError): assets.firmware_entries(archive)

    def test_homebrew_dotnet_launcher_uses_runtime_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root / 'bin').mkdir(); (root / 'libexec/host/fxr').mkdir(parents=True)
            binary = root / 'bin/dotnet'; binary.touch()
            with patch.dict(os.environ, {}, clear=True), patch.object(iswitch.shutil, 'which', return_value=str(binary)):
                self.assertEqual(iswitch.tool_environment()['DOTNET_ROOT'], str((root / 'libexec').resolve()))

if __name__ == '__main__': unittest.main()
