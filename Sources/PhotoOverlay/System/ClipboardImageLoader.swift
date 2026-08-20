import AppKit
import Foundation

/// An image decoded from the system pasteboard together with enough metadata to
/// make clipboard-driven editor behavior predictable.
struct ClipboardImage {
    enum Source: Equatable {
        case pngData
        case tiffData
        case nativeImage
        case fileURL(URL)
    }

    let image: NSImage
    let source: Source
    let pasteboardChangeCount: Int
}

/// Decodes the common image representations applications place on the macOS
/// clipboard. All calls should be made from the main thread because AppKit owns
/// both `NSPasteboard` and `NSImage`.
@MainActor
enum ClipboardImageLoader {
    static func loadImage(from pasteboard: NSPasteboard = .general) -> ClipboardImage? {
        let changeCount = pasteboard.changeCount

        // Prefer explicit lossless data. This also handles clipboard producers
        // that advertise PNG/TIFF without implementing NSPasteboardReading.
        if
            let data = pasteboard.data(forType: .png),
            let image = NSImage(data: data)
        {
            return ClipboardImage(
                image: detachedCopy(of: image),
                source: .pngData,
                pasteboardChangeCount: changeCount
            )
        }

        if
            let data = pasteboard.data(forType: .tiff),
            let image = NSImage(data: data)
        {
            return ClipboardImage(
                image: detachedCopy(of: image),
                source: .tiffData,
                pasteboardChangeCount: changeCount
            )
        }

        if
            let objects = pasteboard.readObjects(
                forClasses: [NSImage.self],
                options: nil
            ),
            let image = objects.first as? NSImage
        {
            return ClipboardImage(
                image: detachedCopy(of: image),
                source: .nativeImage,
                pasteboardChangeCount: changeCount
            )
        }

        // Finder and several asset-management apps put file URLs on the
        // pasteboard instead of image data. Walk every URL so a non-image first
        // item does not mask a valid image later in the selection.
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let fileObjects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []

        for object in fileObjects {
            guard let nsURL = object as? NSURL else { continue }
            let fileURL = nsURL as URL
            guard fileURL.isFileURL, let image = NSImage(contentsOf: fileURL) else {
                continue
            }

            return ClipboardImage(
                image: detachedCopy(of: image),
                source: .fileURL(fileURL),
                pasteboardChangeCount: changeCount
            )
        }

        // Also accept a raw public.file-url string. This is useful for small
        // utilities and scripts that declare the UTI directly instead of using
        // NSURL's NSPasteboardWriting conformance.
        if let rawFileURL = pasteboard.string(forType: .fileURL) {
            let fileURL: URL
            if let parsedURL = URL(string: rawFileURL), parsedURL.isFileURL {
                fileURL = parsedURL
            } else {
                fileURL = URL(fileURLWithPath: rawFileURL)
            }

            if let image = NSImage(contentsOf: fileURL) {
                return ClipboardImage(
                    image: detachedCopy(of: image),
                    source: .fileURL(fileURL),
                    pasteboardChangeCount: changeCount
                )
            }
        }

        return nil
    }

    static func containsImage(in pasteboard: NSPasteboard = .general) -> Bool {
        loadImage(from: pasteboard) != nil
    }

    private static func detachedCopy(of image: NSImage) -> NSImage {
        // Give the editor its own mutable image object. Data-created images own
        // their encoded bytes, while native/file-backed images retain their
        // image representations through the copied NSImage.
        (image.copy() as? NSImage) ?? image
    }
}
