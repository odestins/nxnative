"""Only actual iOS shader builds require the iOS Metal compiler."""
import importlib.util
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/gfx/tools'))
spec = importlib.util.spec_from_file_location('own_compilers', REPO / 'dm/gfx/tools/own_compilers.py')
own = importlib.util.module_from_spec(spec); spec.loader.exec_module(own)


class CompilerTargets(unittest.TestCase):
    def check(self, errors, environment):
        with mock.patch.object(own, 'strict', return_value=errors), mock.patch.dict(os.environ, environment, clear=True):
            return own.check_tools()

    def test_mac_skips_missing_ios_compiler(self):
        failure = 'metal_iphoneos: lock fixture / actual missing'
        for env in ({}, {'DMSH_TARGETS': 'mac'}, {'IOSOUT': '/unused', 'DMSH_TARGETS': 'mac'}):
            self.assertEqual(self.check([failure], env), [])

    def test_ios_requires_ios_compiler(self):
        failure = 'metal_iphoneos: lock fixture / actual missing'
        for env in ({'IOSOUT': '/ios'}, {'DMSH_TARGETS': 'ios'}, {'DMSH_TARGETS': 'mac,ios'}):
            self.assertEqual(self.check([failure], env), [failure])

    def test_other_missing_tools_remain_errors(self):
        for name in ('metal_macosx', 'spirv-cross', 'xlate_source'):
            failure = f'{name}: lock fixture / actual missing'
            self.assertEqual(self.check([failure], {'DMSH_TARGETS': 'mac'}), [failure])

    def test_wrapper_is_outside_chain_hash(self):
        import dmsh_chain
        self.assertNotIn('tools/own_compilers.py', dmsh_chain.FILES)


if __name__ == '__main__': unittest.main()
