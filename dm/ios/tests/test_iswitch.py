"""iSwitch cards, command boundaries, and pipeline integration; no game data needed."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/ios/tools'))
sys.path.insert(0, str(REPO / 'scripts'))
import iswitch_manifest as cards
import iswitch
import build_ipa_from_nsp as pipeline


class CardTests(unittest.TestCase):
    def test_export_atomic_without_keys_or_source_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            icon = root / 'icon.jpg'; icon.write_bytes(b'cover fixture')
            destination = root / 'game.iswitch'
            for packaged in [True, False]:
                cards.write_card(destination, title_id='010015100B514000', name='Test Game',
                                 version='1.2.1', bundle_id='org.example.game', icon=icon,
                                 profiled=False, packaged=packaged, revision='abc123')
                result = json.loads(destination.read_text())
                self.assertEqual(result['launchURL'], 'nxnative-010015100b514000://launch')
                self.assertEqual(result['buildState'], 'packaged' if packaged else 'project')
                self.assertEqual(result['compatibility'], 'experimental')
                self.assertNotIn(folder, destination.read_text())
                self.assertNotIn('keys', destination.read_text())
                self.assertFalse(list(root.glob('.iswitch-*')))

    def test_failed_export_preserves_existing_card(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / 'game.iswitch'; destination.write_text('original')
            with self.assertRaises(ValueError):
                cards.write_card(destination, title_id='../bad', name='Bad', version='1', bundle_id='org.example.game')
            self.assertEqual(destination.read_text(), 'original')

    def test_command_handles_shell_metacharacters_as_arguments(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'Game $(touch NEVER) `unsafe`'; root.mkdir()
            (root / 'base.nsp').write_bytes(b'fixture')
            keys = Path(folder) / 'prod.keys'; keys.write_text('synthetic fixture')
            with patch.object(iswitch.shutil, 'disk_usage', return_value=type('Disk', (), {'free': 100 * 1024**3})()):
                _, command = iswitch.preparation_command(root, keys, xcode=True)
            self.assertIn(str(root.resolve()), command)
            self.assertIn('--prepare-xcode', command)
            self.assertIn('--iswitch-card', command)
            self.assertEqual(command[command.index('--keys') + 1], str(keys.resolve()))

    def test_progress_reads_the_isolated_generated_project(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            work = root / 'work'
            (work / 'xcode/Gen/src').mkdir(parents=True)
            (work / 'xcode/Gen/src/host.c').touch()
            (work / 'xcode/Sources').mkdir()
            (work / 'xcode/Sources/main.m').touch()
            watch = pipeline.IpaWatch(REPO, work, root / 'game.ipa')
            with patch.object(pipeline, 'PROG') as progress:
                watch.line('[12:00:00] xcodebuild (Release)')
                self.assertEqual(progress.set.call_args.kwargs['total'], 4)

    def test_repository_game_paths_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'outside the source'):
            iswitch.preparation_command(REPO, REPO / 'prod.keys')

    def test_missing_keys_rejected_without_reading_contents(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'prod.keys'):
                iswitch.preparation_command(folder, Path(folder) / 'missing.keys')

    def test_flag_is_opt_in_and_catalog_is_current(self):
        self.assertFalse(pipeline.parse_args([]).iswitch_card)
        self.assertTrue(pipeline.parse_args(['--iswitch-card']).iswitch_card)
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'catalog.json'
            iswitch.generate_catalog(output)
            self.assertEqual(json.loads(output.read_text()), json.loads((REPO / 'launcher/Resources/catalog.json').read_text()))

    def test_game_project_declares_the_expected_scheme(self):
        # Render the actual XcodeGen template to exercise environment substitution and plist types.
        if not iswitch.shutil.which('xcodegen'):
            self.skipTest('XcodeGen is not installed')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for p in ['Sources', 'Gen/dm', 'Gen/Assets.xcassets', 'Gen/src', 'Gen/main']:
                (root / p).mkdir(parents=True, exist_ok=True)
            (root / 'Gen/embed.S').touch(); (root / 'Gen/main/main.c').touch(); (root / 'Gen/dm.xcconfig').touch()
            (root / 'project.yml').write_text((REPO / 'dm/ios/project.yml').read_text())
            env = dict(os.environ, DM_BUNDLE_ID='org.example.game', DM_DISPLAY_NAME='Game', DM_SCHEME_NAME='Game',
                       DM_LAUNCH_SCHEME='nxnative-010015100b514000', DM_APP_VERSION='1.0', DM_APP_CATEGORY='public.app-category.games',
                       DM_TEAM_ID='0000000000', DM_SHOW_FPS='YES', DM_LANG='en-US',
                       DM_SAVE_SYNC_PACKAGE=str(REPO / 'cloudsave'))
            subprocess.run(['xcodegen', 'generate', '-q'], cwd=root, env=env, check=True, capture_output=True)
            import plistlib
            plist = plistlib.loads((root / 'Gen/Info.plist').read_bytes())
            self.assertEqual(plist['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['nxnative-010015100b514000'])


if __name__ == '__main__': unittest.main()
