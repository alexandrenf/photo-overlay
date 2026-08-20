import AppKit
import SwiftUI

@MainActor
final class CanvasViewportState: ObservableObject {
    @Published var zoom: Double = 1
    @Published var pan: CGPoint = .zero

    var zoomLabel: String { "\(Int((zoom * 100).rounded()))%" }

    func reset() {
        zoom = 1
        pan = .zero
    }
}

struct EditorCanvasView: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    @ObservedObject var viewportState: CanvasViewportState
    var isCropping: Bool
    @Binding var cropSelection: PixelRect?
    var onSave: () -> Void
    var onCopy: () -> Void
    var onDismiss: () -> Void
    var onError: (Error) -> Void

    func makeNSView(context: Context) -> EditorCanvasNSView {
        let view = EditorCanvasNSView(document: document, viewportState: viewportState)
        view.onCropSelectionChange = { cropSelection = $0 }
        view.onSave = onSave
        view.onCopy = onCopy
        view.onDismiss = onDismiss
        view.onError = onError
        view.isCropping = isCropping
        return view
    }

    func updateNSView(_ nsView: EditorCanvasNSView, context: Context) {
        nsView.document = document
        nsView.viewportState = viewportState
        nsView.onCropSelectionChange = { cropSelection = $0 }
        nsView.onSave = onSave
        nsView.onCopy = onCopy
        nsView.onDismiss = onDismiss
        nsView.onError = onError
        nsView.isCropping = isCropping
        nsView.externalCropSelection = cropSelection
        nsView.synchronizeRenderedImage()
    }
}

@MainActor
final class EditorCanvasNSView: NSView, NSTextFieldDelegate {
    var document: EditorDocument
    var viewportState: CanvasViewportState {
        didSet { needsDisplay = true }
    }
    var isCropping = false {
        didSet {
            if oldValue != isCropping {
                cropDragStart = nil
                if !isCropping { cropSelection = nil }
                resetCursorRects()
                needsDisplay = true
            }
        }
    }
    var externalCropSelection: PixelRect? {
        didSet {
            if externalCropSelection != cropSelection {
                cropSelection = externalCropSelection
                needsDisplay = true
            }
        }
    }

    var onCropSelectionChange: (PixelRect?) -> Void = { _ in }
    var onSave: () -> Void = {}
    var onCopy: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onError: (Error) -> Void = { _ in }

    private var committedImage: NSImage?
    private var renderedBaseIdentity: ObjectIdentifier?
    private var renderedAnnotations: [Annotation] = []
    private var dragStart: PixelPoint?
    private var dragPoints: [PixelPoint] = []
    private var cropDragStart: PixelPoint?
    private var cropSelection: PixelRect?
    private var selectionDragOriginal: Annotation?
    private var selectionDragStart: PixelPoint?
    private var selectionDragMode: SelectionDragMode = .move
    private var selectionPreview: Annotation?
    private var selectionBackground: NSImage?
    private var panDragStart: CGPoint?
    private var panOrigin: CGPoint = .zero
    private var isSpaceHeld = false
    private var textField: NSTextField?
    private var textAnchor: PixelPoint?
    private var editingTextAnnotation: Annotation?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(document: EditorDocument, viewportState: CanvasViewportState) {
        self.document = document
        self.viewportState = viewportState
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorCanvasNSView does not support storyboards")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        resetCursorRects()
        needsDisplay = true
    }

    override func resetCursorRects() {
        discardCursorRects()
        let cursor: NSCursor
        if isCropping {
            cursor = .crosshair
        } else {
            switch document.activeTool {
            case .select: cursor = isSpaceHeld ? .openHand : .arrow
            case .text: cursor = .iBeam
            default: cursor = .crosshair
            }
        }
        addCursorRect(bounds, cursor: cursor)
    }

