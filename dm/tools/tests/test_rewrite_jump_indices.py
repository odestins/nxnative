"""Recognize bounded jump-table indices without accepting an unrelated check."""
import ast
from pathlib import Path
import re
import struct
import unittest

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM


class ZeroExtendedJumpIndex(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(__file__).resolve().parents[1] / 'patch_nso.py'
        tree = ast.parse(source.read_text())
        functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)
                     and node.name == 'jump_offsets']
        cls.scope = dict(re=re, struct=struct)
        exec(compile(ast.Module(body=functions, type_ignores=[]), str(source), 'exec'), cls.scope)

    def targets(self, compare=0x7100111f, branch=0x54000248, extra=()):
        # adrp/add x16 -> table at 0x80; cmp w8,#4; b.hi; zero-extend x8;
        # load the signed table entry, add its base, and branch through x18.
        words = [0x90000010, 0x91020210, compare, branch, *extra,
                 0x92407d12, 0xb8b27a12, 0x8b100252, 0xd61f0240]
        code = b''.join(struct.pack('<I', word) for word in words)
        image = bytearray(256)
        image[:len(code)] = code
        struct.pack_into('<5i', image, 0x80, 64, 68, 72, 76, 80)
        decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        decoder.detail = True
        instructions = list(decoder.disasm(code, 0))
        self.scope['IMG'] = image
        return self.scope['jump_offsets'](instructions, len(instructions) - 1)

    def test_checked_low_word_is_the_zero_extended_index(self):
        self.assertEqual(self.targets(), [192, 196, 200, 204, 208])

    def test_comparison_on_another_register_is_rejected(self):
        self.assertIsNone(self.targets(compare=0x7100113f))  # cmp w9,#4

    def test_missing_unsigned_bounds_branch_is_rejected(self):
        self.assertIsNone(self.targets(branch=0xd503201f))  # nop

    def test_index_changed_after_check_is_rejected(self):
        self.assertIsNone(self.targets(extra=(0x11000508,)))  # add w8,w8,#1


if __name__ == '__main__':
    unittest.main()
