import AppKit
import SwiftUI

@main
struct PhotoOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Overlay", systemImage: "rectangle.on.rectangle.angled") {
            OverlayMenu(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct OverlayMenu: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var document: EditorDocument

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _document = ObservedObject(wrappedValue: coordinator.document)
    }

    var body: some View {
        Button("Open Clipboard Image") {
            coordinator.openClipboard()
        }
        .keyboardShortcut("2", modifiers: [.command, .shift])

        Button("Open Image…") {
            coordinator.openFilePicker()
        }

        if document.hasImage {
            Button("Show Editor") {
                coordinator.showEditor()
            }
        }

        Divider()

        Toggle(
            "Open Images Automatically",
            isOn: Binding(
                get: { coordinator.isAutoOpenEnabled },
                set: { coordinator.setAutoOpen($0) }
            )
        )

        Divider()

        Button("Quit Overlay") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
