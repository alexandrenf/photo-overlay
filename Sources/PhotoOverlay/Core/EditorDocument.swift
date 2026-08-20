import AppKit
import Combine
import Foundation

public enum EditorDocumentError: LocalizedError {
    case noImage
    case emptyClipboard
    case pasteboardWriteFailed

    public var errorDescription: String? {
        switch self {
        case .noImage:
            return "There is no image to edit."
        case .emptyClipboard:
            return "The clipboard does not contain an image."
        case .pasteboardWriteFailed:
            return "The edited image could not be copied to the clipboard."
        }
    }
}

public enum ImageExportFormat: Sendable {
    case png
    case jpeg(quality: Double = 0.92)
}

/// Main-actor editor state with lightweight snapshot-based undo and redo.
///
/// The base image is immutable between transformations, so annotation-only
/// snapshots safely share it instead of duplicating a potentially large bitmap.
@MainActor
public final class EditorDocument: ObservableObject {
    @Published public private(set) var baseImage: NSImage? = nil
    @Published public private(set) var imageSize: CGSize = .zero
    @Published public private(set) var annotations: [Annotation] = []
    @Published public var draftAnnotation: Annotation?
    @Published public var selectedAnnotationID: UUID?
    @Published public var activeTool: AnnotationTool = .pen
    @Published public var style: AnnotationStyle = .default(for: .pen)

    public var maximumHistoryDepth: Int = 80

    private struct Snapshot {
        var baseImage: NSImage?
        var imageSize: CGSize
        var annotations: [Annotation]
        var selectedAnnotationID: UUID?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var transactionStart: Snapshot?

    public init(image: NSImage? = nil) {
        if let image {
            do {
                try loadImage(image)
            } catch {
                baseImage = nil
                imageSize = .zero
            }
        }
    }

    public var pixelSize: PixelSize { PixelSize(imageSize) }
    public var hasImage: Bool { baseImage != nil && imageSize.width > 0 && imageSize.height > 0 }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var selectedAnnotation: Annotation? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first { $0.id == selectedAnnotationID }
    }

    public func loadImage(_ image: NSImage) throws {
        let size = try ImageRenderer.pixelSize(of: image)
        baseImage = image.copy() as? NSImage ?? image
        imageSize = size.cgSize
        annotations = []
        draftAnnotation = nil
        selectedAnnotationID = nil
        undoStack = []
        redoStack = []
        transactionStart = nil
    }

    public func loadClipboardImage(from pasteboard: NSPasteboard = .general) throws {
        guard let image = NSImage(pasteboard: pasteboard) else {
            throw EditorDocumentError.emptyClipboard
        }
        try loadImage(image)
    }

    public func selectTool(_ tool: AnnotationTool, resetStyle: Bool = false) {
        activeTool = tool
        if resetStyle {
            style = .default(for: tool)
        }
        if tool != .select {
            selectedAnnotationID = nil
        }
    }

    public func addAnnotation(_ annotation: Annotation, select: Bool = true) {
        guard annotation.isRenderable else { return }
        performMutation {
            annotations.append(annotation)
            selectedAnnotationID = select ? annotation.id : nil
        }
    }

