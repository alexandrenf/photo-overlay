#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_icon.swift <AppIcon.iconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024)
]

for variant in variants {
    let size = variant.pixels
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let scale = CGFloat(size)
    let canvas = CGRect(x: 0, y: 0, width: scale, height: scale)
    context.clear(canvas)

    let tile = canvas.insetBy(dx: scale * 0.055, dy: scale * 0.055)
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: scale * 0.215,
        cornerHeight: scale * 0.215,
        transform: nil
    )
    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(red: 0.20, green: 0.28, blue: 0.95, alpha: 1),
            CGColor(red: 0.12, green: 0.66, blue: 0.95, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY),
        options: []
    )

    // Soft highlight gives the tile the depth of a native macOS icon.
    context.setFillColor(CGColor(gray: 1, alpha: 0.12))
    context.fillEllipse(in: CGRect(x: -scale * 0.12, y: scale * 0.45, width: scale * 0.92, height: scale * 0.82))
    context.restoreGState()

    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Image frame.
    let frame = CGRect(x: scale * 0.20, y: scale * 0.23, width: scale * 0.60, height: scale * 0.54)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.97))
    context.setLineWidth(scale * 0.057)
    context.addPath(
        CGPath(
            roundedRect: frame,
            cornerWidth: scale * 0.085,
            cornerHeight: scale * 0.085,
            transform: nil
        )
    )
    context.strokePath()

    // Photo horizon.
    context.setLineWidth(scale * 0.044)
    context.move(to: CGPoint(x: scale * 0.27, y: scale * 0.36))
    context.addLine(to: CGPoint(x: scale * 0.42, y: scale * 0.52))
    context.addLine(to: CGPoint(x: scale * 0.53, y: scale * 0.42))
    context.addLine(to: CGPoint(x: scale * 0.69, y: scale * 0.58))
    context.strokePath()

    // Annotation stroke and endpoint.
    context.setStrokeColor(CGColor(red: 1.0, green: 0.84, blue: 0.20, alpha: 1))
    context.setLineWidth(scale * 0.072)
    context.move(to: CGPoint(x: scale * 0.31, y: scale * 0.70))
    context.addCurve(
        to: CGPoint(x: scale * 0.72, y: scale * 0.34),
        control1: CGPoint(x: scale * 0.43, y: scale * 0.88),
        control2: CGPoint(x: scale * 0.64, y: scale * 0.57)
    )
    context.strokePath()
    context.setFillColor(CGColor(red: 1.0, green: 0.84, blue: 0.20, alpha: 1))
    context.fillEllipse(
        in: CGRect(
            x: scale * 0.685,
            y: scale * 0.305,
            width: scale * 0.07,
            height: scale * 0.07
        )
    )

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputDirectory.appendingPathComponent(variant.name), options: .atomic)
}
