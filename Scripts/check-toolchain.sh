#!/bin/bash
set -euo pipefail
[[ "$(xcodebuild -version)" == $'Xcode 27.0\nBuild version 27A266a' ]] || { echo 'FAIL: expected Xcode 27.0 (27A266a)'; exit 1; }
xcrun swift --version | grep -F 'Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)' >/dev/null
[[ "$(xcrun swift-format --version)" == 'main' ]] || { echo 'FAIL: formatter differs from pinned Xcode'; exit 1; }
xcodebuild -version
xcrun swift --version
xcrun swift-format --version
