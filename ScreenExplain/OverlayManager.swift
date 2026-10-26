import AppKit
import Combine
import SwiftUI

/// Полоса-оверлей внизу экрана: `NSPanel`, который не активирует приложение и не забирает фокус клавиатуры.
@MainActor
final class OverlayManager {
    static let shared = OverlayManager()

    private var panel: NSPanel?
    private let paging = OverlayPagingModel()
    private var cancellables: Set<AnyCancellable> = []
    /// Видимая область экрана, на котором показана полоса (экран курсора на момент show()).
    private var screenFrame: NSRect = .zero
    private var contentHeight: CGFloat = minHeight
    private var isShown = false
    private var isAnimating = false

    private static let minHeight: CGFloat = 56
    private static let margin: CGFloat = 24
    private static let slide: CGFloat = 16
    private static let duration: TimeInterval = 0.18

    private init() {}

    /// Подписывается на runner.isOverlayVisible: true → show(), false → hide().
    func bind(to runner: ExplainRunner) {
        cancellables.removeAll()
        runner.$isOverlayVisible
            .removeDuplicates()
            .sink { [weak self] visible in visible ? self?.show() : self?.hide() }
            .store(in: &cancellables)
        runner.$phase
            .sink { [weak self] phase in
                guard let self, case .capturing = phase else { return }
                paging.followsEnd = true
                paging.currentPage = 0
            }
            .store(in: &cancellables)
    }

    /// Номер окна полосы для исключения из захвата экрана; nil, пока панель не создана.
    var panelWindowNumber: Int? { panel?.windowNumber }

    func pageDown() { paging.pageDown() }
    func pageUp() { paging.pageUp() }

    /// Вызывается вью: желаемая высота содержимого; менеджер меняет frame панели, низ фиксирован.
    func setContentHeight(_ height: CGFloat) {
        contentHeight = max(Self.minHeight, height)
        guard isShown, !isAnimating, let panel else { return }
        panel.setFrame(targetFrame(), display: true, animate: false)
    }

    private func show() {
        let panel = panel ?? makePanel()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        screenFrame = screen?.visibleFrame ?? .zero
        paging.screenHeight = screenFrame.height
        isShown = true
        isAnimating = true

        let target = targetFrame()
        panel.alphaValue = 0
        panel.setFrame(target.offsetBy(dx: 0, dy: -Self.slide), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        } completionHandler: {
            Task { @MainActor in self.finishAnimation() }
        }
        GlobalHotkeyManager.setOverlayHotkeys(enabled: true)
    }

    private func hide() {
        GlobalHotkeyManager.setOverlayHotkeys(enabled: false)
        guard isShown, let panel else { return }
        isShown = false
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: -Self.slide), display: true)
        } completionHandler: {
            Task { @MainActor in self.finishAnimation() }
        }
    }

    /// Конец анимации: скрытая полоса уходит с экрана, показанная догоняет высоту, пришедшую во время анимации.
    private func finishAnimation() {
        isAnimating = false
        guard let panel else { return }
        if isShown {
            panel.alphaValue = 1
            panel.setFrame(targetFrame(), display: true, animate: false)
        } else {
            panel.orderOut(nil)
        }
    }

    private func targetFrame() -> NSRect {
        NSRect(
            x: screenFrame.minX + Self.margin,
            y: screenFrame.minY + Self.margin,
            width: screenFrame.width - Self.margin * 2,
            height: contentHeight
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: Self.minHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Важное замечание: некоторые приложения для записи экрана могут игнорировать этот флаг.
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // NSApp.hide (закрытие окна настроек) прячет все окна приложения; полоса должна остаться.
        panel.canHide = false
        panel.becomesKeyOnlyIfNeeded = true

        let root = OverlayBarView(runner: ExplainRunner.shared, paging: paging) { [weak self] height in
            self?.setContentHeight(height)
        }
        let hostingView = NSHostingView(rootView: root)
        // Размер панели задаёт менеджер, хостинг не должен подгонять окно под SwiftUI.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = nil
        panel.contentView = hostingView

        self.panel = panel
        return panel
    }
}