    public func updateAnnotation(_ annotation: Annotation, registerUndo: Bool = true) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        guard annotations[index] != annotation else { return }
        if registerUndo { recordUndoSnapshot() }
        annotations[index] = annotation
        redoStack.removeAll()
    }

    public func updateAnnotation(
        id: UUID,
        registerUndo: Bool = true,
        _ update: (inout Annotation) -> Void
    ) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var updated = annotations[index]
        update(&updated)
        guard updated != annotations[index] else { return }
        if registerUndo { recordUndoSnapshot() }
        annotations[index] = updated
        redoStack.removeAll()
    }

    public func updateSelectedAnnotationStyle(
        registerUndo: Bool = true,
        _ update: (inout AnnotationStyle) -> Void
    ) {
        guard let id = selectedAnnotationID else { return }
        updateAnnotation(id: id, registerUndo: registerUndo) { annotation in
            update(&annotation.style)
        }
    }

    public func translateAnnotation(
        id: UUID,
        dx: Double,
        dy: Double,
        registerUndo: Bool = true
    ) {
        updateAnnotation(id: id, registerUndo: registerUndo) { annotation in
            annotation = annotation.translatedBy(dx: dx, dy: dy)
        }
    }

    public func duplicateSelectedAnnotation(offset: PixelPoint = PixelPoint(x: 12, y: 12)) {
        guard var duplicate = selectedAnnotation else { return }
        duplicate.id = UUID()
        duplicate = duplicate.translatedBy(dx: offset.x, dy: offset.y)
        addAnnotation(duplicate)
    }

    public func removeAnnotation(id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        performMutation {
            annotations.removeAll { $0.id == id }
            if selectedAnnotationID == id {
                selectedAnnotationID = nil
            }
        }
    }

    public func removeSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        removeAnnotation(id: selectedAnnotationID)
    }

    public func clearAnnotations() {
        guard !annotations.isEmpty || draftAnnotation != nil else { return }
        performMutation {
            annotations = []
            draftAnnotation = nil
            selectedAnnotationID = nil
        }
    }

    /// Convenience alias used by toolbar actions.
    public func clear() {
        clearAnnotations()
    }

    public func clearDocument() {
        guard baseImage != nil else { return }
        performMutation {
            baseImage = nil
            imageSize = .zero
            annotations = []
            draftAnnotation = nil
            selectedAnnotationID = nil
        }
    }

    public func setDraft(_ annotation: Annotation?) {
        draftAnnotation = annotation
    }

    public func commitDraft(select: Bool = true) {
        guard let draftAnnotation, draftAnnotation.isRenderable else {
            self.draftAnnotation = nil
            return
        }
        performMutation {
            annotations.append(draftAnnotation)
            self.draftAnnotation = nil
            selectedAnnotationID = select ? draftAnnotation.id : nil
        }
    }

    public func cancelDraft() {
        draftAnnotation = nil
    }

    public func select(_ id: UUID?) {
        if let id, annotations.contains(where: { $0.id == id }) {
            selectedAnnotationID = id
        } else {
            selectedAnnotationID = nil
        }
    }

    @discardableResult
    public func selectAnnotation(at point: PixelPoint, tolerance: Double = 8) -> UUID? {
        let match = annotations.last { $0.hitTest(point, tolerance: tolerance) }
        selectedAnnotationID = match?.id
        return match?.id
    }

    /// Groups a series of `registerUndo: false` changes (for example a drag)
    /// into one undo operation.
    public func beginEditingTransaction() {
        if transactionStart == nil {
            transactionStart = makeSnapshot()
        }
    }

    public func endEditingTransaction(commit: Bool = true) {
        guard let transactionStart else { return }
        self.transactionStart = nil
        if commit {
            if !snapshotMatchesCurrentState(transactionStart) {
                pushUndo(transactionStart)
                redoStack.removeAll()
            }
        } else {
            restore(transactionStart)
        }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(makeSnapshot())
        restore(previous)
        draftAnnotation = nil
        transactionStart = nil
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        pushUndo(makeSnapshot())
        restore(next)
        draftAnnotation = nil
        transactionStart = nil
    }

    public func crop(to requestedRect: PixelRect) throws {
        guard let baseImage else { throw EditorDocumentError.noImage }
        let bounds = PixelRect(origin: .zero, size: pixelSize)
        guard let clamped = requestedRect.standardized.intersection(bounds) else {
            throw ImageRenderError.invalidCanvasSize
        }
        let integralRect = PixelRect(clamped.cgRect.integral)
        guard let crop = integralRect.intersection(bounds), !crop.isEmpty else {
            throw ImageRenderError.invalidCanvasSize
        }

        let transformedImage = try ImageRenderer.crop(baseImage, to: crop)
        let keptAnnotations = annotations
            .filter { $0.bounds.intersection(crop) != nil }
            .map { $0.translatedBy(dx: -crop.minX, dy: -crop.minY) }

        recordUndoSnapshot()
        self.baseImage = transformedImage
        imageSize = CGSize(width: crop.width, height: crop.height)
        annotations = keptAnnotations
        draftAnnotation = nil
        if let selectedAnnotationID,
           !keptAnnotations.contains(where: { $0.id == selectedAnnotationID }) {
            self.selectedAnnotationID = nil
        }
        redoStack.removeAll()
    }

    public func rotateClockwise() throws {
        guard let baseImage else { throw EditorDocumentError.noImage }
        let oldWidth = Double(imageSize.width)
        let oldHeight = Double(imageSize.height)
        let transformedImage = try ImageRenderer.rotateClockwise(baseImage)
        let transformedAnnotations = annotations.map { annotation in
            annotation.mappingPoints { point in
                PixelPoint(x: oldHeight - point.y, y: point.x)
            }
        }

        recordUndoSnapshot()
        self.baseImage = transformedImage
        imageSize = CGSize(width: oldHeight, height: oldWidth)
        annotations = transformedAnnotations
        draftAnnotation = nil
        redoStack.removeAll()
    }

    public func rotateCounterclockwise() throws {
        guard let baseImage else { throw EditorDocumentError.noImage }
        let oldWidth = Double(imageSize.width)
        let oldHeight = Double(imageSize.height)
        let transformedImage = try ImageRenderer.rotateCounterclockwise(baseImage)
        let transformedAnnotations = annotations.map { annotation in
            annotation.mappingPoints { point in
                PixelPoint(x: point.y, y: oldWidth - point.x)
            }
        }

        recordUndoSnapshot()
        self.baseImage = transformedImage
        imageSize = CGSize(width: oldHeight, height: oldWidth)
        annotations = transformedAnnotations
        draftAnnotation = nil
        redoStack.removeAll()
    }

    public func flipHorizontal() throws {
        guard let baseImage else { throw EditorDocumentError.noImage }
        let width = Double(imageSize.width)
        let transformedImage = try ImageRenderer.flipHorizontal(baseImage)
        let transformedAnnotations = annotations.map { annotation in
            annotation.mappingPoints { point in
                PixelPoint(x: width - point.x, y: point.y)
            }
        }

        recordUndoSnapshot()
        self.baseImage = transformedImage
        annotations = transformedAnnotations
        draftAnnotation = nil
        redoStack.removeAll()
    }

    public func flipVertical() throws {
        guard let baseImage else { throw EditorDocumentError.noImage }
        let height = Double(imageSize.height)
        let transformedImage = try ImageRenderer.flipVertical(baseImage)
        let transformedAnnotations = annotations.map { annotation in
            annotation.mappingPoints { point in
                PixelPoint(x: point.x, y: height - point.y)
            }
        }

        recordUndoSnapshot()
        self.baseImage = transformedImage
        annotations = transformedAnnotations
        draftAnnotation = nil
        redoStack.removeAll()
    }

    public func render(
        includeDraft: Bool = true,
        backgroundColor: RGBAColor? = nil
    ) throws -> NSImage {
        guard let baseImage else { throw EditorDocumentError.noImage }
        var renderedAnnotations = annotations
        if includeDraft, let draftAnnotation, draftAnnotation.isRenderable {
            renderedAnnotations.append(draftAnnotation)
        }
        return try ImageRenderer.render(
            baseImage: baseImage,
            annotations: renderedAnnotations,
            canvasSize: pixelSize,
            backgroundColor: backgroundColor
        )
    }

    public func pngData(includeDraft: Bool = false) throws -> Data {
        try ImageRenderer.pngData(from: render(includeDraft: includeDraft))
    }

    public func jpegData(
        quality: Double = 0.92,
        includeDraft: Bool = false
    ) throws -> Data {
        let image = try render(includeDraft: includeDraft, backgroundColor: .white)
        return try ImageRenderer.jpegData(from: image, quality: quality)
    }

    public func clipboardImage(includeDraft: Bool = false) throws -> NSImage {
        try render(includeDraft: includeDraft)
    }

    public func copyToPasteboard(
        _ pasteboard: NSPasteboard = .general,
        includeDraft: Bool = false
    ) throws {
        let image = try clipboardImage(includeDraft: includeDraft)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else {
            throw EditorDocumentError.pasteboardWriteFailed
        }
    }

    public func export(
        to url: URL,
        format: ImageExportFormat,
        includeDraft: Bool = false
    ) throws {
        let data: Data
        switch format {
        case .png:
            data = try pngData(includeDraft: includeDraft)
        case let .jpeg(quality):
            data = try jpegData(quality: quality, includeDraft: includeDraft)
        }
        try data.write(to: url, options: .atomic)
    }
}

