#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$PROJECT_ROOT"
swift build "${SWIFT_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
"$BIN_DIR/ClampEverything" --export-design "$PROJECT_ROOT/docs/design"