    func synchronizeRenderedImage(force: Bool = false) {
        guard let baseImage = document.baseImage else {
            discardTextEditor()
            committedImage = nil
            renderedBaseIdentity = nil
            renderedAnnotations = []
            needsDisplay = true
            return
        }

        let identity = ObjectIdentifier(baseImage)
        if let renderedBaseIdentity, identity != renderedBaseIdentity {
            // Loading or transforming an image while the field editor is open
            // must not leave an editor for the previous image floating above it.
            discardTextEditor()
        }
        guard force || identity != renderedBaseIdentity || renderedAnnotations != document.annotations else {
            needsDisplay = true
            return
        }

        do {
            committedImage = try ImageRenderer.render(
                baseImage: baseImage,
                annotations: document.annotations,
                canvasSize: document.pixelSize
            )
            renderedBaseIdentity = identity
            renderedAnnotations = document.annotations
        } catch {
            onError(error)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
        dirtyRect.fill()
        drawCanvasGrid(in: dirtyRect)

        guard document.hasImage else { return }
        let viewport = currentViewport
        let imageRect = viewport.imageRectInView.cgRect

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.52)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: 7)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: imageRect, xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        let imageToDraw = selectionBackground ?? committedImage ?? document.baseImage
        imageToDraw?.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        if let draft = document.draftAnnotation {
            CanvasAnnotationPainter.draw(draft, viewport: viewport, isEffectPreview: true)
        }
        if let selectionPreview {
            CanvasAnnotationPainter.draw(selectionPreview, viewport: viewport)
        }

        if isCropping {
            drawCropOverlay(viewport: viewport)
        } else if let selected = selectionPreview ?? document.selectedAnnotation {
            drawSelection(for: selected, viewport: viewport)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard document.hasImage else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let viewport = currentViewport
        let pixelPoint = viewport.pixelPoint(fromViewPoint: viewPoint)
        guard viewport.imageRectInView.contains(PixelPoint(viewPoint)) else {
            if document.activeTool == .select {
                beginPan(at: viewPoint)
            }
            return
        }

        if isCropping {
            cropDragStart = pixelPoint
            cropSelection = PixelRect(from: pixelPoint, to: pixelPoint)
            onCropSelectionChange(cropSelection)
            needsDisplay = true
            return
        }

        if isSpaceHeld {
            beginPan(at: viewPoint)
            return
        }

        switch document.activeTool {
        case .select:
            let tolerance = max(5, 9 / viewport.scale)
            if let selected = document.selectedAnnotation,
               let handle = selectionHandle(at: viewPoint, for: selected, viewport: viewport) {
                selectionDragOriginal = selected
                selectionDragStart = pixelPoint
                selectionDragMode = .resize(handle)
                selectionPreview = selected
                renderSelectionBackground(excluding: selected.id)
            } else if let id = document.selectAnnotation(at: pixelPoint, tolerance: tolerance),
               let annotation = document.annotations.first(where: { $0.id == id }) {
                if event.clickCount == 2, annotation.tool == .text {
                    beginEditingText(annotation, viewport: viewport)
                    return
                }
                selectionDragOriginal = annotation
                selectionDragStart = pixelPoint
                selectionDragMode = .move
                selectionPreview = annotation
                renderSelectionBackground(excluding: id)
            } else {
                document.select(nil)
                beginPan(at: viewPoint)
            }
            needsDisplay = true

        case .text:
            beginAddingText(at: pixelPoint, viewport: viewport)

        default:
            dragStart = pixelPoint
            dragPoints = [pixelPoint]
            document.setDraft(makeAnnotation(from: pixelPoint, to: pixelPoint, points: dragPoints))
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard document.hasImage else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)

        if let panDragStart {
            viewportState.pan = CGPoint(
                x: panOrigin.x + viewPoint.x - panDragStart.x,
                y: panOrigin.y + viewPoint.y - panDragStart.y
            )
            needsDisplay = true
            return
        }

        let pixelPoint = currentViewport.pixelPoint(fromViewPoint: viewPoint)
        if isCropping, let cropDragStart {
            cropSelection = PixelRect(from: cropDragStart, to: pixelPoint)
                .clamped(to: document.pixelSize)
            onCropSelectionChange(cropSelection)
            needsDisplay = true
            return
        }

        if let original = selectionDragOriginal, let start = selectionDragStart {
            switch selectionDragMode {
            case .move:
                selectionPreview = original.translatedBy(
                    dx: pixelPoint.x - start.x,
                    dy: pixelPoint.y - start.y
                )
            case let .resize(handle):
                selectionPreview = resized(original, dragging: handle, to: pixelPoint)
            }
            needsDisplay = true
            return
        }

        guard let dragStart else { return }
        if document.activeTool == .pencil || document.activeTool == .pen || document.activeTool == .highlighter {
            if dragPoints.last?.distance(to: pixelPoint) ?? .infinity > max(0.7, 1.8 / currentViewport.scale) {
                dragPoints.append(pixelPoint)
            }
        }
        document.setDraft(makeAnnotation(from: dragStart, to: pixelPoint, points: dragPoints))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragPoints = []
            cropDragStart = nil
            panDragStart = nil
            if !isSpaceHeld { NSCursor.arrow.set() }
        }