private extension EditorDocument {
    func makeSnapshot() -> Snapshot {
        Snapshot(
            baseImage: baseImage,
            imageSize: imageSize,
            annotations: annotations,
            selectedAnnotationID: selectedAnnotationID
        )
    }

    func restore(_ snapshot: Snapshot) {
        baseImage = snapshot.baseImage
        imageSize = snapshot.imageSize
        annotations = snapshot.annotations
        selectedAnnotationID = snapshot.selectedAnnotationID
    }

    func recordUndoSnapshot() {
        if transactionStart == nil {
            pushUndo(makeSnapshot())
        }
        redoStack.removeAll()
    }

    func pushUndo(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        let overflow = undoStack.count - max(maximumHistoryDepth, 1)
        if overflow > 0 {
            undoStack.removeFirst(overflow)
        }
    }

    func performMutation(_ mutation: () -> Void) {
        recordUndoSnapshot()
        mutation()
    }

    func snapshotMatchesCurrentState(_ snapshot: Snapshot) -> Bool {
        let hasSameBaseImage: Bool
        switch (snapshot.baseImage, baseImage) {
        case (nil, nil):
            hasSameBaseImage = true
        case let (lhs?, rhs?):
            hasSameBaseImage = lhs === rhs
        default:
            hasSameBaseImage = false
        }
        return hasSameBaseImage
            && snapshot.imageSize == imageSize
            && snapshot.annotations == annotations
            && snapshot.selectedAnnotationID == selectedAnnotationID
    }
}
