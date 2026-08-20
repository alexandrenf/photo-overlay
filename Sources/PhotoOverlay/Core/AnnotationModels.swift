import AppKit
import Foundation

public enum AnnotationTool: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case select
    case pencil
    case pen
    case highlighter
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case blur
    case pixelate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .select: return "Select"
        case .pencil: return "Pencil"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        }
    }

    public var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .pencil: return "pencil"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3.square"
        }
    }

    public var createsAnnotation: Bool { self != .select }
}

/// A portable, Codable color representation for annotation documents.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? .black
        self.init(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }

    public var nsColor: NSColor {
        NSColor(
            deviceRed: CGFloat(red.clamped(to: 0 ... 1)),
            green: CGFloat(green.clamped(to: 0 ... 1)),
            blue: CGFloat(blue.clamped(to: 0 ... 1)),
            alpha: CGFloat(alpha.clamped(to: 0 ... 1))
        )
    }

    public var cgColor: CGColor { nsColor.cgColor }

    public func withAlpha(_ alpha: Double) -> RGBAColor {
        var result = self
        result.alpha = alpha
        return result
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let red = RGBAColor(red: 0.95, green: 0.18, blue: 0.16)
    public static let orange = RGBAColor(red: 1, green: 0.45, blue: 0.08)
    public static let yellow = RGBAColor(red: 1, green: 0.82, blue: 0.12)
    public static let green = RGBAColor(red: 0.13, green: 0.72, blue: 0.36)
    public static let blue = RGBAColor(red: 0.05, green: 0.48, blue: 0.95)
    public static let purple = RGBAColor(red: 0.54, green: 0.28, blue: 0.91)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
}

public enum AnnotationFontWeight: String, Codable, CaseIterable, Hashable, Sendable {
    case regular
    case medium
    case semibold
    case bold

    public var nsWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

public enum AnnotationTextAlignment: String, Codable, CaseIterable, Hashable, Sendable {
    case leading
    case center
    case trailing

    public var nsAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

public struct AnnotationStyle: Codable, Hashable, Sendable {
    public var strokeColor: RGBAColor
    public var fillColor: RGBAColor?
    /// Width in native image pixels.
    public var lineWidth: Double
    public var opacity: Double
    public var dashPattern: [Double]
    public var cornerRadius: Double
    public var fontName: String?
    public var fontSize: Double
    public var fontWeight: AnnotationFontWeight
    public var arrowHeadLength: Double
    public var blurRadius: Double
    /// Approximate width, in image pixels, of one output mosaic tile.
    public var pixelScale: Double

    public init(
        strokeColor: RGBAColor = .red,
        fillColor: RGBAColor? = nil,
        lineWidth: Double = 5,
        opacity: Double = 1,
        dashPattern: [Double] = [],
        cornerRadius: Double = 0,
        fontName: String? = nil,
        fontSize: Double = 32,
        fontWeight: AnnotationFontWeight = .semibold,
        arrowHeadLength: Double = 18,
        blurRadius: Double = 18,
        pixelScale: Double = 14
    ) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.dashPattern = dashPattern
        self.cornerRadius = cornerRadius
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.arrowHeadLength = arrowHeadLength
        self.blurRadius = blurRadius
        self.pixelScale = pixelScale
    }

    public static func `default`(for tool: AnnotationTool) -> AnnotationStyle {
        switch tool {
        case .select:
            return AnnotationStyle()
        case .pencil:
            return AnnotationStyle(
                strokeColor: .black,
                lineWidth: 2,
                opacity: 0.72,
                fontWeight: .regular
            )
        case .pen:
            return AnnotationStyle(strokeColor: .red, lineWidth: 5)
        case .highlighter:
            return AnnotationStyle(
                strokeColor: .yellow,
                lineWidth: 20,
                opacity: 0.45,
                fontWeight: .regular
            )
        case .arrow, .line, .rectangle, .ellipse:
            return AnnotationStyle(strokeColor: .red, lineWidth: 5)
        case .text:
            return AnnotationStyle(
                strokeColor: .white,
                fillColor: RGBAColor.black.withAlpha(0.62),
                lineWidth: 0,
                cornerRadius: 7,
                fontSize: 32,
                fontWeight: .semibold
            )
        case .blur:
            return AnnotationStyle(strokeColor: .clear, lineWidth: 0, blurRadius: 20)
        case .pixelate:
            return AnnotationStyle(strokeColor: .clear, lineWidth: 0, pixelScale: 14)
        }
    }
}

public struct TextAnnotation: Codable, Hashable, Sendable {
    public var text: String
    public var frame: PixelRect
    public var alignment: AnnotationTextAlignment
    public var hasBackground: Bool

    public init(
        text: String,
        frame: PixelRect,
        alignment: AnnotationTextAlignment = .leading,
        hasBackground: Bool = false
    ) {
        self.text = text
        self.frame = frame
        self.alignment = alignment
        self.hasBackground = hasBackground
    }
}

/// The clipping mask used by blur and pixelation annotations.
public enum EffectRegion: Codable, Hashable, Sendable {
    case rectangle(PixelRect)
    case ellipse(PixelRect)
    case path(points: [PixelPoint], lineWidth: Double)

