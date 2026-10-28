// NVN readback contract: a pending clear must reach both GPU buffer copies and CPU reads.
// Expected 8x4 RGBA values are literal bytes, independent of the Metal replay's state.
#define nvn_game_fps nvn_game_fps_mtl_default
#include "../nvn/nvn_mtl.m"
#undef nvn_game_fps
#define g_ft g_ft_hle
#include "../nvn/hle_nvn.c"
#undef g_ft
uint64_t g_t0_ns;
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int cases, failed;
#define EXPECT(n,w,v) do { int a=(w), b=(v); cases++; printf("%s expected %d -> got %d %s\n",n,a,b,a==b?"PASS":"FAIL"); failed+=a!=b; } while (0)

// A texture in a sparse virtual pool takes its content from what the pool's page table maps (nvn_sparse_copy), unmapped pages as 0. ReadTexels reads it there on whatever thread asks:
// Tears of the Kingdom reads such textures on its own threads (bake::ModuleMgr), and resolving the host texture there uploaded it outside the submit thread (up_owner_check aborted, #471)
typedef struct { const NVNtexture *t; const NVNcopyRegion *r; uint8_t *dst; } read_job;
static void *read_on_thread(void *p) { read_job *j = p; h_nvnTextureReadTexels(j->t, NULL, j->r, j->dst); return NULL; }
static void sparse_reads(const NVNcopyRegion *region, const uint8_t expected[4]) {
    size_t len = 4 * (size_t)getpagesize();
    uint8_t *phys = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0); if (phys == MAP_FAILED) abort();
    pool_t physical, sparse; pool_builder_t pb = {.mem=phys, .size=len, .flags=0x24};
    EXPECT("physical pool init", 1, h_nvnMemoryPoolInitialize((NVNmemoryPool *)&physical, (const NVNmemoryPoolBuilder *)&pb));
    pb = (pool_builder_t){.size=DM_GAME_APP_POOL + 4 * len, .flags=NVN_MEMORY_POOL_FLAGS_VIRTUAL};   // larger than the application pool: sparse
    EXPECT("sparse pool init", 1, h_nvnMemoryPoolInitialize((NVNmemoryPool *)&sparse, (const NVNmemoryPoolBuilder *)&pb));
    map_req map = {.phys=(NVNmemoryPool *)&physical, .size=len};   // [0, len) mapped, the rest not
    EXPECT("sparse mapping", 1, h_nvnMemoryPoolMapVirtual((NVNmemoryPool *)&sparse, 1, (const NVNmappingRequest *)&map));
    EXPECT("pool reads through its page table", 1, nvn_sparse_pool(&sparse));
    for (size_t i = 0; i < len / 4; i++) memcpy(phys + i * 4, expected, 4);   // every texel the same, whatever the block-linear order
    NVNtextureBuilder tb; NVNtexture mapped, unmapped; h_nvnTextureBuilderSetDefaults(&tb); h_nvnTextureBuilderSetWidth(&tb, 8);
    h_nvnTextureBuilderSetHeight(&tb, 4); h_nvnTextureBuilderSetFormat(&tb, NVN_FORMAT_RGBA8);
    h_nvnTextureBuilderSetStorage(&tb, (const NVNmemoryPool *)&sparse, 0); EXPECT("mapped sparse texture init", 1, h_nvnTextureInitialize(&mapped, &tb));
    h_nvnTextureBuilderSetStorage(&tb, (const NVNmemoryPool *)&sparse, 2 * len); EXPECT("unmapped sparse texture init", 1, h_nvnTextureInitialize(&unmapped, &tb));
    static const uint8_t zero[4];
    for (int other = 1; other >= 0; other--) for (int m = 0; m < 2; m++) {   // a game thread first (the texture not resolved yet), then the submit thread (this one: mtl_sub_begin ran here)
        uint8_t cpu[128]; memset(cpu, 0xEE, sizeof cpu); read_job j = {m ? &unmapped : &mapped, region, cpu};
        if (other) { pthread_t th; pthread_create(&th, NULL, read_on_thread, &j); pthread_join(th, NULL); } else read_on_thread(&j);
        int bad = 0; for (int i = 0; i < 32; i++) bad += memcmp(cpu + i * 4, m ? zero : expected, 4) != 0;
        char name[128]; snprintf(name, sizeof name, "sparse texture, %s pages, ReadTexels on %s thread, 32 literal pixels", m ? "unmapped" : "mapped", other ? "a game" : "the submit");
        EXPECT(name, 0, bad);
    }
    h_nvnTextureFinalize(&unmapped); h_nvnTextureFinalize(&mapped);
    h_nvnMemoryPoolFinalize((NVNmemoryPool *)&sparse); h_nvnMemoryPoolFinalize((NVNmemoryPool *)&physical); munmap(phys, len);
}

