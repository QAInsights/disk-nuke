#!/usr/bin/env swift
// Generates AppIcon PNGs for Disk Nuke: a dark slate rounded-rect disk with a
// platter and highlight ring, overlaid with a yellow/orange radiation trefoil.
// Usage: swift Scripts/generate_icon.swift  (run from the repo root)

import AppKit
import CoreGraphics
import Foundation

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "32x32"), (128, "128x128"), (256, "256x256"), (512, "512x512"),
]
let scales = [1, 2]

func drawIcon(size s: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Rounded-rect disk body (macOS icon squircle-ish, ~22.5% radius).
    let inset = s * 0.02
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 0.225
    let bodyPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Dark slate gradient, slightly diagonal.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 0.23, green: 0.27, blue: 0.33, alpha: 1),
        CGColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Platter circle.
    let platterR = s * 0.34
    let center = CGPoint(x: s / 2, y: s / 2)
    let platterGrad = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1),
        CGColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - platterR, y: center.y - platterR,
                              width: platterR * 2, height: platterR * 2))
    ctx.clip()
    ctx.drawRadialGradient(platterGrad,
                           startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: platterR,
                           options: [])
    ctx.restoreGState()

    // Highlight ring around the platter.
    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 0.35))
    ctx.setLineWidth(s * 0.012)
    ctx.strokeEllipse(in: CGRect(x: center.x - platterR, y: center.y - platterR,
                                 width: platterR * 2, height: platterR * 2))
    // Spindle hub.
    ctx.setFillColor(CGColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - s * 0.045, y: center.y - s * 0.045,
                               width: s * 0.09, height: s * 0.09))
    ctx.restoreGState()

    // Radiation trefoil: center disc + three 60° wedge blades.
    let trefoilCenter = CGPoint(x: s * 0.5, y: s * 0.50)
    let trefoilR = s * 0.24
    let bladeStart = trefoilR * 0.34
    let bladeSpan: CGFloat = .pi / 3   // 60°
    let gap: CGFloat = .pi / 30
    ctx.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 1))

    for i in 0..<3 {
        let a = CGFloat(i) * (2 * .pi / 3) - .pi / 2
        let path = CGMutablePath()
        path.move(to: trefoilCenter)
        path.addArc(center: trefoilCenter, radius: trefoilR,
                    startAngle: a - bladeSpan / 2 + gap,
                    endAngle: a + bladeSpan / 2 - gap, clockwise: false)
        path.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008),
                      blur: s * 0.02,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }
    // Center hub disc.
    ctx.setFillColor(CGColor(red: 1.0, green: 0.72, blue: 0.05, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: trefoilCenter.x - bladeStart, y: trefoilCenter.y - bladeStart,
                               width: bladeStart * 2, height: bladeStart * 2))

    // Subtle top highlight on the body.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let hiGrad = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.14),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray, locations: [0, 0.45])!
    ctx.drawLinearGradient(hiGrad, start: CGPoint(x: s / 2, y: s),
                           end: CGPoint(x: s / 2, y: s * 0.4), options: [])
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixelSize: Int, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    // Ensure exact pixel size.
    let scaled = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    scaled.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
               from: .zero, operation: .sourceOver, fraction: 1)
    scaled.unlockFocus()
    guard let t = scaled.tiffRepresentation,
          let r = NSBitmapImageRep(data: t),
          let data = r.representation(using: .png, properties: [:]) else {
        try png.write(to: url)
        return
    }
    try data.write(to: url)
}

let root = FileManager.default.currentDirectoryPath
let iconset = URL(fileURLWithPath: root)
    .appendingPathComponent("DiskNuke/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

var images: [[String: String]] = []
for (pt, idiom) in sizes {
    for scale in scales {
        let px = pt * scale
        let filename = "icon_\(idiom)@\(scale)x.png"
        let dest = iconset.appendingPathComponent(filename)
        try writePNG(drawIcon(size: 512), pixelSize: px, to: dest)
        images.append([
            "size": idiom,
            "idiom": "mac",
            "filename": filename,
            "scale": "\(scale)x",
        ])
        print("wrote \(filename)")
    }
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: iconset.appendingPathComponent("Contents.json"))
print("wrote Contents.json")
