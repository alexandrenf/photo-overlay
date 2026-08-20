import AppKit
import Foundation

/// Polls `NSPasteboard.changeCount`, the reliable macOS mechanism for observing
/// clipboard changes. The monitor is opt-in and does no work until `start()` is
/// called.
@MainActor
final class ClipboardChangeMonitor {
    typealias ChangeHandler = @MainActor (ClipboardImage?) -> Void

    let pollingInterval: TimeInterval
    var isMonitoring: Bool { timer != nil }

    private let pasteboard: NSPasteboard
    private let onChange: ChangeHandler
    private var lastChangeCount: Int
    private var timer: Timer?

    init(
        pasteboard: NSPasteboard = .general,
        pollingInterval: TimeInterval = 0.35,
        onChange: @escaping ChangeHandler
    ) {
        self.pasteboard = pasteboard
        self.pollingInterval = max(0.1, pollingInterval)
        self.onChange = onChange
        self.lastChangeCount = pasteboard.changeCount
    }

    deinit {
        timer?.invalidate()
    }

    /// Starts watching. When `emitCurrentValue` is true, the handler is called
    /// immediately with the image currently on the clipboard (or nil).
    func start(emitCurrentValue: Bool = false) {
        guard timer == nil else { return }

        lastChangeCount = pasteboard.changeCount
        if emitCurrentValue {
            onChange(ClipboardImageLoader.loadImage(from: pasteboard))
        }

        let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            // This timer is installed on RunLoop.main below. Make that executor
            // guarantee explicit to Swift's concurrency checker.
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Checks immediately without changing whether the recurring monitor is on.
    func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount
        onChange(ClipboardImageLoader.loadImage(from: pasteboard))
    }
}