int main(void) { @autoreleasepool {
    mtl_init();
    void *mem = NULL; if (posix_memalign(&mem, getpagesize(), 262144)) abort(); memset(mem, 0, 262144);
    pool_t pool = {.mem=mem, .size=262144}; mtl_pool_add(mem, 262144);
    NVNtextureBuilder tb; NVNtexture tex; h_nvnTextureBuilderSetDefaults(&tb); h_nvnTextureBuilderSetWidth(&tb, 8);
    h_nvnTextureBuilderSetHeight(&tb, 4); h_nvnTextureBuilderSetFormat(&tb, NVN_FORMAT_RGBA8);
    h_nvnTextureBuilderSetStorage(&tb, (const NVNmemoryPool *)&pool, 131072); EXPECT("texture init", 1, h_nvnTextureInitialize(&tex, &tb));
    NVNcommandBuffer cmd; EXPECT("command init", 1, h_nvnCommandBufferInitialize(&cmd, NULL));
    h_nvnCommandBufferAddCommandMemory(&cmd, (const NVNmemoryPool *)&pool, 0, 65536);
    h_nvnCommandBufferBeginRecording(&cmd);
    const NVNtexture *targets[] = {&tex}; const NVNtextureView *views[] = {NULL};
    h_nvnCommandBufferSetRenderTargets(&cmd, 1, targets, views, NULL, NULL);
    float color[] = {0.2f, 0.4f, 0.6f, 1.f}; h_nvnCommandBufferClearColor(&cmd, 0, color, 15);
    NVNcopyRegion region = {0, 0, 0, 8, 4, 1}; uint8_t *out = (uint8_t *)mem + 196608; memset(out, 0xEE, 256);
    h_nvnCommandBufferSetCopyRowStride(&cmd, 64);
    h_nvnCommandBufferCopyTextureToBuffer(&cmd, &tex, NULL, &region, (NVNbufferAddress)out, 0);
    NVNsync sync; h_nvnSyncInitialize(&sync, NULL);
    h_nvnCommandBufferFenceSync(&cmd, &sync, NVN_SYNC_CONDITION_ALL_GPU_COMMANDS_COMPLETE, 0);
    NVNcommandHandle h = h_nvnCommandBufferEndRecording(&cmd);
    state_reset(); memset(&R, 0, sizeof R); mtl_sub_begin(); mtl_exec((const uint8_t *)h); mtl_sub_commit();
    int wait = h_nvnSyncWait(&sync, 5000000000ull); EXPECT("recorded fence wait", 1, wait == 0 || wait == 1);
    EXPECT("GPU success", 0, mtl_last_commit_error());
    static const uint8_t expected[] = {51, 102, 153, 255}; int bad = 0;
    for (int y=0; y<4; y++) { for (int x=0; x<8; x++) bad += memcmp(out+y*64+x*4, expected, 4) != 0;
        for (int x=32; x<64; x++) bad += out[y*64+x] != 0xEE; }
    EXPECT("pending clear -> GPU copy, literal pixels and untouched row padding", 0, bad);
    uint8_t cpu[128]; memset(cpu, 0xEE, sizeof cpu); h_nvnTextureReadTexels(&tex, NULL, &region, cpu); bad = 0;
    for (int i=0; i<32; i++) bad += memcmp(cpu+i*4, expected, 4) != 0;
    EXPECT("GPU clear -> CPU ReadTexels, 32 literal pixels", 0, bad);
    h_nvnTextureFinalize(&tex); mtl_pool_del(mem); free(mem);
    sparse_reads(&region, expected);
    printf("READBACK cases=%d failed=%d\n", cases, failed); return failed != 0;
} }