    public var bounds: PixelRect {
        switch self {
        case let .rectangle(rect), let .ellipse(rect):
            return rect.standardized
        case let .path(points, lineWidth):
            guard let first = points.first else { return .zero }
            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            return PixelRect(
                x: minX - (lineWidth / 2),
                y: minY - (lineWidth / 2),
                width: (maxX - minX) + lineWidth,
                height: (maxY - minY) + lineWidth
            )
        }
    }
}

public enum AnnotationGeometry: Codable, Hashable, Sendable {
    case stroke([PixelPoint])
    case segment(start: PixelPoint, end: PixelPoint)
    case box(PixelRect)
    case text(TextAnnotation)
    case region(EffectRegion)
}

public struct Annotation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var tool: AnnotationTool
    public var geometry: AnnotationGeometry
    public var style: AnnotationStyle

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        geometry: AnnotationGeometry,
        style: AnnotationStyle? = nil
    ) {
        self.id = id
        self.tool = tool
        self.geometry = geometry
        self.style = style ?? .default(for: tool)
    }

    public static func pencil(
        points: [PixelPoint],
        style: AnnotationStyle = .default(for: .pencil)
    ) -> Annotation {
        Annotation(tool: .pencil, geometry: .stroke(points), style: style)
    }

    public static func pen(
        points: [PixelPoint],
        style: AnnotationStyle = .default(for: .pen)
    ) -> Annotation {
        Annotation(tool: .pen, geometry: .stroke(points), style: style)
    }

    public static func highlighter(
        points: [PixelPoint],
        style: AnnotationStyle = .default(for: .highlighter)
    ) -> Annotation {
        Annotation(tool: .highlighter, geometry: .stroke(points), style: style)
    }

    public static func line(
        from start: PixelPoint,
        to end: PixelPoint,
        style: AnnotationStyle = .default(for: .line)
    ) -> Annotation {
        Annotation(tool: .line, geometry: .segment(start: start, end: end), style: style)
    }

    public static func arrow(
        from start: PixelPoint,
        to end: PixelPoint,
        style: AnnotationStyle = .default(for: .arrow)
    ) -> Annotation {
        Annotation(tool: .arrow, geometry: .segment(start: start, end: end), style: style)
    }

    public static func rectangle(
        _ rect: PixelRect,
        style: AnnotationStyle = .default(for: .rectangle)
    ) -> Annotation {
        Annotation(tool: .rectangle, geometry: .box(rect), style: style)
    }

    public static func ellipse(
        _ rect: PixelRect,
        style: AnnotationStyle = .default(for: .ellipse)
    ) -> Annotation {
        Annotation(tool: .ellipse, geometry: .box(rect), style: style)
    }

    public static func text(
        _ text: String,
        in frame: PixelRect,
        alignment: AnnotationTextAlignment = .leading,
        hasBackground: Bool = false,
        style: AnnotationStyle = .default(for: .text)
    ) -> Annotation {
        Annotation(
            tool: .text,
            geometry: .text(
                TextAnnotation(
                    text: text,
                    frame: frame,
                    alignment: alignment,
                    hasBackground: hasBackground
                )
            ),
            style: style
        )
    }

    public static func blur(
        _ region: EffectRegion,
        style: AnnotationStyle = .default(for: .blur)
    ) -> Annotation {
        Annotation(tool: .blur, geometry: .region(region), style: style)
    }

    public static func pixelate(
        _ region: EffectRegion,
        style: AnnotationStyle = .default(for: .pixelate)
    ) -> Annotation {
        Annotation(tool: .pixelate, geometry: .region(region), style: style)
    }
}

public extension Annotation {
    var bounds: PixelRect {
        let padding = max(style.lineWidth / 2, 1)
        switch geometry {
        case let .stroke(points):
            guard let first = points.first else { return .zero }
            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            return PixelRect(
                x: minX - padding,
                y: minY - padding,
                width: (maxX - minX) + (padding * 2),
                height: (maxY - minY) + (padding * 2)
            )
        case let .segment(start, end):
            var points = [start, end]
            if let arrowWingPoints {
                points.append(contentsOf: [arrowWingPoints.left, arrowWingPoints.right])
            }
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            return PixelRect(
                x: (xs.min() ?? 0) - padding,
                y: (ys.min() ?? 0) - padding,
                width: ((xs.max() ?? 0) - (xs.min() ?? 0)) + (padding * 2),
                height: ((ys.max() ?? 0) - (ys.min() ?? 0)) + (padding * 2)
            )
        case let .box(rect):
            return rect.standardized.insetBy(dx: -padding, dy: -padding)
        case let .text(text):
            return text.frame.standardized
        case let .region(region):
            return region.bounds
        }
    }

    var isRenderable: Bool {
        switch (tool, geometry) {
        case (.pencil, let .stroke(points)),
             (.pen, let .stroke(points)),
             (.highlighter, let .stroke(points)):
            return !points.isEmpty
        case (.arrow, let .segment(start, end)),
             (.line, let .segment(start, end)):
            return start != end
        case (.rectangle, let .box(rect)),
             (.ellipse, let .box(rect)):
            return !rect.isEmpty
        case (.text, let .text(text)):
            return !text.text.isEmpty && !text.frame.isEmpty
        case (.blur, let .region(region)),
             (.pixelate, let .region(region)):
            return !region.bounds.isEmpty
        default:
            return false
        }
    }

