"""Exercise the exact Foundation parser used by the iOS scene delegate."""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCES = pathlib.Path(__file__).resolve().parents[1] / "Sources"


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "Apple Foundation required")
class LauncherLinkTests(unittest.TestCase):
    def test_only_a_single_boolean_for_this_game_is_accepted(self):
        source = r'''
#import "LauncherLink.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSString *scheme = @"nxnative-010015100b514000";
    assert([dm_launcher_hud_value([NSURL URLWithString:@"nxnative-010015100b514000://launch?hud=1"], scheme) isEqual:@YES]);
    assert([dm_launcher_hud_value([NSURL URLWithString:@"nxnative-010015100b514000://launch?hud=0"], scheme) isEqual:@NO]);
    for (NSString *url in @[
        @"nxnative-010015100b514000://launch", @"https://launch?hud=1",
        @"nxnative-0100000000000000://launch?hud=1",
        @"nxnative-010015100b514000://other?hud=1",
        @"nxnative-010015100b514000://launch/path?hud=1",
        @"nxnative-010015100b514000://user@launch?hud=1",
        @"nxnative-010015100b514000://launch:80?hud=1",
        @"nxnative-010015100b514000://launch?hud=1#fragment",
        @"nxnative-010015100b514000://launch?hud=1&hud=0",
        @"nxnative-010015100b514000://launch?hud=1&DM_LANG=x",
        @"nxnative-010015100b514000://launch?hud=true",
        @"nxnative-010015100b514000://launch?hud=", @"nxnative-010015100b514000://launch?other=1"
    ]) { assert(dm_launcher_hud_value([NSURL URLWithString:url], scheme) == nil); }
    NSString *restore = @"6c1838c3-cad7-4377-ab9d-dfb2448dd0a4";
    NSURL *validRestore = [NSURL URLWithString:[@"nxnative-010015100b514000://launch?hud=0&restore=" stringByAppendingString:restore]];
    assert([dm_launcher_restore_value(validRestore, scheme).lowercaseString isEqual:restore]);
    assert([dm_launcher_hud_value(validRestore, scheme) isEqual:@NO]);
    for (NSString *bad in @[@"../save", @"not-a-uuid", @"", @"1&restore=2"]) {
        NSURL *url = [NSURL URLWithString:[@"nxnative-010015100b514000://launch?restore=" stringByAppendingString:bad]];
        assert(dm_launcher_restore_value(url, scheme) == nil);
    }
    assert(dm_launcher_hud_value(nil, scheme) == nil);
} return 0; }
'''
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "check.m").write_text(source)
            subprocess.run(["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", "-I", str(SOURCES), str(root / "check.m"), "-o", str(root / "check")], check=True, capture_output=True, text=True)
            subprocess.run([str(root / "check")], check=True, capture_output=True, text=True)