        if isCropping {
            onCropSelectionChange(cropSelection)
            needsDisplay = true
            return
        }

        if let selectionPreview, let selectionDragOriginal {
            let didChange = selectionPreview != selectionDragOriginal
            if didChange {
                document.updateAnnotation(selectionPreview)
            }
            selectionDragOriginal = nil
            selectionDragStart = nil
            selectionDragMode = .move
            self.selectionPreview = nil
            selectionBackground = nil
            if didChange {
                synchronizeRenderedImage(force: true)
            } else {
                needsDisplay = true
            }
            return
        }

        if document.draftAnnotation != nil {
            document.commitDraft(select: false)
            synchronizeRenderedImage(force: true)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas
                ? -Double(event.scrollingDeltaY) * 0.008
                : -Double(event.deltaY) * 0.06
            viewportState.zoom = (viewportState.zoom * (1 + delta)).clamped(to: 0.2 ... 8)
        } else {
            viewportState.pan.x += event.scrollingDeltaX
            viewportState.pan.y += event.scrollingDeltaY
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        viewportState.zoom = (viewportState.zoom * (1 + Double(event.magnification))).clamped(to: 0.2 ... 8)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if key == " " {
            isSpaceHeld = true
            NSCursor.openHand.set()
            resetCursorRects()
            return
        }
        if event.keyCode == 53 {
            if document.draftAnnotation != nil {
                document.cancelDraft()
                needsDisplay = true
            } else {
                onDismiss()
            }
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            document.removeSelectedAnnotation()
            synchronizeRenderedImage(force: true)
            return
        }

        if modifiers.contains(.command) {
            switch key {
            case "z":
                if modifiers.contains(.shift) {
                    document.redo()
                } else {
                    document.undo()
                }
                synchronizeRenderedImage(force: true)
            case "c": onCopy()
            case "s": onSave()
            case "d":
                document.duplicateSelectedAnnotation()
                synchronizeRenderedImage(force: true)
            case "0": viewportState.reset()
            case "+", "=": viewportState.zoom = (viewportState.zoom * 1.2).clamped(to: 0.2 ... 8)
            case "-": viewportState.zoom = (viewportState.zoom / 1.2).clamped(to: 0.2 ... 8)
            default: super.keyDown(with: event)
            }
            needsDisplay = true
            return
        }

        if let tool = AnnotationTool(keyboardKey: key) {
            document.selectTool(tool, resetStyle: true)
            resetCursorRects()
            needsDisplay = true
            return
        }

        let amount = modifiers.contains(.shift) ? 10.0 : 1.0
        switch event.keyCode {
        case 123: nudgeSelection(dx: -amount, dy: 0)
        case 124: nudgeSelection(dx: amount, dy: 0)
        case 125: nudgeSelection(dx: 0, dy: amount)
        case 126: nudgeSelection(dx: 0, dy: -amount)
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            isSpaceHeld = false
            NSCursor.arrow.set()
            resetCursorRects()
            return
        }
        super.keyUp(with: event)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEditor()
    }

    private var currentViewport: ImageViewport {
        ImageViewport(
            imageSize: document.imageSize,
            viewSize: bounds.size,
            zoom: viewportState.zoom,
            pan: viewportState.pan
        )
    }

    private func beginPan(at point: CGPoint) {
        panDragStart = point
        panOrigin = viewportState.pan
        NSCursor.closedHand.set()
    }

