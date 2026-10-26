# Как участвовать

Спасибо, что хотите помочь. Пара правил, чтобы изменения проходили быстро.

## Сборка

- macOS 15.7 или новее, Xcode 26 или новее (нужен SDK macOS 26 из-за `glassEffect`).
- Откройте `ScreenExplain.xcodeproj` и запустите, либо из терминала:

```bash
xcodebuild -project ScreenExplain.xcodeproj -scheme ScreenExplain -configuration Debug -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
```

Новые файлы в папке `ScreenExplain/` попадают в проект сами (синхронизируемая папка), `project.pbxproj` править не нужно.

## Проверки

Чистая логика (разбор ответа, SSE, страницы) проверяется без Xcode-таргета:

```bash
bash Tests/run.sh
```

Добавляете логику без AppKit и SwiftUI? Положите её в отдельный файл с `nonisolated`, впишите файл в `Tests/run.sh` и добавьте `check(...)` в `Tests/main.swift`. Всё остальное (окна, хоткеи, разрешения) проверяется руками по [docs/testing.md](docs/testing.md).

## Код

- Swift 5 language mode с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: типы изолированы на главный актор по умолчанию, чистые функции и C-колбэки помечаются `nonisolated`.
- Без сторонних зависимостей.
- Сборка должна проходить без предупреждений.
- Интерфейс и комментарии на русском, идентификаторы на английском.

## Pull request

1. Одна задача на PR.
2. В описании: что изменилось, как проверяли (команды и что увидели), скриншот, если менялся интерфейс.
3. Если меняли полосу, панель или окно настроек, перегенерируйте картинки: `bash scripts/render-previews.sh` (нужен `ffmpeg`).

## Замысел

Прежде чем менять поведение полосы или хоткеев, прочитайте [docs/design.md](docs/design.md): там цели, антицели и причины решений.
