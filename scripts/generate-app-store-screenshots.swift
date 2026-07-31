#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let canvasSize = NSSize(width: 1440, height: 900)
private let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let assets = projectRoot.appendingPathComponent("AppStoreAssets/Screenshots")
private let output = assets.appendingPathComponent("Final", isDirectory: true)

private struct ScreenshotSpec {
    let filename: String
    let headline: String
    let subheadline: String
    let imageName: String
    let imageFrame: NSRect
    let sourceCrop: NSRect?
    let chips: [String]
}

private let specs = [
    ScreenshotSpec(
        filename: "01-dictee.png",
        headline: "Dictez. Pressay\ns’occupe du reste.",
        subheadline: "Une barre vocale simple, depuis le menu de macOS.",
        imageName: "raw-settings.png",
        imageFrame: NSRect(x: 880, y: 54, width: 480, height: 757),
        sourceCrop: nil,
        chips: ["Sans compte Pressay", "Historique local chiffré"]
    ),
    ScreenshotSpec(
        filename: "02-menu.png",
        headline: "Une dictée à\nportée de clic.",
        subheadline: "Parlez, récupérez le texte, continuez votre travail.",
        imageName: "raw-menubar.png",
        imageFrame: NSRect(x: 790, y: 136, width: 540, height: 540),
        sourceCrop: nil,
        chips: ["Barre des menus", "Copie instantanée", "Voice Inbox optionnelle"]
    ),
    ScreenshotSpec(
        filename: "03-modes.png",
        headline: "12 modes pour\nécrire juste.",
        subheadline: "Adaptez chaque dictée à votre intention.",
        imageName: "raw-modes.png",
        imageFrame: NSRect(x: 754, y: 300, width: 610, height: 300),
        // XCTest attachments are Retina images: NSImage exposes point dimensions.
        sourceCrop: NSRect(x: 250, y: 352, width: 610, height: 300),
        chips: ["Fidèle", "Message", "Email", "Ticket", "Traduction", "Résumé"]
    )
]

private func image(named name: String) throws -> NSImage {
    let url = assets.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(
            domain: "PressayScreenshots",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Image introuvable : \(url.path)"]
        )
    }
    return image
}

private func drawAspectFill(_ image: NSImage, in destination: NSRect) {
    let sourceSize = image.size
    let destinationRatio = destination.width / destination.height
    let sourceRatio = sourceSize.width / sourceSize.height
    let sourceRect: NSRect
    if sourceRatio > destinationRatio {
        let width = sourceSize.height * destinationRatio
        sourceRect = NSRect(
            x: (sourceSize.width - width) / 2,
            y: 0,
            width: width,
            height: sourceSize.height
        )
    } else {
        let height = sourceSize.width / destinationRatio
        sourceRect = NSRect(
            x: 0,
            y: (sourceSize.height - height) / 2,
            width: sourceSize.width,
            height: height
        )
    }
    image.draw(in: destination, from: sourceRect, operation: .copy, fraction: 1)
}

private func drawText(
    _ text: String,
    x: CGFloat,
    top: CGFloat,
    width: CGFloat,
    font: NSFont,
    color: NSColor,
    lineHeight: CGFloat? = nil
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
    let height = attributed.boundingRect(
        with: NSSize(width: width, height: 500),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height.rounded(.up)
    attributed.draw(in: NSRect(
        x: x,
        y: canvasSize.height - top - height,
        width: width,
        height: height
    ))
}

private func drawBrand(icon: NSImage) {
    icon.draw(
        in: NSRect(x: 72, y: 782, width: 56, height: 56),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    drawText(
        "Pressay",
        x: 142,
        top: 70,
        width: 230,
        font: .systemFont(ofSize: 28, weight: .bold),
        color: .white
    )
    drawText(
        "pour macOS",
        x: 142,
        top: 105,
        width: 230,
        font: .systemFont(ofSize: 16, weight: .medium),
        color: NSColor.white.withAlphaComponent(0.65)
    )
}

private func drawChip(_ text: String, at origin: NSPoint) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.92)
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let width = attributed.size().width.rounded(.up) + 34
    let rect = NSRect(x: origin.x, y: origin.y, width: width, height: 42)
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 21, yRadius: 21).fill()
    attributed.draw(at: NSPoint(x: rect.minX + 17, y: rect.minY + 11))
    return width
}

private func drawInterface(
    _ image: NSImage,
    in frame: NSRect,
    sourceCrop: NSRect?
) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.48)
    shadow.shadowBlurRadius = 38
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor(calibratedWhite: 0.05, alpha: 1).setFill()
    NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28).addClip()
    image.draw(
        in: frame,
        from: sourceCrop ?? NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.16).setStroke()
    let border = NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28)
    border.lineWidth = 1.5
    border.stroke()
}

private func render(
    spec: ScreenshotSpec,
    background: NSImage,
    icon: NSImage
) throws {
    guard let bitmapContext = CGContext(
        data: nil,
        width: Int(canvasSize.width),
        height: Int(canvasSize.height),
        bitsPerComponent: 8,
        bytesPerRow: Int(canvasSize.width) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "PressayScreenshots", code: 2)
    }
    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawAspectFill(background, in: NSRect(origin: .zero, size: canvasSize))
    NSColor.black.withAlphaComponent(0.10).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
    drawBrand(icon: icon)
    drawText(
        spec.headline,
        x: 72,
        top: 215,
        width: 650,
        font: .systemFont(ofSize: 58, weight: .bold),
        color: .white,
        lineHeight: 66
    )
    drawText(
        spec.subheadline,
        x: 76,
        top: 370,
        width: 610,
        font: .systemFont(ofSize: 23, weight: .medium),
        color: NSColor.white.withAlphaComponent(0.76),
        lineHeight: 31
    )

    var chipX: CGFloat = 76
    var chipY: CGFloat = 300
    for chip in spec.chips {
        let estimatedWidth = CGFloat(chip.count * 10 + 34)
        if chipX + estimatedWidth > 690 {
            chipX = 76
            chipY -= 56
        }
        let width = drawChip(chip, at: NSPoint(x: chipX, y: chipY))
        chipX += width + 12
    }

    drawInterface(
        try image(named: spec.imageName),
        in: spec.imageFrame,
        sourceCrop: spec.sourceCrop
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = bitmapContext.makeImage() else {
        throw NSError(domain: "PressayScreenshots", code: 3)
    }
    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let data = representation.representation(
        using: .png,
        properties: [:]
    ) else {
        throw NSError(domain: "PressayScreenshots", code: 4)
    }
    try data.write(
        to: output.appendingPathComponent(spec.filename),
        options: .atomic
    )
}

try FileManager.default.createDirectory(
    at: output,
    withIntermediateDirectories: true
)
let background = try image(named: "background-voice-waves.png")
let icon = try NSImage(
    contentsOf: projectRoot.appendingPathComponent(
        "Pressay/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png"
    )
).unwrap(or: "Icône Pressay introuvable")

for spec in specs {
    try render(spec: spec, background: background, icon: icon)
    print("Créé : \(output.appendingPathComponent(spec.filename).path)")
}

private extension Optional {
    func unwrap(or message: String) throws -> Wrapped {
        guard let value = self else {
            throw NSError(
                domain: "PressayScreenshots",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return value
    }
}
