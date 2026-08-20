import AppKit
import CoreImage
import CoreText
import Foundation
import ImageIO

public enum ImageRenderError: LocalizedError {
    case imageHasNoBitmap
    case invalidCanvasSize
    case contextCreationFailed
    case outputCreationFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .imageHasNoBitmap:
            return "The source image could not be converted to pixels."
        case .invalidCanvasSize:
            return "The image canvas has an invalid size."
        case .contextCreationFailed:
            return "A bitmap drawing context could not be created."
        case .outputCreationFailed:
            return "The edited image could not be created."
        case .encodingFailed:
            return "The edited image could not be encoded."
        }
    }
}

/// A native-resolution, color-managed renderer for the editor document.
public enum ImageRenderer {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let ciContext = CIContext(options: [
        CIContextOption.workingColorSpace: colorSpace,
        CIContextOption.outputColorSpace: colorSpace
    ] as [CIContextOption: Any])

    public static func pixelSize(of image: NSImage) throws -> PixelSize {
        let image = try cgImage(from: image)
        return PixelSize(width: Double(image.width), height: Double(image.height))
    }

    public static func render(
        baseImage: NSImage,
        annotations: [Annotation],
        canvasSize: PixelSize? = nil,
        backgroundColor: RGBAColor? = nil
    ) throws -> NSImage {
        let source = try cgImage(from: baseImage)
        let requestedSize = canvasSize ?? PixelSize(
            width: Double(source.width),
            height: Double(source.height)
        )
        let roundedWidth = requestedSize.width.rounded()
        let roundedHeight = requestedSize.height.rounded()
        guard
            roundedWidth.isFinite,
            roundedHeight.isFinite,
            let width = Int(exactly: roundedWidth),
            let height = Int(exactly: roundedHeight),
            width > 0,
            height > 0
        else {
            throw ImageRenderError.invalidCanvasSize
        }

        guard let context = makeContext(width: width, height: height) else {
            throw ImageRenderError.contextCreationFailed
        }
        let canvasRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )

        if let backgroundColor {
            context.setFillColor(backgroundColor.cgColor)
            context.fill(canvasRect)
        } else {
            context.clear(canvasRect)
        }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.draw(source, in: canvasRect)

        for annotation in annotations where annotation.isRenderable {
            if annotation.tool == .blur || annotation.tool == .pixelate {
                try drawEffect(annotation, in: context, canvasRect: canvasRect)
            } else {
                draw(annotation, in: context, canvasHeight: Double(height))
            }
        }

        guard let output = context.makeImage() else {
            throw ImageRenderError.outputCreationFailed
        }
        return NSImage(
            cgImage: output,
            size: NSSize(width: CGFloat(width), height: CGFloat(height))
        )
    }

    public static func pngData(from image: NSImage) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: try cgImage(from: image))
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageRenderError.encodingFailed
        }
        return data
    }

    public static func jpegData(from image: NSImage, quality: Double = 0.92) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: try cgImage(from: image))
        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality.clamped(to: 0 ... 1)]
        ) else {
            throw ImageRenderError.encodingFailed
        }
        return data
    }

    public static func crop(_ image: NSImage, to pixelRect: PixelRect) throws -> NSImage {
        let source = try cgImage(from: image)
        let imageBounds = PixelRect(
            x: 0,
            y: 0,
            width: Double(source.width),
            height: Double(source.height)
        )
        guard let crop = pixelRect.standardized.intersection(imageBounds) else {
            throw ImageRenderError.invalidCanvasSize
        }

        // Core Image uses a bottom-left origin; the editor model uses top-left.
        let ciRect = CGRect(
            x: crop.minX,
            y: Double(source.height) - crop.maxY,
            width: crop.width,
            height: crop.height
        ).integral
        let input = CIImage(cgImage: source)
        let cropped = input
            .cropped(to: ciRect)
            .transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
        return try makeImage(from: cropped, extent: CGRect(origin: .zero, size: ciRect.size))
    }

    public static func rotateClockwise(_ image: NSImage) throws -> NSImage {
        try oriented(image, orientation: .right)
    }

    public static func rotateCounterclockwise(_ image: NSImage) throws -> NSImage {
        try oriented(image, orientation: .left)
    }

    public static func flipHorizontal(_ image: NSImage) throws -> NSImage {
        let source = try cgImage(from: image)
        let input = CIImage(cgImage: source)
        let transformed = input.transformed(
            by: CGAffineTransform(translationX: CGFloat(source.width), y: 0)
                .scaledBy(x: -1, y: 1)
        )
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(source.width),
            height: CGFloat(source.height)
        )
        return try makeImage(from: transformed, extent: extent)
    }

    public static func flipVertical(_ image: NSImage) throws -> NSImage {
        let source = try cgImage(from: image)
        let input = CIImage(cgImage: source)
        let transformed = input.transformed(
            by: CGAffineTransform(translationX: 0, y: CGFloat(source.height))
                .scaledBy(x: 1, y: -1)
        )
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(source.width),
            height: CGFloat(source.height)
        )
        return try makeImage(from: transformed, extent: extent)
    }
}

