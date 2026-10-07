#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/check-toolchain.sh
xcrun swift-format lint --strict --recursive --configuration .swift-format CoolMalliOS Packages/MallKit/Sources Packages/MallKit/Tests CoolMalliOSUITests
xcrun swift-format lint --strict --configuration .swift-format Packages/MallKit/Package.swift Scripts/SourceBoundaries.swift
