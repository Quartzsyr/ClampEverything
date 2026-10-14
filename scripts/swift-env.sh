#!/bin/bash
# Source this script from other scripts; put all writable caches inside the project.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${SDKROOT:-}" ]; then
    for CLAMP_SDK in /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk; do
        if [ -d "$CLAMP_SDK" ]; then export SDKROOT="$CLAMP_SDK"; fi
    done
    if [ -z "${SDKROOT:-}" ]; then export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"; fi
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
SWIFT_ARGS=(--disable-sandbox --cache-path "$PROJECT_ROOT/.build/cache" --scratch-path "$PROJECT_ROOT/.build" --manifest-cache none --triple arm64-apple-macosx14.0)
