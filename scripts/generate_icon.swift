#!/usr/bin/env swift

import AppKit
import Foundation

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        return image
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let inset = size * 0.055
    let iconRect = CGRect(x: inset, y: inset, width: size - (2 * inset), height: size - (2 * inset))
    let iconPath = NSBezierPath(
        roundedRect: iconRect,
        xRadius: size * 0.22,
        yRadius: size * 0.22
    )

    iconPath.addClip()

    if let baseGradient = NSGradient(colors: [
        NSColor(hex: 0x0C2248),
        NSColor(hex: 0x123166),
        NSColor(hex: 0x0A1D3F)
    ]) {
        baseGradient.draw(in: iconPath, angle: 90)
    }

    let highlightRect = iconRect.insetBy(dx: size * 0.08, dy: size * 0.09)
    let highlightPath = NSBezierPath(
        roundedRect: highlightRect,
        xRadius: size * 0.16,
        yRadius: size * 0.16
    )
    NSColor(hex: 0x4E8EF8, alpha: 0.25).setFill()
    highlightPath.fill()

    let bodyWidth = size * 0.165
    let bodyHeight = size * 0.31
    let bodyRect = CGRect(
        x: (size - bodyWidth) / 2,
        y: size * 0.33,
        width: bodyWidth,
        height: bodyHeight
    )
    let bodyPath = NSBezierPath(
        roundedRect: bodyRect,
        xRadius: bodyWidth * 0.5,
        yRadius: bodyWidth * 0.5
    )

    if let bodyGradient = NSGradient(colors: [
        NSColor(hex: 0xFFBE58),
        NSColor(hex: 0xF18D2D)
    ]) {
        bodyGradient.draw(in: bodyPath, angle: 90)
    }

    let stemRect = CGRect(
        x: (size * 0.5) - (size * 0.02),
        y: size * 0.26,
        width: size * 0.04,
        height: size * 0.09
    )
    let stemPath = NSBezierPath(
        roundedRect: stemRect,
        xRadius: size * 0.02,
        yRadius: size * 0.02
    )
    NSColor.white.withAlphaComponent(0.94).setFill()
    stemPath.fill()

    let baseRect = CGRect(
        x: (size * 0.5) - (size * 0.11),
        y: size * 0.22,
        width: size * 0.22,
        height: size * 0.045
    )
    let basePath = NSBezierPath(
        roundedRect: baseRect,
        xRadius: size * 0.022,
        yRadius: size * 0.022
    )
    NSColor.white.withAlphaComponent(0.92).setFill()
    basePath.fill()

    let ringRect = CGRect(
        x: size * 0.26,
        y: size * 0.32,
        width: size * 0.48,
        height: size * 0.20
    )
    let ringPath = NSBezierPath(ovalIn: ringRect)
    ringPath.lineWidth = size * 0.018
    NSColor(hex: 0x8AB5FF, alpha: 0.36).setStroke()
    ringPath.stroke()

    iconPath.lineWidth = size * 0.018
    NSColor.white.withAlphaComponent(0.1).setStroke()
    iconPath.stroke()

    return image
}

private func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "NativeWhisperIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }

    try pngData.write(to: url)
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = cwd.appendingPathComponent("NativeWhisper/Resources/AppIcon.iconset")
let outputURL = iconsetURL.appendingPathComponent("icon_512x512@2x.png")

let icon = drawIcon(size: 1024)
try writePNG(icon, to: outputURL)
print("Generated \(outputURL.path)")
