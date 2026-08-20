import AppKit
import Foundation

/// A point in the source image's native pixel coordinate system.
///
/// The origin is the image's top-left corner. Keeping editor geometry in image
/// pixels makes annotations independent from window size, backing scale, zoom,
/// and the size of the overlay canvas.
public struct PixelPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    public static let zero = PixelPoint(x: 0, y: 0)

    public func distance(to other: PixelPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }

    public func clamped(to size: PixelSize) -> PixelPoint {
        PixelPoint(
            x: min(max(x, 0), size.width),
            y: min(max(y, 0), size.height)
        )
    }
}

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public static let zero = PixelSize(width: 0, height: 0)
}

public struct PixelRect: Codable, Hashable, Sendable {
    public var origin: PixelPoint
    public var size: PixelSize

    public init(origin: PixelPoint, size: PixelSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(
            origin: PixelPoint(x: x, y: y),
            size: PixelSize(width: width, height: height)
        )
    }

    public init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    public init(from start: PixelPoint, to end: PixelPoint) {
        self.init(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    public var x: Double {
        get { origin.x }
        set { origin.x = newValue }
    }

    public var y: Double {
        get { origin.y }
        set { origin.y = newValue }
    }

    public var width: Double {
        get { size.width }
        set { size.width = newValue }
    }

    public var height: Double {
        get { size.height }
        set { size.height = newValue }
    }

    public var minX: Double { min(x, x + width) }
    public var minY: Double { min(y, y + height) }
    public var maxX: Double { max(x, x + width) }
    public var maxY: Double { max(y, y + height) }
    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }
    public var isEmpty: Bool { width == 0 || height == 0 }
    public var standardized: PixelRect {
        PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public var cgRect: CGRect {
        let value = standardized
        return CGRect(x: value.x, y: value.y, width: value.width, height: value.height)
    }

    public func insetBy(dx: Double, dy: Double) -> PixelRect {
        PixelRect(cgRect.insetBy(dx: dx, dy: dy))
    }

    public func offsetBy(dx: Double, dy: Double) -> PixelRect {
        PixelRect(cgRect.offsetBy(dx: dx, dy: dy))
    }

    public func contains(_ point: PixelPoint) -> Bool {
        standardized.cgRect.contains(point.cgPoint)
    }

    public func intersection(_ other: PixelRect) -> PixelRect? {
        let result = standardized.cgRect.intersection(other.standardized.cgRect)
        guard !result.isNull, !result.isEmpty else { return nil }
        return PixelRect(result)
    }

    public func clamped(to imageSize: PixelSize) -> PixelRect? {
        intersection(PixelRect(origin: .zero, size: imageSize))
    }

    public static let zero = PixelRect(origin: .zero, size: .zero)
}

public enum ImageContentMode: String, Codable, CaseIterable, Hashable, Sendable {
    case aspectFit
    case aspectFill
}

/// Converts points between a SwiftUI/AppKit editor surface and image pixels.
/// Both spaces are assumed to use a top-left origin.
public struct ImageViewport: Hashable, Sendable {
    public var imageSize: PixelSize
    public var viewSize: PixelSize
    public var contentMode: ImageContentMode
    public var zoom: Double
    /// Pan is expressed in view points after fitting and zooming.
    public var pan: PixelPoint

    public init(
        imageSize: PixelSize,
        viewSize: PixelSize,
        contentMode: ImageContentMode = .aspectFit,
        zoom: Double = 1,
        pan: PixelPoint = .zero
    ) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.contentMode = contentMode
        self.zoom = max(zoom, 0.01)
        self.pan = pan
    }

    public init(
        imageSize: CGSize,
        viewSize: CGSize,
        contentMode: ImageContentMode = .aspectFit,
        zoom: Double = 1,
        pan: CGPoint = .zero
    ) {
        self.init(
            imageSize: PixelSize(imageSize),
            viewSize: PixelSize(viewSize),
            contentMode: contentMode,
            zoom: zoom,
            pan: PixelPoint(pan)
        )
    }

    public var baseScale: Double {
        guard !imageSize.isEmpty, !viewSize.isEmpty else { return 1 }
        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        return contentMode == .aspectFit
            ? min(widthScale, heightScale)
            : max(widthScale, heightScale)
    }

    public var scale: Double { baseScale * zoom }

    public var imageRectInView: PixelRect {
        let rendered = PixelSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return PixelRect(
            x: ((viewSize.width - rendered.width) / 2) + pan.x,
            y: ((viewSize.height - rendered.height) / 2) + pan.y,
            width: rendered.width,
            height: rendered.height
        )
    }

    public func pixelPoint(fromViewPoint point: CGPoint, clamped: Bool = true) -> PixelPoint {
        guard scale > 0 else { return .zero }
        let rect = imageRectInView
        let result = PixelPoint(
            x: (point.x - rect.x) / scale,
            y: (point.y - rect.y) / scale
        )
        return clamped ? result.clamped(to: imageSize) : result
    }

    public func viewPoint(fromPixelPoint point: PixelPoint) -> CGPoint {
        let rect = imageRectInView
        return CGPoint(
            x: rect.x + (point.x * scale),
            y: rect.y + (point.y * scale)
        )
    }

    public func pixelRect(fromViewRect rect: CGRect, clamped: Bool = true) -> PixelRect? {
        let result = PixelRect(
            from: pixelPoint(fromViewPoint: rect.origin, clamped: clamped),
            to: pixelPoint(
                fromViewPoint: CGPoint(x: rect.maxX, y: rect.maxY),
                clamped: clamped
            )
        )
        guard !result.isEmpty else { return nil }
        return result
    }

    public func viewRect(fromPixelRect rect: PixelRect) -> CGRect {
        let standardized = rect.standardized
        let origin = viewPoint(fromPixelPoint: standardized.origin)
        return CGRect(
            origin: origin,
            size: CGSize(
                width: standardized.width * scale,
                height: standardized.height * scale
            )
        )
    }

    /// Converts a desired width in view points to a stable image-pixel width.
    public func pixelLength(fromViewLength length: Double) -> Double {
        length / max(scale, 0.000_001)
    }
}
