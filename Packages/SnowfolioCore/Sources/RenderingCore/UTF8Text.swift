import Darwin
import Foundation

/// Byte identity for syntax-bearing text. Native reused storage takes a pointer
/// fast path; distinct contiguous buffers use bounded comparison. Foreign storage
/// first rejects different UTF-16 lengths, then compares Foundation’s bulk UTF-8 conversion.
/// No borrowed pointer escapes and canonical Unicode equivalence is not identity.
public enum UTF8Text {
  public static func equal(_ lhs: String, _ rhs: String) -> Bool {
    if let result = lhs.utf8.withContiguousStorageIfAvailable({ left -> Bool? in
      rhs.utf8.withContiguousStorageIfAvailable { right in equalBytes(left, right) }
    }), let equal = result {
      return equal
    }
    // NSTextView snapshots commonly retain foreign NSString storage. Walking its
    // UTF-8 iterator calls through NSString for each scalar and makes end-of-file
    // typing/reflection proportional to the entire matching prefix.
    guard lhs.utf16.count == rhs.utf16.count else { return false }
    let first = lhs as NSString
    let second = rhs as NSString
    // Keep both owners alive while borrowing their encoded buffers. The explicit
    // length includes embedded NULs; strcmp/strlen would lose source distinctions.
    // A comparison can run outside NSApplication’s event pool (for example in
    // batch exports). Release Foundation’s temporary encoded buffers immediately.
    return autoreleasepool {
      withExtendedLifetime((first, second)) {
        guard let left = first.utf8String, let right = second.utf8String else {
          // An NSString can contain an unpaired surrogate. Swift’s UTF-8 view
          // repairs those; retain that exact behavior when Foundation cannot encode.
          return lhs.utf8.elementsEqual(rhs.utf8)
        }
        let count = first.lengthOfBytes(using: String.Encoding.utf8.rawValue)
        guard count == second.lengthOfBytes(using: String.Encoding.utf8.rawValue) else {
          return false
        }
        return count == 0 || left == right || memcmp(left, right, count) == 0
      }
    }
  }

  private static func equalBytes(
    _ left: UnsafeBufferPointer<UInt8>, _ right: UnsafeBufferPointer<UInt8>
  ) -> Bool {
    guard left.count == right.count else { return false }
    guard !left.isEmpty else { return true }
    guard let first = left.baseAddress, let second = right.baseAddress else { return false }
    return first == second || memcmp(first, second, left.count) == 0
  }
}
