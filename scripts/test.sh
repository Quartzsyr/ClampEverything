#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$PROJECT_ROOT"
CLAMP_DEVELOPER="$(xcode-select -p)"
CLAMP_TEST_FRAMEWORKS="$CLAMP_DEVELOPER/Library/Developer/Frameworks"
CLAMP_TEST_LIBRARIES="$CLAMP_DEVELOPER/Library/Developer/usr/lib"
if [ -d "$CLAMP_TEST_FRAMEWORKS/Testing.framework" ]; then
    swift test "${SWIFT_ARGS[@]}" --disable-xctest -Xswiftc -F -Xswiftc "$CLAMP_TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$CLAMP_TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$CLAMP_TEST_LIBRARIES" "$@"
else
    swift test "${SWIFT_ARGS[@]}" --disable-xctest "$@"
fi
