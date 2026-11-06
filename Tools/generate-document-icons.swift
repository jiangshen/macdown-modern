import AppKit
import Foundation

// Original vector artwork; the OS supplies the modern document shape through UTTypeIcons.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fm = FileManager.default
let catalog = output.appendingPathComponent("DocumentIcons.xcassets")
try fm.createDirectory(at: catalog, withIntermediateDirectories: true)
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}\n".utf8).write(
  to: catalog.appendingPathComponent("Contents.json"))

func monogram(_ context: CGContext, size: CGFloat, white: Bool) {
  context.saveGState()
  let factor = size * 0.90 / 438
  context.translateBy(x: size * 0.05, y: (size - 228 * factor) / 2)
  context.scaleBy(x: factor, y: factor)
  context.setFillColor(
    (white ? NSColor.white : NSColor(srgbRed: 0.18, green: 0.43, blue: 0.62, alpha: 1)).cgColor)
  let paths: [[CGPoint]] = [
    [
      [0, 0], [62, 0], [136, 106], [210, 0], [272, 0], [272, 228], [210, 228], [210, 104],
      [136, 210], [62, 104], [62, 228], [0, 228],
    ].map { CGPoint(x: $0[0], y: $0[1]) },
    [[334, 0], [398, 0], [398, 124], [438, 124], [366, 214], [294, 124], [334, 124]].map {
      CGPoint(x: $0[0], y: $0[1])
    },
  ]
  for points in paths {
    context.beginPath()
    context.addLines(between: points)
    context.closePath()
    context.fillPath()
  }
  context.restoreGState()
}

func gradient(_ context: CGContext, size: CGFloat) {
  let colors =
    [
      NSColor(srgbRed: 0.49, green: 0.79, blue: 0.94, alpha: 1).cgColor,
      NSColor(srgbRed: 0.20, green: 0.53, blue: 0.77, alpha: 1).cgColor,
    ] as CFArray
  guard
    let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
  else { fatalError("Gradient") }
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
}

func png(size: Int, kind: String) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
  else { fatalError("Bitmap") }
  let context = graphics.cgContext
  context.clear(CGRect(x: 0, y: 0, width: size, height: size))
  context.translateBy(x: 0, y: CGFloat(size))
  context.scaleBy(x: 1, y: -1)
  let dimension = CGFloat(size)
  if kind == "background" {
    gradient(context, size: dimension)
  } else if kind == "badge" {
    monogram(context, size: dimension, white: true)
  } else {
    context.scaleBy(x: dimension / 1024, y: dimension / 1024)
    let paper = CGMutablePath()
    paper.move(to: CGPoint(x: 228, y: 64))
    paper.addLine(to: CGPoint(x: 632, y: 64))
    paper.addLine(to: CGPoint(x: 832, y: 264))
    paper.addLine(to: CGPoint(x: 832, y: 904))
    paper.addQuadCurve(to: CGPoint(x: 784, y: 952), control: CGPoint(x: 832, y: 952))
    paper.addLine(to: CGPoint(x: 228, y: 952))
    paper.addQuadCurve(to: CGPoint(x: 180, y: 904), control: CGPoint(x: 180, y: 952))
    paper.addLine(to: CGPoint(x: 180, y: 112))
    paper.addQuadCurve(to: CGPoint(x: 228, y: 64), control: CGPoint(x: 180, y: 64))
    paper.closeSubpath()
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: 10), blur: 14,
      color: NSColor.black.withAlphaComponent(0.18).cgColor)
    context.setFillColor(NSColor.white.cgColor)
    context.addPath(paper)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(paper)
    context.clip()
    gradient(context, size: 1024)
    context.restoreGState()
    context.setFillColor(NSColor(srgbRed: 0.74, green: 0.89, blue: 0.98, alpha: 1).cgColor)
    context.beginPath()
    context.move(to: CGPoint(x: 632, y: 64))
    context.addLine(to: CGPoint(x: 832, y: 264))
    context.addLine(to: CGPoint(x: 672, y: 264))
    context.addQuadCurve(to: CGPoint(x: 632, y: 224), control: CGPoint(x: 632, y: 264))
    context.closePath()
    context.fillPath()
    context.saveGState()
    context.translateBy(x: 264, y: 304)
    monogram(context, size: 496, white: true)
    context.restoreGState()
    context.setFillColor(NSColor.white.withAlphaComponent(0.42).cgColor)
    context.fill(CGRect(x: 300, y: 720, width: 424, height: 12))
    context.fill(CGRect(x: 300, y: 764, width: 300, height: 12))
  }
  guard let result = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG") }
  return result
}

let slots: [(String, Int)] = [
  ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
  ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512),
  ("512x512@2x", 1024),
]
for (name, kind) in [
  ("MarkdownDocumentBackground", "background"), ("MarkdownDocumentBadge", "badge"),
  ("MarkdownDocument", "document"),
] {
  let directory =
    kind == "document"
    ? output.appendingPathComponent("MarkdownDocument.iconset")
    : catalog.appendingPathComponent(name + ".iconset")
  try fm.createDirectory(at: directory, withIntermediateDirectories: true)
  for (slot, size) in slots {
    try png(size: size, kind: kind).write(
      to: directory.appendingPathComponent("icon_" + slot + ".png"))
  }
}
print("Generated glacial document icon assets")
