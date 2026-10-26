"""Heap and virtual-address layouts must follow the executable's NPDM."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'games'))
import profile_guess as pg


class UnrealMemory(unittest.TestCase):
    def profile(self, system_resource):
        facts = dict(
            mods={'main': dict(imports={pg.HEAP_API, 'nvnBootstrapLoader'},
                               exports=set(), bss=24 * pg.MiB, far=False)},
            romfs={'exts': {'.pak': 1}, 'root': set()},
            main_markers={'Unreal', 'Unreal 4'}, sysres=system_resource)
        return pg.guess(facts, hooks=set())

    def test_nonvirtual_unreal_has_room_for_measured_heap(self):
        g = self.profile(0)
        reserve, alias, stack = (int(g[k][0], 0) for k in
                                 ('mem_reserve', 'mem_alias', 'mem_stack'))
        # mem_init reserves 256 MiB before alias/stack/heap. Little Nightmares
        # 1.0.4 requests this heap before nnMain; the old override left zero.
        self.assertGreaterEqual(reserve - 256 * pg.MiB - alias - stack, 0xc5600000)
        self.assertLessEqual(reserve, 5 * 1024**3)

    def test_virtual_unreal_retains_mac_bringup_region(self):
        g = self.profile(16 * pg.MiB)
        self.assertGreaterEqual(int(g['mem_alias'][0], 0), 62 * 1024**3)
        self.assertEqual(int(g['sys_resource'][0], 0), 16 * pg.MiB)


if __name__ == '__main__':
    unittest.main()
