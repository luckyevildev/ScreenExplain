import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .noDisplay: "Дисплей не найден"
        case .windowNotFound: "Окно не найдено (возможно, оно закрыто)"
        }
    }
}

/// Источник захвата: дисплей или окно приложения
enum CaptureSource: String, CaseIterable, Identifiable {
    case display = "Дисплей"
    case window = "Окно приложения"

    var id: String { rawValue }
}

struct DisplayItem: Identifiable, Hashable {
    let displayID: UInt32
    let name: String

    var id: UInt32 { displayID }
}

struct WindowItem: Identifiable, Hashable {
    let windowID: UInt32
    let bundleIdentifier: String
    let appName: String
    let windowTitle: String

    var id: UInt32 { windowID }
    var displayName: String { windowTitle.isEmpty ? appName : "\(appName) — \(windowTitle)" }
    /// Строка для сохранения выбора в настройках, см. `WindowKey`.
    var key: String { "\(bundleIdentifier):\(windowID)" }
}

/// Разобранный `WindowItem.key`: `bundleIdentifier:windowID`.
/// Если окно с таким ID закрыли, ищем любое окно того же приложения.
struct WindowKey {
    let bundleIdentifier: String
    let windowID: UInt32

    init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let windowID = UInt32(parts[1]) else { return nil }
        self.bundleIdentifier = String(parts[0])
        self.windowID = windowID
    }

    func match(in windows: [WindowItem]) -> WindowItem? {
        windows.first { $0.windowID == windowID } ?? windows.first { $0.bundleIdentifier == bundleIdentifier }
    }

    fileprivate func match(in windows: [SCWindow]) -> SCWindow? {
        windows.first { $0.windowID == windowID }
            ?? windows.first { $0.owningApplication?.bundleIdentifier == bundleIdentifier && $0.isOnScreen }
    }
}

enum ScreenCapture {
    static func availableDisplays() async throws -> [DisplayItem] {
        let content = try await SCShareableContent.current
        return content.displays.enumerated().map { index, display in
            DisplayItem(displayID: display.displayID, name: displayName(for: display) ?? "Дисплей \(index + 1)")
        }
    }

    /// Окна приложений, видимые на экране
    static func availableWindows() async throws -> [WindowItem] {
        let content = try await SCShareableContent.current
        return content.windows
            .filter(\.isOnScreen)
            .compactMap { window in
                guard let app = window.owningApplication else { return nil }
                return WindowItem(
                    windowID: window.windowID,
                    bundleIdentifier: app.bundleIdentifier,
                    appName: app.applicationName,
                    windowTitle: window.title ?? ""
                )
            }
            .sorted { $0.appName < $1.appName }
    }

    private static func displayName(for display: SCDisplay) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens
            .first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == display.displayID }?
            .localizedName
    }

    /// Захват по выбранному источнику. `displayID == nil` — первый дисплей.
    /// `excludingWindowNumbers` — окна, которые не попадут в снимок дисплея (полоса); для захвата окна не используется.
    static func capture(
        source: CaptureSource,
        displayID: UInt32?,
        windowKey: String,
        excludingWindowNumbers numbers: [Int]
    ) async throws -> NSImage {
        let content = try await SCShareableContent.current

        let filter: SCContentFilter
        switch source {
        case .display:
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw ScreenCaptureError.noDisplay
            }
            filter = SCContentFilter(
                display: display,
                excludingWindows: content.windows.filter { numbers.contains(Int($0.windowID)) }
            )

        case .window:
            guard let window = WindowKey(windowKey)?.match(in: content.windows) else {
                throw ScreenCaptureError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        }

        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: cgImage, size: filter.contentRect.size)
    }
}