    func translatedBy(dx: Double, dy: Double) -> Annotation {
        mappingPoints { PixelPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// Maps every image-space point, including all four corners of rectangles.
    /// Useful for crop, quarter-turn rotation, and flip operations.
    func mappingPoints(_ transform: (PixelPoint) -> PixelPoint) -> Annotation {
        var result = self

        func transformedRect(_ rect: PixelRect) -> PixelRect {
            let value = rect.standardized
            let corners = [
                PixelPoint(x: value.minX, y: value.minY),
                PixelPoint(x: value.maxX, y: value.minY),
                PixelPoint(x: value.maxX, y: value.maxY),
                PixelPoint(x: value.minX, y: value.maxY)
            ].map(transform)
            let xs = corners.map(\.x)
            let ys = corners.map(\.y)
            return PixelRect(
                x: xs.min() ?? 0,
                y: ys.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: (ys.max() ?? 0) - (ys.min() ?? 0)
            )
        }

        switch geometry {
        case let .stroke(points):
            result.geometry = .stroke(points.map(transform))
        case let .segment(start, end):
            result.geometry = .segment(start: transform(start), end: transform(end))
        case let .box(rect):
            result.geometry = .box(transformedRect(rect))
        case .text(var text):
            text.frame = transformedRect(text.frame)
            result.geometry = .text(text)
        case let .region(region):
            switch region {
            case let .rectangle(rect):
                result.geometry = .region(.rectangle(transformedRect(rect)))
            case let .ellipse(rect):
                result.geometry = .region(.ellipse(transformedRect(rect)))
            case let .path(points, lineWidth):
                result.geometry = .region(.path(points: points.map(transform), lineWidth: lineWidth))
            }
        }
        return result
    }

    /// Lenient selection hit-testing in image pixels.
    func hitTest(_ point: PixelPoint, tolerance: Double = 8) -> Bool {
        if tool == .ellipse, case let .box(pixelRect) = geometry {
            let rect = pixelRect.standardized
            let radiusX = rect.width / 2
            let radiusY = rect.height / 2
            guard radiusX > 0, radiusY > 0 else { return false }
            let normalizedDistance = sqrt(
                pow((point.x - rect.midX) / radiusX, 2)
                    + pow((point.y - rect.midY) / radiusY, 2)
            )
            let normalizedTolerance = (tolerance + (style.lineWidth / 2)) / min(radiusX, radiusY)
            return style.fillColor != nil
                ? normalizedDistance <= 1 + normalizedTolerance
                : abs(normalizedDistance - 1) <= normalizedTolerance
        }

        if tool == .rectangle {
            let rect = bounds.standardized
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance + style.lineWidth, dy: tolerance + style.lineWidth)
            return outer.contains(point) && (!inner.contains(point) || style.fillColor != nil)
        }

        switch geometry {
        case let .stroke(points):
            return points.adjacentPairs.contains {
                point.distanceToSegment(from: $0.0, to: $0.1) <= tolerance + (style.lineWidth / 2)
            } || (points.first?.distance(to: point) ?? .greatestFiniteMagnitude) <= tolerance
        case let .segment(start, end):
            let threshold = tolerance + (style.lineWidth / 2)
            if point.distanceToSegment(from: start, to: end) <= threshold {
                return true
            }
            guard let arrowWingPoints else { return false }
            return point.distanceToSegment(from: end, to: arrowWingPoints.left) <= threshold
                || point.distanceToSegment(from: end, to: arrowWingPoints.right) <= threshold
        case .box, .text, .region:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }
}

private extension Annotation {
    var arrowWingPoints: (left: PixelPoint, right: PixelPoint)? {
        guard tool == .arrow, case let .segment(start, end) = geometry else { return nil }
        let length = start.distance(to: end)
        guard length > 0 else { return nil }
        let headLength = min(max(style.arrowHeadLength, style.lineWidth * 2.8), length * 0.46)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let spread = Double.pi / 6
        return (
            PixelPoint(
                x: end.x - (headLength * cos(angle - spread)),
                y: end.y - (headLength * sin(angle - spread))
            ),
            PixelPoint(
                x: end.x - (headLength * cos(angle + spread)),
                y: end.y - (headLength * sin(angle + spread))
            )
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension PixelPoint {
    func distanceToSegment(from start: PixelPoint, to end: PixelPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else { return distance(to: start) }
        let projection = (((x - start.x) * dx) + ((y - start.y) * dy)) / lengthSquared
        let t = min(max(projection, 0), 1)
        return distance(to: PixelPoint(x: start.x + (t * dx), y: start.y + (t * dy)))
    }
}

private extension Array {
    var adjacentPairs: [(Element, Element)] {
        guard count > 1 else { return [] }
        return zip(self, dropFirst()).map { ($0, $1) }
    }
}