private extension ImageRenderer {
    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    static func cgImage(from image: NSImage) throws -> CGImage {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let image = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return image
        }

        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let image = bitmap.cgImage {
            return image
        }
        throw ImageRenderError.imageHasNoBitmap
    }

    static func oriented(
        _ image: NSImage,
        orientation: CGImagePropertyOrientation
    ) throws -> NSImage {
        let source = try cgImage(from: image)
        let transformed = CIImage(cgImage: source).oriented(orientation)
        let translated = transformed.transformed(
            by: CGAffineTransform(
                translationX: -transformed.extent.minX,
                y: -transformed.extent.minY
            )
        )
        let extent = CGRect(origin: .zero, size: transformed.extent.size)
        return try makeImage(from: translated, extent: extent)
    }

    static func makeImage(from image: CIImage, extent: CGRect) throws -> NSImage {
        guard extent.width > 0,
              extent.height > 0,
              let output = ciContext.createCGImage(image, from: extent) else {
            throw ImageRenderError.outputCreationFailed
        }
        return NSImage(cgImage: output, size: extent.size)
    }

    static func canvasPoint(_ point: PixelPoint, height: Double) -> CGPoint {
        CGPoint(x: point.x, y: height - point.y)
    }

    static func canvasRect(_ rect: PixelRect, height: Double) -> CGRect {
        let value = rect.standardized
        return CGRect(
            x: value.minX,
            y: height - value.maxY,
            width: value.width,
            height: value.height
        )
    }

    static func draw(_ annotation: Annotation, in context: CGContext, canvasHeight: Double) {
        context.saveGState()
        defer { context.restoreGState() }

        let style = annotation.style
        context.setAlpha(CGFloat(style.opacity.clamped(to: 0 ... 1)))
        context.setStrokeColor(style.strokeColor.cgColor)
        context.setLineWidth(CGFloat(max(style.lineWidth, 0.25)))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if !style.dashPattern.isEmpty {
            context.setLineDash(phase: 0, lengths: style.dashPattern.map { CGFloat($0) })
        }

        switch (annotation.tool, annotation.geometry) {
        case (.pencil, let .stroke(points)):
            drawPencil(points, style: style, in: context, canvasHeight: canvasHeight)
        case (.pen, let .stroke(points)):
            stroke(points, in: context, canvasHeight: canvasHeight)
        case (.highlighter, let .stroke(points)):
            context.setBlendMode(.multiply)
            stroke(points, in: context, canvasHeight: canvasHeight)
        case (.line, let .segment(start, end)):
            strokeSegment(from: start, to: end, in: context, canvasHeight: canvasHeight)
        case (.arrow, let .segment(start, end)):
            drawArrow(from: start, to: end, style: style, in: context, canvasHeight: canvasHeight)
        case (.rectangle, let .box(rect)):
            drawShape(rect, ellipse: false, style: style, in: context, canvasHeight: canvasHeight)
        case (.ellipse, let .box(rect)):
            drawShape(rect, ellipse: true, style: style, in: context, canvasHeight: canvasHeight)
        case (.text, let .text(text)):
            drawText(text, style: style, in: context, canvasHeight: canvasHeight)
        default:
            break
        }
    }

    static func smoothPath(_ points: [PixelPoint], canvasHeight: Double) -> CGPath? {
        guard let first = points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: canvasPoint(first, height: canvasHeight))
        guard points.count > 1 else { return path }

        if points.count == 2 {
            path.addLine(to: canvasPoint(points[1], height: canvasHeight))
            return path
        }

        for index in 1 ..< points.count {
            let current = canvasPoint(points[index], height: canvasHeight)
            let previous = canvasPoint(points[index - 1], height: canvasHeight)
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: current)
            }
        }
        return path
    }

    static func stroke(_ points: [PixelPoint], in context: CGContext, canvasHeight: Double) {
        guard let first = points.first else { return }
        if points.count == 1 {
            let center = canvasPoint(first, height: canvasHeight)
            // A nearly-zero line plus a round cap produces a dot using the
            // already configured stroke color and width.
            context.move(to: center)
            context.addLine(to: CGPoint(x: center.x + 0.001, y: center.y))
            context.strokePath()
            return
        }
        guard let path = smoothPath(points, canvasHeight: canvasHeight) else { return }
        context.addPath(path)
        context.strokePath()
    }

    static func drawPencil(
        _ points: [PixelPoint],
        style: AnnotationStyle,
        in context: CGContext,
        canvasHeight: Double
    ) {
        if points.count == 1 {
            stroke(points, in: context, canvasHeight: canvasHeight)
            return
        }
        guard let path = smoothPath(points, canvasHeight: canvasHeight) else { return }
        context.addPath(path)
        context.strokePath()

        // A subtle broken graphite pass adds texture without random output.
        context.saveGState()
        context.translateBy(x: 0.35, y: -0.25)
        context.setAlpha(CGFloat((style.opacity * 0.38).clamped(to: 0 ... 1)))
        context.setLineWidth(CGFloat(max(style.lineWidth * 0.42, 0.45)))
        context.setLineDash(phase: 0.5, lengths: [0.8, 1.7])
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    static func strokeSegment(
        from start: PixelPoint,
        to end: PixelPoint,
        in context: CGContext,
        canvasHeight: Double
    ) {
        context.move(to: canvasPoint(start, height: canvasHeight))
        context.addLine(to: canvasPoint(end, height: canvasHeight))
        context.strokePath()
    }

    static func drawArrow(
        from start: PixelPoint,
        to end: PixelPoint,
        style: AnnotationStyle,
        in context: CGContext,
        canvasHeight: Double
    ) {
        let length = start.distance(to: end)
        guard length > 0 else { return }
        strokeSegment(from: start, to: end, in: context, canvasHeight: canvasHeight)

        let headLength = min(max(style.arrowHeadLength, style.lineWidth * 2.8), length * 0.46)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let wingAngle = Double.pi / 6
        let left = PixelPoint(
            x: end.x - (headLength * cos(angle - wingAngle)),
            y: end.y - (headLength * sin(angle - wingAngle))
        )
        let right = PixelPoint(
            x: end.x - (headLength * cos(angle + wingAngle)),
            y: end.y - (headLength * sin(angle + wingAngle))
        )

        context.move(to: canvasPoint(left, height: canvasHeight))
        context.addLine(to: canvasPoint(end, height: canvasHeight))
        context.addLine(to: canvasPoint(right, height: canvasHeight))
        context.strokePath()
    }

    static func drawShape(
        _ pixelRect: PixelRect,
        ellipse: Bool,
        style: AnnotationStyle,
        in context: CGContext,
        canvasHeight: Double
    ) {
        let rect = canvasRect(pixelRect, height: canvasHeight)
        guard !rect.isEmpty else { return }

        let path: CGPath
        if ellipse {
            path = CGPath(ellipseIn: rect, transform: nil)
        } else if style.cornerRadius > 0 {
            let radius = min(CGFloat(style.cornerRadius), min(rect.width, rect.height) / 2)
            path = CGPath(
                roundedRect: rect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        } else {
            path = CGPath(rect: rect, transform: nil)
        }

        if let fillColor = style.fillColor {
            context.addPath(path)
            context.setFillColor(fillColor.cgColor)
            context.fillPath()
        }
        if style.lineWidth > 0, style.strokeColor.alpha > 0 {
            context.addPath(path)
            context.setStrokeColor(style.strokeColor.cgColor)
            context.strokePath()
        }
    }

    static func drawText(
        _ text: TextAnnotation,
        style: AnnotationStyle,
        in context: CGContext,
        canvasHeight: Double
    ) {
        let frame = canvasRect(text.frame, height: canvasHeight)
        guard !frame.isEmpty, !text.text.isEmpty else { return }

        if text.hasBackground, let fillColor = style.fillColor {
            let radius = min(CGFloat(style.cornerRadius), min(frame.width, frame.height) / 2)
            context.addPath(
                CGPath(
                    roundedRect: frame,
                    cornerWidth: radius,
                    cornerHeight: radius,
                    transform: nil
                )
            )
            context.setFillColor(fillColor.cgColor)
            context.fillPath()
        }

        let font: NSFont
        if let fontName = style.fontName,
           let customFont = NSFont(name: fontName, size: CGFloat(max(style.fontSize, 1))) {
            font = customFont
        } else {
            font = NSFont.systemFont(
                ofSize: CGFloat(max(style.fontSize, 1)),
                weight: style.fontWeight.nsWeight
            )
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = text.alignment.nsAlignment
        paragraph.lineBreakMode = .byWordWrapping
        // The context already carries the annotation opacity.
        let color = style.strokeColor.nsColor
        let attributed = NSAttributedString(
            string: text.text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let inset = max(CGFloat(style.lineWidth), text.hasBackground ? 8 : 0)
        let textRect = frame.insetBy(dx: inset, dy: inset)
        guard textRect.width > 0, textRect.height > 0 else { return }
        let path = CGPath(rect: textRect, transform: nil)
        let ctFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        CTFrameDraw(ctFrame, context)
    }

    static func drawEffect(
        _ annotation: Annotation,
        in context: CGContext,
        canvasRect: CGRect
    ) throws {
        guard case let .region(region) = annotation.geometry,
              let current = context.makeImage() else { return }

        let input = CIImage(cgImage: current)
        let output: CIImage
        if annotation.tool == .blur {
            output = input
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [
                        kCIInputRadiusKey: max(annotation.style.blurRadius, 0.5)
                    ]
                )
                .cropped(to: input.extent)
        } else {
            let center = CIVector(x: input.extent.midX, y: input.extent.midY)
            output = input
                .applyingFilter(
                    "CIPixellate",
                    parameters: [
                        kCIInputScaleKey: max(annotation.style.pixelScale, 2),
                        kCIInputCenterKey: center
                    ]
                )
                .cropped(to: input.extent)
        }

        guard let filtered = ciContext.createCGImage(output, from: input.extent) else {
            throw ImageRenderError.outputCreationFailed
        }

        context.saveGState()
        defer { context.restoreGState() }
        addClip(for: region, in: context, canvasHeight: Double(canvasRect.height))
        context.setAlpha(CGFloat(annotation.style.opacity.clamped(to: 0 ... 1)))
        context.interpolationQuality = .none
        context.draw(filtered, in: canvasRect)
    }

    static func addClip(
        for region: EffectRegion,
        in context: CGContext,
        canvasHeight: Double
    ) {
        switch region {
        case let .rectangle(rect):
            context.clip(to: canvasRect(rect, height: canvasHeight))
        case let .ellipse(rect):
            context.addEllipse(in: canvasRect(rect, height: canvasHeight))
            context.clip()
        case let .path(points, lineWidth):
            if points.count == 1, let point = points.first {
                let center = canvasPoint(point, height: canvasHeight)
                let diameter = CGFloat(max(lineWidth, 1))
                context.addEllipse(
                    in: CGRect(
                        x: center.x - (diameter / 2),
                        y: center.y - (diameter / 2),
                        width: diameter,
                        height: diameter
                    )
                )
                context.clip()
                return
            }
            guard let path = smoothPath(points, canvasHeight: canvasHeight) else {
                context.clip(to: .zero)
                return
            }
            context.addPath(path)
            context.setLineWidth(CGFloat(max(lineWidth, 1)))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