    private func makeAnnotation(from start: PixelPoint, to end: PixelPoint, points: [PixelPoint]) -> Annotation? {
        let style = document.style
        switch document.activeTool {
        case .pencil: return .pencil(points: points, style: style)
        case .pen: return .pen(points: points, style: style)
        case .highlighter: return .highlighter(points: points, style: style)
        case .arrow: return .arrow(from: start, to: end, style: style)
        case .line: return .line(from: start, to: end, style: style)
        case .rectangle: return .rectangle(PixelRect(from: start, to: end), style: style)
        case .ellipse: return .ellipse(PixelRect(from: start, to: end), style: style)
        case .blur: return .blur(.rectangle(PixelRect(from: start, to: end)), style: style)
        case .pixelate: return .pixelate(.rectangle(PixelRect(from: start, to: end)), style: style)
        case .select, .text: return nil
        }
    }

    private func renderSelectionBackground(excluding id: UUID) {
        guard let baseImage = document.baseImage else { return }
        do {
            selectionBackground = try ImageRenderer.render(
                baseImage: baseImage,
                annotations: document.annotations.filter { $0.id != id },
                canvasSize: document.pixelSize
            )
        } catch {
            onError(error)
        }
    }

    private func selectionHandle(
        at viewPoint: CGPoint,
        for annotation: Annotation,
        viewport: ImageViewport
    ) -> SelectionHandle? {
        let bounds = annotation.bounds.standardized
        let corners: [(SelectionHandle, PixelPoint)] = [
            (.topLeft, PixelPoint(x: bounds.minX, y: bounds.minY)),
            (.topRight, PixelPoint(x: bounds.maxX, y: bounds.minY)),
            (.bottomLeft, PixelPoint(x: bounds.minX, y: bounds.maxY)),
            (.bottomRight, PixelPoint(x: bounds.maxX, y: bounds.maxY))
        ]
        return corners.first { _, point in
            let handlePoint = viewport.viewPoint(fromPixelPoint: point)
            return hypot(handlePoint.x - viewPoint.x, handlePoint.y - viewPoint.y) <= 9
        }?.0
    }

    private func resized(
        _ annotation: Annotation,
        dragging handle: SelectionHandle,
        to point: PixelPoint
    ) -> Annotation {
        let oldBounds = annotation.bounds.standardized
        guard oldBounds.width > 0.001, oldBounds.height > 0.001 else { return annotation }

        let opposite: PixelPoint
        switch handle {
        case .topLeft: opposite = PixelPoint(x: oldBounds.maxX, y: oldBounds.maxY)
        case .topRight: opposite = PixelPoint(x: oldBounds.minX, y: oldBounds.maxY)
        case .bottomLeft: opposite = PixelPoint(x: oldBounds.maxX, y: oldBounds.minY)
        case .bottomRight: opposite = PixelPoint(x: oldBounds.minX, y: oldBounds.minY)
        }

        let newBounds = PixelRect(from: point, to: opposite).standardized
        guard newBounds.width >= 3, newBounds.height >= 3 else { return annotation }
        let scaleX = newBounds.width / oldBounds.width
        let scaleY = newBounds.height / oldBounds.height
        return annotation.mappingPoints { source in
            PixelPoint(
                x: newBounds.minX + ((source.x - oldBounds.minX) * scaleX),
                y: newBounds.minY + ((source.y - oldBounds.minY) * scaleY)
            )
        }
    }

    private func nudgeSelection(dx: Double, dy: Double) {
        guard let id = document.selectedAnnotationID else { return }
        document.translateAnnotation(id: id, dx: dx, dy: dy)
        synchronizeRenderedImage(force: true)
    }

    private func beginAddingText(at point: PixelPoint, viewport: ImageViewport) {
        textAnchor = point
        editingTextAnnotation = nil
        showTextEditor(text: "", pixelFrame: nil, viewport: viewport)
    }

    private func beginEditingText(_ annotation: Annotation, viewport: ImageViewport) {
        guard case let .text(text) = annotation.geometry else { return }
        textAnchor = text.frame.origin
        editingTextAnnotation = annotation
        renderSelectionBackground(excluding: annotation.id)
        showTextEditor(text: text.text, pixelFrame: text.frame, viewport: viewport)
    }

