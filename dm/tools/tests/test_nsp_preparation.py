"""Untrusted package metadata and preflight failures must stop before expensive work."""
from contextlib import ExitStack
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('build_ipa_from_nsp', REPO / 'scripts/build_ipa_from_nsp.py')
nsp = importlib.util.module_from_spec(spec); spec.loader.exec_module(nsp)
sys.path.insert(0, str(REPO / 'dm/games'))
import game
import profile_guess as pg


class PackageBounds(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def package(self, count, strings, entries=b'', body=b''):
        p = self.root / 'fixture.nsp'
        p.write_bytes(b'PFS0' + struct.pack('<III', count, len(strings), 0) + entries + strings + body)
        return p

    def test_truncated_magic_header(self):
        p = self.root / 'short.nsp'; p.write_bytes(b'PFS0')
        with self.assertRaisesRegex(nsp.BuildError, 'truncated PFS0 header'): nsp.pfs0_names(p)

    def test_huge_counts_rejected_before_directory_read(self):
        p = self.package(0xffffffff, b'')
        with self.assertRaisesRegex(nsp.BuildError, 'limit'): nsp.pfs0_names(p)

    def test_huge_string_table_rejected(self):
        p = self.root / 'huge.nsp'; p.write_bytes(b'PFS0' + struct.pack('<III', 0, 0xffffffff, 0))
        with self.assertRaisesRegex(nsp.BuildError, 'limit'): nsp.pfs0_names(p)

    def test_truncated_directory_rejected(self):
        with self.assertRaisesRegex(nsp.BuildError, 'truncated PFS0 directory'): nsp.pfs0_names(self.package(1, b''))

    def test_name_offset_and_missing_terminator_rejected(self):
        for offset, strings in ((10, b'a\0'), (0, b'abc'), (0, b'\0'), (0, b'a' * 1024 + b'\0')):
            with self.subTest(offset=offset, length=len(strings)), self.assertRaisesRegex(nsp.BuildError, 'entry name'):
                nsp.pfs0_names(self.package(1, strings, struct.pack('<QQII', 0, 0, offset, 0)))

    def test_truncated_payload_rejected(self):
        with self.assertRaisesRegex(nsp.BuildError, 'beyond the package'):
            nsp.pfs0_names(self.package(1, b'content.nca\0', struct.pack('<QQII', 0, 100, 0, 0), b'short'))

    def test_valid_ticket_overrides_filename_tag(self):
        ticket = b'010015100b5140000000000000000011.tik'
        p = self.package(1, ticket + b'\0', struct.pack('<QQII', 0, 0, 0, 0))
        renamed = p.with_name('Wrong [0100AC601DCA8000].NSP'); p.rename(renamed)
        self.assertEqual(nsp.title_of(renamed), 0x010015100B514000)
        with mock.patch.object(nsp, 'say'):
            self.assertEqual(nsp.scan_nsps(self.root)[1]['base'], renamed)

    def test_malformed_update_does_not_hide_valid_update(self):
        app = 0x010015100B514000
        base = self.root / f'Base [{app:016X}].xci'; base.write_bytes(bytes(0x100) + b'HEAD')
        update = self.root / f'Update [{app | 0x800:016X}].nsp'
        update.write_bytes(b'PFS0' + bytes(12))
        malformed = self.root / f'Bad [{app | 0x800:016X}].nsp'; malformed.write_bytes(b'PFS0')
        (self.root / 'folder.nsp').mkdir()
        with mock.patch.object(nsp, 'say') as say:
            _, family = nsp.scan_nsps(self.root)
        self.assertEqual(family['updates'], [(None, update)])
        self.assertEqual(nsp.nsp_versions(family, {'v65536': {}})['v65536'], update)
        self.assertTrue(any('truncated PFS0 header' in c.args[0] for c in say.call_args_list))


class Npdm(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'main.npdm'

    def test_instruction_flag_not_address_space_flag(self):
        for flags, native in ((0x3f, True), (0x01, True), (0x04, False), (0, False)):
            data = bytearray(0x80); data[:4] = b'META'; data[0xc] = flags; self.path.write_bytes(data)
            self.assertEqual(pg.aarch64(self.path), native)

    def test_missing_metadata_retains_previous_path(self):
        self.assertTrue(pg.aarch64(self.path))

    def test_short_header_has_readable_error(self):
        self.path.write_bytes(b'META')
        with self.assertRaisesRegex(ValueError, 'truncated META header'): pg.aarch64(self.path)

    def test_survey_stops_before_reading_32bit_module_tables(self):
        app = 0x010015100B514000; folder = self.path.parent
        base = folder / 'fixture.nsp'; base.touch()
        def extract(cmd, log, **kw):
            out = cmd[4]; (out / 'ExeFS').mkdir(parents=True)
            data = bytearray(0x80); data[:4] = b'META'; data[0xc] = 0x04
            (out / 'ExeFS/main.npdm').write_bytes(data)
            log.parent.mkdir(parents=True); log.write_text('')
        with mock.patch.object(nsp, 'PROG', mock.Mock()), mock.patch.object(nsp, 'say'), \
                mock.patch.object(nsp, 'pg', pg, create=True), mock.patch.object(nsp, 'nacp', SimpleNamespace(name=lambda p: 'Fixture'), create=True), \
                mock.patch.object(nsp, 'build_nx_extract', return_value=folder / 'nx_extract'), mock.patch.object(nsp, 'run', side_effect=extract), \
                mock.patch.object(pg, 'facts_of') as facts:
            with self.assertRaisesRegex(nsp.BuildError, '32-bit ARM program.*AArch64'):
                nsp.survey(folder, app, {'base': base, 'updates': []}, folder / 'keys', REPO, sys.executable, {})
        facts.assert_not_called()


class CacheAndPreflight(unittest.TestCase):
    def test_sdk_patch_change_invalidates_unnamed_build(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); (root / 'dm/tools').mkdir(parents=True); (root / 'dm/games/other').mkdir(parents=True)
            sdk = root / 'dm/tools/sdk_patches.py'; sdk.write_text('SDK_RULE = 1\n')
            other = root / 'dm/games/other/patches.py'; other.write_text('unrelated = 2\n')
            main = root / 'main'; main.write_bytes(bytes(range(0x80)))
            files = nsp.patch_files(root, root, ['main'])
            self.assertEqual(files, [sdk])
            before = nsp.fingerprint(('files', files))
            sdk.write_text('SDK_RULE = 2\n')
            self.assertNotEqual(before, nsp.fingerprint(('files', files)))

    def test_missing_environment_stops_before_unknown_game_survey(self):
        with tempfile.TemporaryDirectory() as d, ExitStack() as stack:
            root = Path(d); keys = root / 'prod.keys'; keys.touch()
            stack.enter_context(mock.patch.object(nsp, 'check_native_python'))
            stack.enter_context(mock.patch.object(nsp, 'scan_nsps', return_value=(1, {'base': root / 'base.nsp', 'updates': [], 'dlc': []})))
            stack.enter_context(mock.patch.object(game, 'by_title', return_value=None))
            stack.enter_context(mock.patch.object(nsp, 'check_prereqs', side_effect=nsp.BuildError('toolchain unavailable')))
            survey = stack.enter_context(mock.patch.object(nsp, 'survey'))
            with self.assertRaisesRegex(nsp.BuildError, 'toolchain unavailable'):
                nsp.main(nsp.parse_args([str(root), '-k', str(keys), '--progress', 'off']))
            survey.assert_not_called()


if __name__ == '__main__': unittest.main()
