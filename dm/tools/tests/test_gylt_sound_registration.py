"""Execute the build-specific AArch64 wrapper with controlled engine callbacks.

Requires the optional Unicorn emulator; no game files or proprietary code.
Checks both patch layouts, the registration lifecycle, and AAPCS64 preservation.
"""
import importlib.util
from pathlib import Path
import struct
import sys
import types
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
try:
    import unicorn as uc
    from unicorn import arm64_const as arm
except ImportError:
    uc = None


@unittest.skipIf(uc is None, 'install unicorn to execute AArch64 stub tests')
class SoundRegistration(unittest.TestCase):
    def run_case(self, patch_offset, sound_class, registered, registration_succeeds=True):
        path = Path(__file__).resolve().parents[2] / 'games/0100AC601DCA8000/patches.py'
        spec = importlib.util.spec_from_file_location('gylt_patches', path)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        code, sites, calls = bytearray(), {}, []
        def put(off, words, reason):
            self.assertIn(off, sites)
            self.assertTrue(reason)
            calls.append((off, words[0]))
        module.sound_class_registration(types.SimpleNamespace(
            here=lambda: patch_offset + len(code),
            emit=lambda w: code.extend(struct.pack('<I', w)),
            site=lambda off, original: sites.update({off: original}), put=put))
        base, device, properties, stack, done = 0x10000000, 0x30000000, 0x30001000, 0x40001000, 0x50000000
        machine = uc.Uc(uc.UC_ARCH_ARM64, uc.UC_MODE_ARM)
        for address in (base + patch_offset, base + 0x27de000, stack - 0x1000, done):
            machine.mem_map(address & ~0xfff, 0x1000)
        machine.mem_write(base + patch_offset, bytes(code))
        machine.reg_write(arm.UC_ARM64_REG_SP, stack)
        machine.reg_write(arm.UC_ARM64_REG_X0, device)
        machine.reg_write(arm.UC_ARM64_REG_X1, sound_class)
        saved = {getattr(arm, f'UC_ARM64_REG_X{i}'): 0x60000000 + i for i in range(18, 30)}
        for reg, value in saved.items(): machine.reg_write(reg, value)
        machine.reg_write(arm.UC_ARM64_REG_LR, done)
        events = []
        def engine(machine, address, size, _):
            nonlocal registered
            if address not in (base + 0x27de450, base + 0x27de150): return
            self.assertEqual(machine.reg_read(arm.UC_ARM64_REG_SP) % 16, 0)
            self.assertEqual(machine.reg_read(arm.UC_ARM64_REG_X0), device)
            self.assertEqual(machine.reg_read(arm.UC_ARM64_REG_X1), sound_class)
            lookup = address == base + 0x27de450
            events.append('lookup' if lookup else 'register')
            if not lookup:
                self.assertTrue(sound_class)
                registered = registration_succeeds
            result = properties if lookup and registered and sound_class else 0
            # Engine calls may destroy every caller-saved argument register.
            for i in range(18): machine.reg_write(getattr(arm, f'UC_ARM64_REG_X{i}'), 0xdead0000 + i)
            machine.reg_write(arm.UC_ARM64_REG_X0, result)
            machine.reg_write(arm.UC_ARM64_REG_PC, machine.reg_read(arm.UC_ARM64_REG_LR))
        machine.hook_add(uc.UC_HOOK_CODE, engine)
        machine.emu_start(base + patch_offset, done, count=100)
        self.assertEqual(machine.reg_read(arm.UC_ARM64_REG_PC), done)
        self.assertEqual(machine.reg_read(arm.UC_ARM64_REG_SP), stack)
        for reg, value in saved.items(): self.assertEqual(machine.reg_read(reg), value)
        self.assertEqual(machine.reg_read(arm.UC_ARM64_REG_X0), properties if registered and sound_class else 0)
        for off, instruction in calls:
            immediate = instruction & 0x3ffffff
            if immediate & 0x2000000: immediate -= 0x4000000
            self.assertEqual(instruction >> 26, 0b100101)  # BL preserves the caller's continuation
            self.assertEqual(off + immediate * 4, patch_offset)
        return events

    def test_lookup_and_registration(self):
        for offset in (-0x1f00000, 0x6800000):
            with self.subTest(offset=offset):
                self.assertEqual(self.run_case(offset, 0, False), ['lookup'])
                self.assertEqual(self.run_case(offset, 0x31000000, True), ['lookup'])
                self.assertEqual(self.run_case(offset, 0x31000000, False), ['lookup', 'register', 'lookup'])
                self.assertEqual(self.run_case(offset, 0x31000000, False, False), ['lookup', 'register', 'lookup'])


if __name__ == '__main__': unittest.main()
