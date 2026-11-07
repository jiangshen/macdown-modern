import Darwin

/// Byte identity for syntax-bearing text. Native reused storage takes a pointer
/// fast path; distinct contiguous buffers use bounded comparison. No pointer
/// escapes either borrow. Foreign storage retains the safe collection fallback.
public enum UTF8Text {
  public static func equal(_ lhs: String, _ rhs: String) -> Bool {
    if let result = lhs.utf8.withContiguousStorageIfAvailable({ left -> Bool? in
      rhs.utf8.withContiguousStorageIfAvailable { right in
        guard left.count == right.count else { return false }
        guard !left.isEmpty else { return true }
        guard let first = left.baseAddress, let second = right.baseAddress else { return false }
        if first == second { return true }
        return memcmp(first, second, left.count) == 0
      }
    }), let equal = result {
      return equal
    }
    return lhs.utf8.elementsEqual(rhs.utf8)
  }
}
