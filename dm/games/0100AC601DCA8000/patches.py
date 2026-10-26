# GYLT 1.2: FMallocBinned3 reserves 37 GB. Use the host UE4 allocator.
# BaseAllocator (main+0xae2ac0) allocates 0x1c38 bytes, puts the object in x19,
# calls the constructor at +0xb45290, then returns it. Addresses and vtable
# layout were checked against main build 4584432786f462dbae0e2c0bb8e0523e.
from nso_asm import B, STP_PRE, LDP_POST, STP, LDP, ADDI
CUTS = {
    '4584432786f462dbae0e2c0bb8e0523e': [
        # This shipping UE4 build does not parse SwitchVirtualAddressSpaceSize:
        # StaticInit writes and requests 62 GB unconditionally. The host malloc
        # replacement leaves this region for the engine's virtual-memory users.
        (0xae250c, 'e81361b2', '0800b0d2', 'StaticInit: record a 2 GB virtual address region instead of 62 GB'),
        (0xae2520, 'e11361b2', '0100b0d2', 'StaticInit: request the same 2 GB from nn::os::AllocateAddressRegion'),
        (0xae2ad8, 'ee890194', '1f2003d5', 'BaseAllocator: omit the 37 GB FMallocBinned3 constructor; the following gate installs the host vtable'),
    ],
}
OBS = {
    '4584432786f462dbae0e2c0bb8e0523e': [
        (0xae2adc, 21, 'aa1303e0', 'BaseAllocator: allocator in x19; host sets the vtable before mov x0, x19'),
    ],
}


def sound_class_registration(ctx):
    # On the iPhone, cinematic classes finish PostLoad before GEngine has its
    # audio manager, but are absent from InitSoundClasses' object snapshot.
    # GetSoundClassCurrentProperties then returns null at the poster cinematic;
    # both callers dereference it. The missing class varies with load timing.
    # Repair a miss using the engine's own RegisterSoundClass on the caller's
    # audio thread (the game thread when threaded audio is disabled). This fills
    # both property maps and keeps subsequent mixer updates/unregistration normal.
    # Do not alter the lookup itself: it is also used to check registration.
    sites = ((0x2e4566c, '7963e697'), (0x26d2a44, '832e0494'))
    for off, original in sites: ctx.site(off, original)
    here, emit = ctx.here, ctx.emit
    start = here()
    emit(STP_PRE(29, 30, 31, -32))
    emit(ADDI(29, 31, 0))
    emit(STP(19, 20, 31, 16))
    emit(0xaa0003f3)  # mov x19,x0 (device)
    emit(0xaa0103f4)  # mov x20,x1 (class)
    emit(B(here(), 0x27de450) | 0x80000000)  # original lookup
    emit(0xb5000100)  # cbnz x0,out (+8 instructions): already registered
    emit(0xb40000f4)  # cbz x20,out (+7): preserve null-class behavior
    emit(0xaa1303e0); emit(0xaa1403e1)  # mov x0,x19; mov x1,x20
    emit(B(here(), 0x27de150) | 0x80000000)  # RegisterSoundClass
    emit(0xaa1303e0); emit(0xaa1403e1)
    emit(B(here(), 0x27de450) | 0x80000000)  # retry once, no recursion
    # Both branches target this epilogue. A miss remains a miss if registration
    # cannot complete; never return fabricated properties or bypass game audio.
    emit(LDP(19, 20, 31, 16))
    emit(LDP_POST(29, 30, 31, 32))
    emit(0xd65f03c0)  # ret
    for off, _ in sites:
        ctx.put(off, [B(off, start) | 0x80000000],
                'Cinematic sound: register a missing sound class through FAudioDevice before retrying its property lookup')


STUBS = {'4584432786f462dbae0e2c0bb8e0523e': sound_class_registration}
