#!/bin/bash
# Offline Core tests (Sources/Core only, no UIKit/host).
#
# STATUS 2026-10-27: does not link on Ubuntu 24.04 WSL. Ubuntu's GNUstep base is built on the GCC
# Objective-C runtime (libobjc.so.4); clang's GNUstep ABI needs libobjc2 (objc_msgSend,
# objc_autoreleasePoolPush, objc_setProperty_nonatomic_copy), and the GCC-runtime mode disables
# object literals/subscripting, which Core uses. Run this where GNUstep is built with clang + libobjc2
# (e.g. a source build of tools-make/libobjc2/base), or compile Tests/CoreTests.m + Sources/Core/*.m
# with Apple clang on macOS:  clang -fobjc-arc -framework Foundation Tests/CoreTests.m Sources/Core/*.m
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
clang -fobjc-runtime=gnustep-2.0 -fobjc-arc -fblocks -fobjc-exceptions \
  $(gnustep-config --objc-flags | tr ' ' '\n' | grep -E '^-(D|I)' | tr '\n' ' ') \
  "$ROOT"/Tests/CoreTests.m "$ROOT"/Sources/Core/*.m \
  $(gnustep-config --base-libs) -o "$OUT/coretests"
"$OUT/coretests"
