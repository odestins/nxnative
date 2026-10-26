// Reusing the three upload allocators must make progress even when their
// commits are still in a partially filled deferred-encoding record block.
#include "../nvn/nvn_mtl.m"
#include <signal.h>
#include <unistd.h>

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

static void timeout(int signal_number) {
    (void)signal_number;
    static const char message[] = "FAIL: upload allocator reuse stalled before queued commits ran\n";
    write(STDERR_FILENO, message, sizeof message - 1);
    _exit(2);
}

int main(int argc, char **argv) {
    int deferred = !(argc > 1 && !strcmp(argv[1], "--inline"));
    setenv("DM_NVN_ENC_THREAD", deferred ? "1" : "0", 1);
    signal(SIGALRM, timeout);
    @autoreleasepool {
        mtl_init();
        enum { batches = 12, bytes_per_batch = 16 };
        id<MTLBuffer> result = [g_dev newBufferWithLength:batches * bytes_per_batch options:MTLResourceStorageModeShared];
        if (!result) return 1;
        memset(result.contents, 0, result.length);
        res_add(result);
        mtl_sub_begin();
        alarm(10);
        for (unsigned i = 0; i < batches; i++) {
            up_begin();
            [g_up_ce fillBuffer:result range:NSMakeRange(i * bytes_per_batch, bytes_per_batch) value:(uint8_t)(i + 1)];
            up_flush();
        }
        uint64_t fence = mtl_sub_commit();
        if (!mtl_wait(fence, 5000000000ull)) return 1;
        up_wait_zero(&g_up_pending);
        alarm(0);
        if (mtl_last_commit_error()) return 1;
        for (unsigned i = 0; i < batches; i++) {
            for (unsigned j = 0; j < bytes_per_batch; j++) {
                if (((uint8_t *)result.contents)[i * bytes_per_batch + j] != i + 1) {
                    fprintf(stderr, "FAIL: incorrect GPU upload data in batch %u\n", i);
                    return 1;
                }
            }
        }
        for (unsigned i = 0; i < 3; i++) if (atomic_load(&g_up_alloc_busy[i])) return 1;
        printf("PASS: %u upload batches reused three slots with correct GPU data (%s encoding)\n", batches, deferred ? "deferred" : "inline");
    }
    return 0;
}
