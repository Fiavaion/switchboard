#!/bin/bash
# Usage: scripts/build.sh [debug|release]
set -euo pipefail
CONF="${1:-debug}"
cd "$(dirname "$0")/.."
swift build -c "$CONF"
scripts/bundle.sh "$CONF"
