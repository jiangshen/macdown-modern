#if NATIVE_DOCUMENT_HOST
  import CoreGraphics
  import Foundation
  import ImageIO

  /// A test-only sample of actual rendered source glyphs. It neither asks the
  /// editor to reveal its caret nor depends on machine-learning model availability.
  struct SourceReadingSnapshot {
    let width: Int
    let height: Int
    let ink: [Bool]
    let maximumShift: Int

    /// Decode the public screenshot data directly. The sampling code needs a
    /// CGImage, not AppKit's display-dependent NSBitmapImageRep representation.
    static func decodeScreenshotPNG(_ data: Data) throws -> CGImage {
      guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        CGImageSourceGetStatus(source) == .statusComplete,
        let image = CGImageSourceCreateImageAtIndex(
          source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
      else { throw failure("Cannot decode complete screenshot PNG (\(data.count) bytes)") }
      return image
    }

    init(image: CGImage, readingRect: CGRect, backgroundPoint: CGPoint, maximumShift: Int) throws {
      let fullWidth = image.width
      let fullHeight = image.height
      let x = Int(readingRect.minX.rounded())
      let y = Int(readingRect.minY.rounded())
      width = Int(readingRect.width.rounded())
      height = Int(readingRect.height.rounded())
      self.maximumShift = maximumShift
      guard x >= 0, y >= 0, width > maximumShift * 2, height > maximumShift * 2,
        x + width <= fullWidth, y + height <= fullHeight
      else { throw Self.failure("Invalid source reading sample bounds") }
      var rgba = [UInt8](repeating: 0, count: fullWidth * fullHeight * 4)
      let drawn = rgba.withUnsafeMutableBytes { buffer in
        guard
          let context = CGContext(
            data: buffer.baseAddress, width: fullWidth, height: fullHeight,
            bitsPerComponent: 8, bytesPerRow: fullWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight))
        return true
      }
      guard drawn else { throw Self.failure("Cannot read source screenshot") }
      func luminance(_ offset: Int) -> Int {
        (Int(rgba[offset]) * 2126 + Int(rgba[offset + 1]) * 7152
          + Int(rgba[offset + 2]) * 722) / 10000
      }
      // The unselected text view's left inset supplies its background color.
      let backgroundX = Int(backgroundPoint.x.rounded())
      let backgroundY = Int(backgroundPoint.y.rounded())
      guard (0..<fullWidth).contains(backgroundX), (0..<fullHeight).contains(backgroundY) else {
        throw Self.failure("Invalid source background sample")
      }
      let background = luminance((backgroundY * fullWidth + backgroundX) * 4)
      var pixels: [Bool] = []
      pixels.reserveCapacity(width * height)
      for row in y..<(y + height) {
        for column in x..<(x + width) {
          pixels.append(abs(luminance((row * fullWidth + column) * 4) - background) >= 80)
        }
      }
      guard pixels.filter({ $0 }).count >= 50 else {
        throw Self.failure("Source glyphs have not painted in the reading sample")
      }
      ink = pixels
    }

    /// Permit only a small raster rounding shift. Compare ink rather than the
    /// mostly blank background, so a changed paragraph number cannot hide in it.
    func difference(from other: Self) -> Double {
      guard width == other.width, height == other.height else { return 1 }
      let shift = max(maximumShift, other.maximumShift)
      var best = 1.0
      for dy in -shift...shift {
        for dx in -shift...shift {
          var different = 0
          var total = 0
          for row in shift..<(height - shift) {
            for column in shift..<(width - shift) {
              let a = ink[row * width + column]
              let b = other.ink[(row + dy) * width + column + dx]
              if a || b { total += 1 }
              if a != b { different += 1 }
            }
          }
          if total > 0 { best = min(best, Double(different) / Double(total)) }
        }
      }
      return best
    }

    private static func failure(_ message: String) -> NSError {
      NSError(
        domain: "SnowfolioSourceReadingSnapshot", code: 1,
        userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
#endif
