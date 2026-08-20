import Carbon.HIToolbox
import Foundation

/// A small, ownership-safe wrapper around Carbon global hot keys.
///
/// Carbon remains the native API for application-wide keyboard shortcuts that
/// do not require Accessibility permission. Register and unregister this object
/// on the main thread so its callback runs on the application's event loop.
final class GlobalHotKey {
    enum RegistrationError: LocalizedError {
        case installingEventHandler(OSStatus)
        case registeringHotKey(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installingEventHandler(let status):
                return "Could not install the global hot-key event handler (OSStatus \(status))."
            case .registeringHotKey(let status):
                if status == OSStatus(eventHotKeyExistsErr) {
                    return "That keyboard shortcut is already registered by another application."
                }
                return "Could not register the global hot key (OSStatus \(status))."
            }
        }
    }

    /// Hardware key code for the `2` key on an ANSI keyboard.
    static let defaultKeyCode = UInt32(kVK_ANSI_2)
    static let defaultModifiers = UInt32(cmdKey | shiftKey)

    let keyCode: UInt32
    let modifiers: UInt32

    @MainActor
    var isRegistered: Bool {
        hotKeyReference != nil
    }

    private static let signature: OSType = 0x504F564C // "POVL"
    private static var nextIdentifier: UInt32 = 1
    private static let identifierLock = NSLock()

    private let identifier: UInt32
    private var handler: @MainActor () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(
        keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
        modifiers: UInt32 = GlobalHotKey.defaultModifiers,
        handler: @escaping @MainActor () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        self.identifier = Self.makeIdentifier()
    }

    deinit {
        unregisterResources()
    }

    /// Registers the shortcut. Calling this repeatedly is harmless.
    @MainActor
    func register() throws {
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            context,
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            eventHandlerReference = nil
            throw RegistrationError.installingEventHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: identifier
        )
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard registrationStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            self.eventHandlerReference = nil
            hotKeyReference = nil
            throw RegistrationError.registeringHotKey(registrationStatus)
        }
    }

    /// Removes both the hot key and its event handler. Calling this repeatedly
    /// is safe, which makes application shutdown and preference changes simple.
    @MainActor
    func unregister() {
        unregisterResources()
    }

    @MainActor
    func updateHandler(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    private func unregisterResources() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }

        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private static func makeIdentifier() -> UInt32 {
        identifierLock.lock()
        defer { identifierLock.unlock() }

        let identifier = nextIdentifier
        nextIdentifier = nextIdentifier == UInt32.max ? 1 : nextIdentifier + 1
        return identifier
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let hotKey = Unmanaged<GlobalHotKey>
            .fromOpaque(userData)
            .takeUnretainedValue()

        var incomingID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            UInt32(MemoryLayout<EventHotKeyID>.size),
            nil,
            &incomingID
        )

        guard
            parameterStatus == noErr,
            incomingID.signature == GlobalHotKey.signature,
            incomingID.id == hotKey.identifier
        else {
            return OSStatus(eventNotHandledErr)
        }

        // The handler is installed on the application event target by the
        // main-actor `register()` method, so Carbon dispatches it on that same
        // event loop. Make the guarantee explicit for SwiftUI callers.
        MainActor.assumeIsolated {
            hotKey.handler()
        }
        return noErr
    }
}
