#!/bin/bash
# Чистая логика без AppKit/SwiftUI: компилируем swiftc и запускаем asserts из Tests/main.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -o "$OUT/checks" \
  ScreenExplain/ResponseContent.swift \
  ScreenExplain/SSE.swift \
  ScreenExplain/Pager.swift \
  Tests/main.swift
"$OUT/checks"