    private func showTextEditor(text: String, pixelFrame: PixelRect?, viewport: ImageViewport) {
        discardTextEditor(clearEditingState: false)

        let editorStyle = editingTextAnnotation?.style ?? document.style

        let origin = viewport.viewPoint(fromPixelPoint: pixelFrame?.origin ?? textAnchor ?? .zero)
        let defaultSize = NSSize(
            width: max(44, min(280, bounds.maxX - origin.x - 8)),
            height: max(38, CGFloat(editorStyle.fontSize * viewport.scale * 1.45))
        )
        let frame: NSRect
        if let pixelFrame {
            let maxPoint = viewport.viewPoint(
                fromPixelPoint: PixelPoint(x: pixelFrame.maxX, y: pixelFrame.maxY)
            )
            frame = NSRect(
                x: origin.x,
                y: origin.y,
                width: max(120, maxPoint.x - origin.x),
                height: max(38, maxPoint.y - origin.y)
            )
        } else {
            frame = NSRect(origin: origin, size: defaultSize)
        }

        let field = NSTextField(frame: frame)
        field.stringValue = text
        field.placeholderString = "Type something…"
        let displayFontSize = max(12, CGFloat(editorStyle.fontSize * viewport.scale))
        field.font = editorStyle.fontName.flatMap { NSFont(name: $0, size: displayFontSize) }
            ?? .systemFont(ofSize: displayFontSize, weight: editorStyle.fontWeight.nsWeight)
        field.textColor = editorStyle.strokeColor.nsColor
        field.backgroundColor = .controlBackgroundColor.withAlphaComponent(0.93)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextFieldAction(_:))
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitTextFieldAction(_ sender: NSTextField) {
        commitTextEditor()
    }

    private func commitTextEditor() {
        guard let field = textField, let anchor = textAnchor else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let viewport = currentViewport
        let existing = editingTextAnnotation
        let editorStyle = existing?.style ?? document.style
        let existingText: TextAnnotation? = {
            guard let existing, case let .text(value) = existing.geometry else { return nil }
            return value
        }()
        let proposedWidth = existingText?.frame.width ?? max(80, Double(field.frame.width) / viewport.scale)
        let proposedHeight = existingText?.frame.height
            ?? max(editorStyle.fontSize * 1.35, Double(field.frame.height) / viewport.scale)
        let frame = PixelRect(
            x: anchor.x,
            y: anchor.y,
            width: min(proposedWidth, max(1, document.pixelSize.width - anchor.x)),
            height: min(proposedHeight, max(1, document.pixelSize.height - anchor.y))
        )

        // Tear down the native field before mutating the document. Removing a
        // first responder can synchronously invoke the end-editing delegate.
        field.delegate = nil
        field.target = nil
        textField = nil
        textAnchor = nil
        editingTextAnnotation = nil
        field.removeFromSuperview()
        selectionBackground = nil
        window?.makeFirstResponder(self)

        if let existing {
            if text.isEmpty {
                document.removeAnnotation(id: existing.id)
            } else {
                var updated = existing
                let originalText = existingText
                updated.geometry = .text(
                    TextAnnotation(
                        text: text,
                        frame: frame,
                        alignment: originalText?.alignment ?? .leading,
                        hasBackground: originalText?.hasBackground ?? (existing.style.fillColor != nil)
                    )
                )
                document.updateAnnotation(updated)
            }
        } else if !text.isEmpty {
            document.addAnnotation(
                .text(
                    text,
                    in: frame,
                    hasBackground: document.style.fillColor != nil,
                    style: document.style
                ),
                select: false
            )
        }

        synchronizeRenderedImage(force: true)
    }

    private func discardTextEditor(clearEditingState: Bool = true) {
        guard let field = textField else {
            if clearEditingState {
                textAnchor = nil
                editingTextAnnotation = nil
                selectionBackground = nil
            }
            return
        }

        field.delegate = nil
        field.target = nil
        textField = nil
        field.removeFromSuperview()
        if clearEditingState {
            textAnchor = nil
            editingTextAnnotation = nil
            selectionBackground = nil
        }
        window?.makeFirstResponder(self)
    }

