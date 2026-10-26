// GYLT's character materials exceed the old 64-binding reflection limit.
// Exercise the real JSON converter, including rejection before fixed-array writes.
#import "../nvn/nvn_refl.h"
#import <Foundation/Foundation.h>
#include <stdio.h>

int main(void) { @autoreleasepool {
    NSMutableArray *bindings = [NSMutableArray array];
    nvn_refl reflection; char error[160];
    for (int i = 0; i < 84; i++) {
        [bindings addObject:@{@"kind": @"tex", @"reg": @(i), @"arg_id": @(i),
                              @"msl_name": @"fp_t", @"msl_type": @"texture2d<float>"}];
    }
    NSDictionary *json = @{@"route": @"B", @"bindings": bindings};
    if (nvn_refl_from_json(json, &reflection, error, sizeof error) || reflection.nb != 84 ||
        reflection.b[83].kind != NVN_RB_TEX || reflection.b[83].aid != 83 || reflection.b[83].reg != 83) {
        fprintf(stderr, "84-binding material failed: %s\n", error); return 1;
    }
    while (bindings.count <= NVN_REFL_MAXB) [bindings addObject:bindings[0]];
    if (!nvn_refl_from_json(json, &reflection, error, sizeof error)) {
        fprintf(stderr, "oversized reflection was accepted\n"); return 1;
    }
    puts("Reflection: 84-binding material accepted; oversized input rejected");
    return 0;
} }
