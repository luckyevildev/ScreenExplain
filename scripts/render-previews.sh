#!/bin/bash
# Собирает Debug-сборку, рендерит скриншоты из реальных вью приложения и склеивает GIF для README.
# Нужен ffmpeg (brew install ffmpeg). Разрешение на запись экрана не требуется.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=docs/images
RENDER=$(mktemp -d)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcodebuild -project ScreenExplain.xcodeproj -scheme ScreenExplain -configuration Debug \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E 'error:|BUILD' || true

# Настройки для картинок передаются как аргументы (домен NSArgumentDomain), пользовательские не трогаются.
SCREENEXPLAIN_RENDER_DIR="$RENDER" .build/Build/Products/Debug/ScreenExplain.app/Contents/MacOS/ScreenExplain \
  -backendMode "LM Studio" \
  -assistantMode "Написание кода" \
  -visionModel qwen2.5-vl-7b-instruct \
  -codeModel qwen2.5-coder-7b-instruct \
  -explainShortcut "⌘⇧Space" \
  -hasCompletedFirstRun YES

mkdir -p "$OUT"
cp "$RENDER"/overlay-answer.png "$RENDER"/overlay-thinking.png "$RENDER"/menubar-panel.png "$RENDER"/settings.png "$OUT"/

ffmpeg -y -loglevel error -f concat -safe 0 -i "$RENDER/gif/frames.txt" \
  -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 "$OUT/demo.gif"

ls -la "$OUT"
