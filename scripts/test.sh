#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
CHECK_DIR="${TMPDIR:-/tmp}/codex-meter-checks"
mkdir -p "$CHECK_DIR"
swiftc -swift-version 5 -parse-as-library -D STANDALONE_CHECKS \
    -module-cache-path "$CHECK_DIR/modules" -o "$CHECK_DIR/checks" \
    Sources/CodexMeter/Usage.swift Sources/CodexMeter/CodexClient.swift \
    Tests/CodexMeterTests/UsageTests.swift
"$CHECK_DIR/checks"
