"""Synthetic fixtures for RFX and Unreal inline shader discovery; no game data."""
import os
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch
import zlib

import lz4.block

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'gfx/tools'))
with patch.dict(os.environ, {'DM_GAME': '010015100B514000', 'DM_GAMES_DIR': str(Path(__file__).resolve().parents[2] / 'games')}):
    import shader_split as split
import uepak


def shader(stage='vs'):
    code = bytearray(0x100)
    code[:4] = split.CS_MAGIC if stage == 'cs' else split.GFX_MAGIC
    struct.pack_into('<I', code, 0x30, {'vs': 1, 'ps': 5, 'cs': 0}[stage] << 10)
    control = bytearray(0x880)
    control[:4] = split.CTL_MAGIC
    struct.pack_into('<I', control, 0x20, len(control))
    struct.pack_into('<I', control, 0x704, len(code))
    return bytes(control), bytes(code)


def lslg(stage='vs'):
    ctl, code = shader(stage)
    return b'LSLG' + {'vs': b'SV', 'ps': b'SP', 'cs': b'SC'}[stage] + bytes(16) + struct.pack('<I', len(code)) + code + struct.pack('<I', len(ctl)) + ctl + bytes(24)


def rfx(stages):
    b = b'RFX ' + struct.pack('<III', 9, 1, 4) + b'test' + bytes(4) + struct.pack('<I', len(stages))
    for stage in stages:
        ctl, code = shader(stage)
        b += b'effect metadata' + code + ctl
    return b


