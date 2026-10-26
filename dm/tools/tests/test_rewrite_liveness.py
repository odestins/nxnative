"""Check the observation gate's caller-saved register proof with real AArch64 instructions."""
import ast
from pathlib import Path
import re
import struct
import unittest

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM


class ObservationLiveness(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(__file__).resolve().parents[1] / 'patch_nso.py'
        tree = ast.parse(source.read_text())
        functions = [n for n in tree.body if isinstance(n, ast.FunctionDef)
                     and n.name in {'dis', 'num', 'regset', 'scratch_dead'}]
        decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        decoder.detail = True
        cls.scope = dict(md=decoder, re=re, struct=struct)
        exec(compile(ast.Module(body=functions, type_ignores=[]), str(source), 'exec'), cls.scope)

    def proof(self, *words):
        image = b''.join(struct.pack('<I', word) for word in words)
        self.scope.update(IMG=image, TEXT_END=len(image))
        return self.scope['scratch_dead'](0)

    def test_return_allows_caller_saved_clobbers(self):
        # GYLT BaseAllocator's epilogue: mov x0, x19; ldr x19; ldp fp/lr; ret.
        self.assertTrue(self.proof(0xaa1303e0, 0xf9400bf3, 0xa8c27bfd, 0xd65f03c0))

    def test_live_scratch_input_is_rejected(self):
        self.assertFalse(self.proof(0xaa0903e0, 0xd65f03c0))  # mov x0, x9; ret
        self.assertFalse(self.proof(0xd65f0120))  # ret x9

    def test_written_scratch_and_call(self):
        self.assertTrue(self.proof(0xd2800029, 0xaa0903e0, 0xd65f03c0))
        self.assertTrue(self.proof(0xaa1303e0, 0x94000004))

    def test_branch_and_unbounded_tail_are_not_proofs(self):
        self.assertFalse(self.proof(0x14000001, 0xd65f03c0))
        self.assertFalse(self.proof(0xd503201f))


if __name__ == '__main__':
    unittest.main()
