#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/check-toolchain.sh
mkdir -p .build/governance
MALL_SWIFT_HOST="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host"
xcrun swiftc -swift-version 6 -I "$MALL_SWIFT_HOST" -L "$MALL_SWIFT_HOST" -lSwiftSyntax -lSwiftParser -Xlinker -rpath -Xlinker "$MALL_SWIFT_HOST" -module-cache-path .build/governance/module-cache Scripts/SourceBoundaries.swift -o .build/governance/source-boundaries
python3 Scripts/check-project-boundaries.py "$@"