class Formats(unittest.TestCase):
    def test_lz50_literal_and_overlapping_backreferences(self):
        # Three literal bytes, then distance 3 / length 6. The flag is negated.
        wrap = lambda n, b: b'\x50\0\0\0' + n.to_bytes(4, 'big') + b
        self.assertEqual(split.camelot_lz50(wrap(9, b'\xf0abc\x36\0'), 'short'), b'abcabcabc')
        # Extended lengths: 16 + byte, or 272 + little-endian word.
        self.assertEqual(split.camelot_lz50(wrap(21, b'\xc0x\x10\0\x04'), 'extended'), b'x' * 21)
        self.assertEqual(split.camelot_lz50(wrap(530, b'\xc0x\x11\0\x01\x01'), 'long'), b'x' * 530)
        for data in (wrap(9, b'\xf0abc\x36'), wrap(9, b'\x80\x36\0'), wrap(8, b'\xf0abc\x36\0'), wrap(1, b'\x80\0\0\0')):
            with self.assertRaises(SystemExit): split.camelot_lz50(data, 'invalid')

    def test_lz50_shaders_inside_narc(self):
        payload = rfx(['vs', 'ps'])
        packed = b'\x50\0\0\0' + len(payload).to_bytes(4, 'big')
        packed += b''.join(b'\0' + payload[i:i + 8] for i in range(0, len(payload), 8))
        found = []
        split.scan_blob(self.narc([packed]), 'fixture', found)
        self.assertEqual([item[1] for item in found], ['vs', 'ps'])

    @staticmethod
    def narc(entries):
        data = b''.join(entries)
        offsets, pos = [], 0
        for entry in entries:
            offsets.append(struct.pack('<II', pos, pos + len(entry)))
            pos += len(entry)
        fat = struct.pack('<HH', len(entries), 0) + b''.join(offsets)
        chunks = b'BTAF' + struct.pack('<I', len(fat) + 8) + fat
        chunks += b'GMIF' + struct.pack('<I', len(data) + 8) + data
        return b'NARC\xfe\xff\x00\x00' + struct.pack('<IHH', 16 + len(chunks), 16, 2) + chunks

    def test_narc_plain_and_compressed_shader_entries(self):
        payload = rfx(['vs', 'ps'])
        compressor = zlib.compressobj(wbits=-15)
        packed = b'\x30' + len(payload).to_bytes(4, 'big') + bytes(11)
        packed += compressor.compress(payload) + compressor.flush()
        archive = self.narc([b'plain file', packed])
        self.assertEqual(list(split.narc_members(archive, 'fixture')), [('0', b'plain file'), ('1', payload)])
        found = []
        split.scan_blob(archive, 'fixture', found)
        self.assertEqual([item[1] for item in found], ['vs', 'ps'])

    def test_narc_truncation_bad_offsets_and_decompression_length(self):
        archive = self.narc([b'plain file'])
        with self.assertRaises(SystemExit): list(split.narc_members(archive[:-1], 'truncated'))
        bad = bytearray(archive)
        struct.pack_into('<I', bad, 32, 0xffffffff)  # first entry end exceeds GMIF
        with self.assertRaises(SystemExit): list(split.narc_members(bad, 'bad entry'))
        compressor = zlib.compressobj(wbits=-15)
        packed = b'\x30' + (2).to_bytes(4, 'big') + bytes(11)
        packed += compressor.compress(b'longer than declared') + compressor.flush()
        with self.assertRaises(SystemExit): list(split.narc_members(self.narc([packed]), 'bad size'))

    def test_embedded_nvn_without_container(self):
        raw = b'module data'
        for stage in ('vs', 'ps', 'cs'):
            ctl, code = shader(stage)
            raw += code + ctl + b'more data'
        self.assertEqual([r[1] for r in split.embedded_nvn_shaders(raw, 'main')], ['vs', 'ps', 'cs'])
        ctl, code = shader('vs')
        self.assertEqual(split.embedded_nvn_shaders(code + ctl[:-1], 'truncated'), [])
        bad = bytearray(ctl)
        struct.pack_into('<I', bad, 0x704, 0xffffffff)
        self.assertEqual(split.embedded_nvn_shaders(code + bad, 'bad length'), [])

    def test_rfx_graphics_compute_and_empty(self):
        self.assertEqual([x[1] for x in split.rfx_shaders(rfx(['vs', 'ps', 'cs']), 'fixture')], ['vs', 'ps', 'cs'])
        self.assertEqual(split.rfx_shaders(rfx([]), 'empty'), [])

    def test_rfx_truncation_and_invalid_sections(self):
        valid = rfx(['vs'])
        for cut in (5, 10, 15, 22, len(valid) - 1, len(valid) - 1000):
            with self.subTest(cut=cut), self.assertRaises(SystemExit):
                split.rfx_shaders(valid[:cut], 'truncated')
        invalid = bytearray(valid)
        struct.pack_into('<I', invalid, invalid.index(split.CTL_MAGIC) + 0x704, 0xffffffff)
        with self.assertRaises(SystemExit): split.rfx_shaders(invalid, 'bad code length')

    def test_unreal_all_inline_compressions(self):
        out = []
        data = b''
        for stage, encode in (('vs', lambda s: s), ('ps', zlib.compress), ('cs', lambda s: lz4.block.compress(s, store_size=False))):
            b = encode(lslg(stage))
            data += b'metadata' + struct.pack('<I', len(b)) + b
        split.ue_inline_shaders(data, 'mixed', out)
        self.assertCountEqual([x[1] for x in out], ['vs', 'ps', 'cs'])
        self.assertEqual(len(out), 3)

    def test_incomplete_and_incidental_lslg_are_ignored(self):
        valid = lslg()
        self.assertIsNone(uepak.lslg(b'LSLG' + bytes(12) + split.CTL_MAGIC))
        self.assertIsNone(uepak.lslg(valid[:-100]))
        block = lz4.block.compress(valid, store_size=False)
        out = []
        split.ue_inline_shaders(b'assetLSLGnoise' + struct.pack('<I', len(block) + 10) + block, 'truncated', out)
        self.assertEqual(out, [])

    def test_lz4_extended_first_literal(self):
        # A literal-only LZ4 block with more than one length-extension byte.
        raw = lslg(); n = len(raw) - 15
        block = bytes([0xf0]) + bytes([255]) * (n // 255) + bytes([n % 255]) + raw
        out = []
        split.ue_inline_shaders(struct.pack('<I', len(block)) + block, 'literal only', out)
        self.assertEqual([x[1] for x in out], ['vs'])


if __name__ == '__main__': unittest.main()
