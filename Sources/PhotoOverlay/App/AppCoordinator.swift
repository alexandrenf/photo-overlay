import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator: ObservableObject {
    struct Toast: Equatable {
        enum Tone: Equatable {
            case neutral
            case success
            case error
        }

        let text: String
        let systemImage: String
        let tone: Tone
    }

    let document = EditorDocument()
    let viewportState = CanvasViewportState()

    @Published private(set) var toast: Toast?
    @Published var errorMessage: String?
    @Published private(set) var isAutoOpenEnabled: Bool

    private lazy var panelController = OverlayPanelController(title: "Overlay") { [weak self] in
        if let self {
            EditorView(coordinator: self)
        } else {
            EmptyView()
        }
    }
    private var hotKey: GlobalHotKey?
    private var clipboardMonitor: ClipboardChangeMonitor?
    private var toastTask: Task<Void, Never>?
    private var lastHandledPasteboardChangeCount = -1
    private var isStarted = false

    private static let autoOpenDefaultsKey = "automaticallyOpenCopiedImages"

    init() {
        isAutoOpenEnabled = UserDefaults.standard.bool(forKey: Self.autoOpenDefaultsKey)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        NSApp.setActivationPolicy(.accessory)

        let hotKey = GlobalHotKey { [weak self] in
            self?.openClipboard()
        }
        self.hotKey = hotKey
        do {
            try hotKey.register()
        } catch {
            present(error)
        }

        let monitor = ClipboardChangeMonitor { [weak self] clipboardImage in
            guard let self, self.isAutoOpenEnabled, let clipboardImage else { return }
            guard clipboardImage.pasteboardChangeCount != self.lastHandledPasteboardChangeCount else { return }
            self.load(clipboardImage, revealEditor: true)
        }
        clipboardMonitor = monitor
        if isAutoOpenEnabled {
            monitor.start()
        }

        // Launching the utility while an image is already copied should feel
        // just as immediate as invoking its global shortcut later.
        if ClipboardImageLoader.containsImage() {
            openClipboard()
        }
    }

    func stop() {
        toastTask?.cancel()
        clipboardMonitor?.stop()
        hotKey?.unregister()
        hotKey = nil
        isStarted = false
    }

    func openClipboard() {
        guard let clipboardImage = ClipboardImageLoader.loadImage() else {
            if !document.hasImage {
                panelController.show()
            }
            showToast(
                "Clipboard has no image",
                systemImage: "doc.on.clipboard",
                tone: .error
            )
            return
        }
        load(clipboardImage, revealEditor: true)
    }

    func showEditor() {
        panelController.show()
    }

    func hideEditor() {
        panelController.hide()
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Open an image"
        panel.prompt = "Open"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.open(url: url)
            }
        }
    }

    func open(url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            presentMessage("Overlay could not read \(url.lastPathComponent).")
            return
        }
        do {
            try document.loadImage(image)
            viewportState.reset()
            panelController.show()
            showToast("Opened \(url.lastPathComponent)", systemImage: "photo", tone: .neutral)
        } catch {
            present(error)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.canLoadObject(ofClass: NSImage.self)
        }) else { return false }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { [weak self] object, error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.present(error)
                    } else if let image = object as? NSImage {
                        do {
                            try self?.document.loadImage(image)
                            self?.viewportState.reset()
                            self?.showToast("Image ready", systemImage: "photo", tone: .success)
                        } catch {
                            self?.present(error)
                        }
                    }
                }
            }
            return true
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.present(error)
                    return
                }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url { self?.open(url: url) }
            }
        }
        return true
    }

    func copyResult() {
        do {
            try document.copyToPasteboard()
            lastHandledPasteboardChangeCount = NSPasteboard.general.changeCount
            showToast("Copied to clipboard", systemImage: "checkmark.circle.fill", tone: .success)
        } catch {
            present(error)
        }
    }

    func saveResult() {
        guard document.hasImage else { return }
        let panel = NSSavePanel()
        panel.title = "Save edited image"
        panel.prompt = "Save"
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.export(to: url)
            }
        }
    }

    func setAutoOpen(_ enabled: Bool) {
        isAutoOpenEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoOpenDefaultsKey)
        if enabled {
            clipboardMonitor?.start()
            showToast("Auto-open enabled", systemImage: "bolt.fill", tone: .success)
        } else {
            clipboardMonitor?.stop()
            showToast("Auto-open disabled", systemImage: "bolt.slash", tone: .neutral)
        }
    }

    func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            present(error)
        }
    }

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showToast(error.localizedDescription, systemImage: "exclamationmark.triangle.fill", tone: .error)
    }

    func presentMessage(_ message: String) {
        errorMessage = message
        showToast(message, systemImage: "exclamationmark.triangle.fill", tone: .error)
    }

    func showToast(
        _ text: String,
        systemImage: String,
        tone: Toast.Tone = .neutral,
        duration: Duration = .seconds(2.2)
    ) {
        toastTask?.cancel()
        toast = Toast(text: text, systemImage: systemImage, tone: tone)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func load(_ clipboardImage: ClipboardImage, revealEditor: Bool) {
        do {
            try document.loadImage(clipboardImage.image)
            viewportState.reset()
            lastHandledPasteboardChangeCount = clipboardImage.pasteboardChangeCount
            if revealEditor { panelController.show() }
            showToast("Clipboard image ready", systemImage: "photo.badge.checkmark", tone: .success)
        } catch {
            present(error)
        }
    }

    private func export(to url: URL) {
        do {
            let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
            try document.export(to: url, format: isJPEG ? .jpeg() : .png)
            showToast("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill", tone: .success)
        } catch {
            present(error)
        }
    }

    private var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Overlay \(formatter.string(from: Date())).png"
    }
}