    private func drawCanvasGrid(in rect: NSRect) {
        let spacing: CGFloat = 18
        let path = NSBezierPath()
        path.lineWidth = 0.5
        var x = rect.minX - rect.minX.truncatingRemainder(dividingBy: spacing)
        while x <= rect.maxX {
            path.move(to: NSPoint(x: x, y: rect.minY))
            path.line(to: NSPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY - rect.minY.truncatingRemainder(dividingBy: spacing)
        while y <= rect.maxY {
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
            y += spacing
        }
        NSColor.white.withAlphaComponent(0.022).setStroke()
        path.stroke()
    }

    private func drawSelection(for annotation: Annotation, viewport: ImageViewport) {
        let bounds = annotation.bounds.standardized
        let min = viewport.viewPoint(fromPixelPoint: bounds.origin)
        let max = viewport.viewPoint(fromPixelPoint: PixelPoint(x: bounds.maxX, y: bounds.maxY))
        let rect = NSRect(x: min.x, y: min.y, width: max.x - min.x, height: max.y - min.y).insetBy(dx: -4, dy: -4)

        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        path.lineWidth = 1.5
        let dash: [CGFloat] = [5, 4]
        path.setLineDash(dash, count: dash.count, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.96).setStroke()
        path.stroke()

        for point in [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY)
        ] {
            let handle = NSBezierPath(ovalIn: NSRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            NSColor.controlAccentColor.setFill()
            NSColor.white.setStroke()
            handle.lineWidth = 1
            handle.fill()
            handle.stroke()
        }
    }

    private func drawCropOverlay(viewport: ImageViewport) {
        let imageRect = viewport.imageRectInView.cgRect
        NSColor.black.withAlphaComponent(0.58).setFill()
        guard let cropSelection, !cropSelection.isEmpty else {
            imageRect.fill()
            return
        }

        let min = viewport.viewPoint(fromPixelPoint: cropSelection.standardized.origin)
        let max = viewport.viewPoint(
            fromPixelPoint: PixelPoint(x: cropSelection.standardized.maxX, y: cropSelection.standardized.maxY)
        )
        let cropRect = NSRect(x: min.x, y: min.y, width: max.x - min.x, height: max.y - min.y)

        NSRect(x: imageRect.minX, y: imageRect.minY, width: imageRect.width, height: max(0, cropRect.minY - imageRect.minY)).fill()
        NSRect(x: imageRect.minX, y: cropRect.maxY, width: imageRect.width, height: max(0, imageRect.maxY - cropRect.maxY)).fill()
        NSRect(x: imageRect.minX, y: cropRect.minY, width: max(0, cropRect.minX - imageRect.minX), height: cropRect.height).fill()
        NSRect(x: cropRect.maxX, y: cropRect.minY, width: max(0, imageRect.maxX - cropRect.maxX), height: cropRect.height).fill()

        let outline = NSBezierPath(rect: cropRect)
        outline.lineWidth = 1.5
        NSColor.white.setStroke()
        outline.stroke()

        let thirds = NSBezierPath()
        thirds.lineWidth = 0.8
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            thirds.move(to: NSPoint(x: cropRect.minX + cropRect.width * fraction, y: cropRect.minY))
            thirds.line(to: NSPoint(x: cropRect.minX + cropRect.width * fraction, y: cropRect.maxY))
            thirds.move(to: NSPoint(x: cropRect.minX, y: cropRect.minY + cropRect.height * fraction))
            thirds.line(to: NSPoint(x: cropRect.maxX, y: cropRect.minY + cropRect.height * fraction))
        }
        NSColor.white.withAlphaComponent(0.45).setStroke()
        thirds.stroke()
    }
}

private enum CanvasAnnotationPainter {
    static func draw(_ annotation: Annotation, viewport: ImageViewport, isEffectPreview: Bool = false) {
        let style = annotation.style
        let strokeColor = style.strokeColor.nsColor.withAlphaComponent(CGFloat(style.opacity))
        let lineWidth = max(0.8, CGFloat(style.lineWidth * viewport.scale))

        switch annotation.geometry {
        case let .stroke(points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: viewport.viewPoint(fromPixelPoint: first))
            for point in points.dropFirst() {
                path.line(to: viewport.viewPoint(fromPixelPoint: point))
            }
            if points.count == 1 {
                let point = viewport.viewPoint(fromPixelPoint: first)
                path.line(to: CGPoint(x: point.x + 0.001, y: point.y))
            }
            configure(path, style: style, lineWidth: lineWidth)
            strokeColor.setStroke()
            path.stroke()

        case let .segment(start, end):
            let startPoint = viewport.viewPoint(fromPixelPoint: start)
            let endPoint = viewport.viewPoint(fromPixelPoint: end)
            let path = NSBezierPath()
            path.move(to: startPoint)
            path.line(to: endPoint)
            configure(path, style: style, lineWidth: lineWidth)
            strokeColor.setStroke()
            path.stroke()
            if annotation.tool == .arrow {
                drawArrowHead(from: startPoint, to: endPoint, color: strokeColor, width: lineWidth, length: CGFloat(style.arrowHeadLength * viewport.scale))
            }

        case let .box(pixelRect):
            let rect = viewRect(pixelRect, viewport: viewport)
            let path: NSBezierPath
            if annotation.tool == .ellipse {
                path = NSBezierPath(ovalIn: rect)
            } else {
                let radius = CGFloat(style.cornerRadius * viewport.scale)
                path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            }
            if let fillColor = style.fillColor {
                fillColor.nsColor
                    .withAlphaComponent(CGFloat(fillColor.alpha * style.opacity))
                    .setFill()
                path.fill()
            }
            configure(path, style: style, lineWidth: lineWidth)
            strokeColor.setStroke()
            path.stroke()

        case let .text(text):
            let rect = viewRect(text.frame, viewport: viewport)
            if text.hasBackground, let fillColor = style.fillColor {
                fillColor.nsColor.setFill()
                NSBezierPath(
                    roundedRect: rect,
                    xRadius: CGFloat(style.cornerRadius * viewport.scale),
                    yRadius: CGFloat(style.cornerRadius * viewport.scale)
                ).fill()
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = text.alignment.nsAlignment
            let font = NSFont.systemFont(
                ofSize: max(8, CGFloat(style.fontSize * viewport.scale)),
                weight: style.fontWeight.nsWeight
            )
            (text.text as NSString).draw(
                in: rect.insetBy(dx: 5, dy: 3),
                withAttributes: [
                    .font: font,
                    .foregroundColor: strokeColor,
                    .paragraphStyle: paragraph
                ]
            )

        case let .region(region):
            guard isEffectPreview else { return }
            let rect = viewRect(region.bounds, viewport: viewport)
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(rect: rect).fill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.5
            let dash: [CGFloat] = [6, 4]
            path.setLineDash(dash, count: dash.count, phase: 0)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.stroke()
        }
    }

    private static func configure(_ path: NSBezierPath, style: AnnotationStyle, lineWidth: CGFloat) {
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if !style.dashPattern.isEmpty {
            let dash = style.dashPattern.map { CGFloat($0) }
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
    }

    private static func viewRect(_ rect: PixelRect, viewport: ImageViewport) -> NSRect {
        let standardized = rect.standardized
        let origin = viewport.viewPoint(fromPixelPoint: standardized.origin)
        let maxPoint = viewport.viewPoint(
            fromPixelPoint: PixelPoint(x: standardized.maxX, y: standardized.maxY)
        )
        return NSRect(x: origin.x, y: origin.y, width: maxPoint.x - origin.x, height: maxPoint.y - origin.y)
    }

    private static func drawArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: NSColor,
        width: CGFloat,
        length: CGFloat
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let shaftLength = hypot(end.x - start.x, end.y - start.y)
        guard shaftLength > 0 else { return }
        let headLength = min(max(length, width * 2.8), shaftLength * 0.46)
        let spread = CGFloat.pi / 6
        let path = NSBezierPath()
        path.move(to: end)
        path.line(to: CGPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        ))
        path.move(to: end)
        path.line(to: CGPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        ))
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}

private extension AnnotationTool {
    init?(keyboardKey: String) {
        switch keyboardKey {
        case "v": self = .select
        case "p": self = .pencil
        case "b": self = .pen
        case "h": self = .highlighter
        case "a": self = .arrow
        case "l": self = .line
        case "r": self = .rectangle
        case "o": self = .ellipse
        case "t": self = .text
        case "u": self = .blur
        case "m": self = .pixelate
        default: return nil
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private enum SelectionHandle {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private enum SelectionDragMode {
    case move
    case resize(SelectionHandle)
}
