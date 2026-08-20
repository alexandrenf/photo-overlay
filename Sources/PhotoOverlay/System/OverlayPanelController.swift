import AppKit
import SwiftUI

/// Owns the floating editor window independently of SwiftUI's scene lifecycle.
/// This makes it suitable for being shown from a Carbon hot-key callback even
/// when the application has no ordinary document window open.
@MainActor
final class OverlayPanelController: NSWindowController, NSWindowDelegate {
    typealias ContentFactory = () -> AnyView

    private let panelTitle: String
    private let defaultSize: NSSize
    private var contentFactory: ContentFactory
    private var hostingController: NSHostingController<AnyView>?
    private var overlayPanel: OverlayPanel?

    var isVisible: Bool {
        overlayPanel?.isVisible == true
    }

    init(
        title: String = "Photo Overlay",
        defaultSize: NSSize = NSSize(width: 1_180, height: 760),
        contentFactory: @escaping ContentFactory
    ) {
        self.panelTitle = title
        self.defaultSize = defaultSize
        self.contentFactory = contentFactory
        super.init(window: nil)
        windowFrameAutosaveName = NSWindow.FrameAutosaveName("PhotoOverlay.EditorPanel")
    }

    convenience init<Content: View>(
        title: String = "Photo Overlay",
        defaultSize: NSSize = NSSize(width: 1_180, height: 760),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            defaultSize: defaultSize,
            contentFactory: { AnyView(content()) }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayPanelController does not support storyboards")
    }

    /// Shows the editor on the screen under the pointer the first time. Later
    /// invocations preserve the user's resized and repositioned window.
    func show(refreshingContent: Bool = true, on screen: NSScreen? = nil) {
        let panel = ensurePanel(on: screen ?? Self.screenUnderPointer())

        if refreshingContent {
            hostingController?.rootView = contentFactory()
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        overlayPanel?.orderOut(nil)
    }

    func toggle(refreshingContent: Bool = true) {
        if isVisible {
            hide()
        } else {
            show(refreshingContent: refreshingContent)
        }
    }

    /// Rebuilds the SwiftUI root view while retaining the same native panel.
    func refreshContent() {
        _ = ensurePanel(on: Self.screenUnderPointer())
        hostingController?.rootView = contentFactory()
    }

    func setContentFactory(_ contentFactory: @escaping ContentFactory) {
        self.contentFactory = contentFactory
        refreshContent()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Keep the controller and editor state alive; a subsequent hot key is
        // instantaneous and does not need to reconstruct the native window.
        sender.orderOut(nil)
        return false
    }

    private func ensurePanel(on screen: NSScreen?) -> OverlayPanel {
        if let panel = overlayPanel {
            return panel
        }

        let frame = Self.initialFrame(size: defaultSize, on: screen)
        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.title = panelTitle
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
        panel.minSize = NSSize(width: 680, height: 460)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let hostingController = NSHostingController(rootView: contentFactory())
        panel.contentViewController = hostingController
        self.hostingController = hostingController
        self.overlayPanel = panel
        self.window = panel

        return panel
    }

    private static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main
    }

    private static func initialFrame(size: NSSize, on screen: NSScreen?) -> NSRect {
        guard let visibleFrame = screen?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }

        let horizontalMargin: CGFloat = 32
        let verticalMargin: CGFloat = 32
        let width = max(320, min(size.width, visibleFrame.width - horizontalMargin))
        let height = max(280, min(size.height, visibleFrame.height - verticalMargin))

        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}
