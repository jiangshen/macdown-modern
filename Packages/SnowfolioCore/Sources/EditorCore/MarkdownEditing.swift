import Foundation

public struct EditorBehavior: Equatable, Sendable {
  public var convertTabs = false
  public var continueBlocks = true
  public var incrementLists = true
  public var pairDelimiters = false
  public var unorderedMarker = "*"
  public init() {}
}

public enum MarkdownCommand: Sendable {
  case bold, italic, inlineCode, strikethrough, highlight, underline, comment
  case heading(Int)
  case paragraph, orderedList, unorderedList, blockquote, indent, outdent
  case link(String?)
  case image(String?)
  case toggleTask, newParagraph
}

public enum MarkdownInput: Sendable { case newline, tab, backtab, backspace }

/// A minimal native replacement and the resulting UTF-16 selection. The adapter
/// applies only this range through NSTextView, retaining native undo and TextKit 2.
public struct EditorTransaction: Sendable {
  public let edit: TextEdit
  public let selection: NSRange
  public init(edit: TextEdit, selection: NSRange) {
    self.edit = edit
    self.selection = selection
  }
}

public enum MarkdownEditing {
  public static func transaction(
    for command: MarkdownCommand, in text: String, selection: NSRange,
    behavior: EditorBehavior = .init()
  ) throws -> EditorTransaction? {
    try TextEdit.validate(selection, in: text)
    switch command {
    case .bold: return try toggleInline(in: text, selection: selection, prefix: "**", suffix: "**")
    case .italic:
      return try toggleInline(
        in: text, selection: selection, prefix: "*", suffix: "*", distinguishStrong: true)
    case .underline:
      // Preserve an existing __strong__ span: three underscores mean combined
      // emphasis in the legacy dialect, so use equivalent star markers for bold.
      let string = text as NSString
      let left = string.substring(to: selection.location)
      let right = string.substring(from: NSMaxRange(selection))
      if left.hasSuffix("__"), right.hasPrefix("__"),
        !left.hasSuffix("___"), !right.hasPrefix("___")
      {
        let content = string.substring(with: selection)
        return EditorTransaction(
          edit: TextEdit(
            range: NSRange(location: selection.location - 2, length: selection.length + 4),
            replacement: "**_" + content + "_**"),
          selection: NSRange(location: selection.location + 1, length: selection.length))
      }
      return try toggleInline(in: text, selection: selection, prefix: "_", suffix: "_")
    case .highlight:
      return try toggleInline(in: text, selection: selection, prefix: "==", suffix: "==")
    case .strikethrough:
      return try toggleInline(in: text, selection: selection, prefix: "~~", suffix: "~~")
    case .comment:
      return try toggleInline(in: text, selection: selection, prefix: "<!--", suffix: "-->")
    case .inlineCode:
      let content = (text as NSString).substring(with: selection)
      var longest = 0
      var current = 0
      for scalar in content.unicodeScalars {
        current = scalar == "`" ? current + 1 : 0
        longest = max(longest, current)
      }
      let delimiter = String(repeating: "`", count: longest + 1)
      let pad =
        content.hasPrefix("`") || content.hasSuffix("`")
          || (content.hasPrefix(" ") && content.hasSuffix(" ")
            && !content.allSatisfy(\.isWhitespace))
        ? " " : ""
      return try toggleInline(
        in: text, selection: selection, prefix: delimiter + pad, suffix: pad + delimiter)
    case .link(let destination), .image(let destination):
      let isImage: Bool
      if case .image = command { isImage = true } else { isImage = false }
      let prefix = isImage ? "![" : "["
      let content = (text as NSString).substring(with: selection)
      let url = (destination ?? "").replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        .replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "\n", with: "%0A")
        .replacingOccurrences(of: "\r", with: "%0D")
      return EditorTransaction(
        edit: TextEdit(range: selection, replacement: prefix + content + "](" + url + ")"),
        selection: NSRange(
          location: selection.location + prefix.utf16.count + content.utf16.count + 2,
          length: url.utf16.count))
    case .newParagraph:
      let line = line(at: selection.location, in: text as NSString)
      let ending = newline(for: line, in: text as NSString)
      return insertion(ending + (line.content.length == 0 ? "" : ending), selection: selection)
    default:
      return try transformLines(command, in: text, selection: selection, behavior: behavior)
    }
  }

  public static func input(
    _ input: MarkdownInput, in text: String, selection: NSRange,
    behavior: EditorBehavior = .init()
  ) throws -> EditorTransaction? {
    try TextEdit.validate(selection, in: text)
    let string = text as NSString
    let current = line(at: selection.location, in: string)
    switch input {
    case .tab:
      if selection.length > 0 {
        return try transaction(for: .indent, in: text, selection: selection, behavior: behavior)
      }
      guard behavior.convertTabs else { return nil }
      let column = selection.location - current.content.location
      return insertion(String(repeating: " ", count: 4 - column % 4), selection: selection)
    case .backtab:
      return try transaction(for: .outdent, in: text, selection: selection, behavior: behavior)
    case .backspace:
      guard selection.length == 0 else { return nil }
      let cursor = selection.location
      if behavior.pairDelimiters, cursor > 0, cursor < string.length,
        let right = pairs[string.character(at: cursor - 1)], right == string.character(at: cursor)
      {
        return insertion("", selection: NSRange(location: cursor - 1, length: 2))
      }
      guard behavior.convertTabs, cursor > current.content.location else { return nil }
      var count = 0
      while count < 4, cursor - count > current.content.location,
        string.character(at: cursor - count - 1) == 32
      { count += 1 }
      guard count >= 2 else { return nil }
      let column = cursor - current.content.location
      let remove = min(count, column % 4 == 0 ? 4 : column % 4)
      return insertion("", selection: NSRange(location: cursor - remove, length: remove))
    case .newline:
      let ending = newline(for: current, in: string)
      guard selection.length == 0 else { return insertion(ending, selection: selection) }
      let before = string.substring(
        with: NSRange(
          location: current.content.location,
          length: selection.location - current.content.location))
      let prefix = Prefix(before)
      let indent = String(before.prefix { $0 == " " || $0 == "\t" })
      if behavior.continueBlocks, let marker = prefix.list {
        let content = (before as NSString).substring(from: marker.end)
        let taskEnd = taskPrefixLength(content)
        if content.trimmingCharacters(in: .whitespaces).isEmpty
          || (taskEnd > 0
            && (content as NSString).substring(from: taskEnd).trimmingCharacters(in: .whitespaces)
              .isEmpty)
        {
          // Return on an empty item ends it in one undoable edit, retaining the
          // surrounding indentation and any quote prefix.
          let range = NSRange(
            location: current.content.location + marker.start,
            length: selection.location - current.content.location - marker.start)
          return insertion(
            ending
              + string.substring(
                with: NSRange(
                  location: current.content.location,
                  length: marker.start)), selection: range)
        }
        var next = marker.spelling
        if let number = marker.number, behavior.incrementLists, number < 999_999_999 {
          next = "\(number + 1)" + marker.delimiter + " "
        }
        let quoteIndent = (before as NSString).substring(to: marker.start)
        if taskEnd > 0 { next += "[ ] " }
        let suffix = string.substring(from: selection.location)
        let completion = quoteIndent + next
        if suffix.hasPrefix(completion) { return insertion(ending, selection: selection) }
        if !quoteIndent.isEmpty, suffix.hasPrefix(next) {
          return insertion(ending + quoteIndent, selection: selection)
        }
        return insertion(ending + completion, selection: selection)
      }
      if behavior.continueBlocks, prefix.quoteEnd > prefix.indentEnd {
        let quote = (before as NSString).substring(to: prefix.quoteEnd)
        let suffix = string.substring(from: selection.location)
        return insertion(ending + (suffix.hasPrefix(quote) ? "" : quote), selection: selection)
      }
      return insertion(ending + indent, selection: selection)
    }
  }

  /// Called only for a single native key replacement outside marked text. Paste,
  /// dictation and multi-character input retain ordinary NSTextView semantics.
  public static func matchingReplacement(_ replacement: String, in text: String, selection: NSRange)
    throws -> EditorTransaction?
  {
    try TextEdit.validate(selection, in: text)
    guard replacement.utf16.count == 1, let character = replacement.utf16.first else { return nil }
    let string = text as NSString
    if selection.length > 0 {
      let suffix =
        pairs[character] ?? ([42, 95, 96, 61, 126].contains(character) ? character : nil)
      guard let suffix else { return nil }
      let prefix = String(UnicodeScalar(character) ?? " ")
      let closing = String(UnicodeScalar(suffix) ?? " ")
      let content = string.substring(with: selection)
      return EditorTransaction(
        edit: TextEdit(range: selection, replacement: prefix + content + closing),
        selection: NSRange(location: selection.location + 1, length: selection.length))
    }
    let cursor = selection.location
    if pairs.values.contains(character), cursor < string.length,
      string.character(at: cursor) == character
    {
      return EditorTransaction(
        edit: TextEdit(range: selection, replacement: ""),
        selection: NSRange(location: cursor + 1, length: 0))
    }
    guard let closing = pairs[character] else { return nil }
    let boundary = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    func isBoundary(_ offset: Int) -> Bool {
      guard offset >= 0, offset < string.length else { return true }
      guard let scalar = UnicodeScalar(string.character(at: offset)) else { return false }
      return boundary.contains(scalar)
    }
    guard isBoundary(cursor), character != closing || isBoundary(cursor - 1) else { return nil }
    return EditorTransaction(
      edit: TextEdit(
        range: selection, replacement: replacement + String(UnicodeScalar(closing) ?? " ")),
      selection: NSRange(location: cursor + 1, length: 0))
  }

  private static let pairs: [UInt16: UInt16] = [
    40: 41, 91: 93, 123: 125, 60: 62, 39: 39, 34: 34,
    0xFF08: 0xFF09, 0x300C: 0x300D, 0x300E: 0x300F, 0x2018: 0x2019, 0x201C: 0x201D,
    0x2039: 0x203A, 0x00AB: 0x00BB, 0x3008: 0x3009, 0x300A: 0x300B,
  ]

  private static func toggleInline(
    in text: String, selection: NSRange, prefix: String, suffix: String,
    distinguishStrong: Bool = false
  ) throws -> EditorTransaction {
    let string = text as NSString
    let p = prefix.utf16.count
    let s = suffix.utf16.count
    let content = string.substring(with: selection)
    let left = string.substring(to: selection.location)
    let right = string.substring(from: selection.location + selection.length)
    let strongOutside =
      distinguishStrong && left.hasSuffix("**") && right.hasPrefix("**")
      && !(left.hasSuffix("***") && right.hasPrefix("***"))
    if left.hasSuffix(prefix), right.hasPrefix(suffix), !strongOutside {
      return EditorTransaction(
        edit: TextEdit(
          range: NSRange(
            location: selection.location - p,
            length: selection.length + p + s), replacement: content),
        selection: NSRange(location: selection.location - p, length: selection.length))
    }
    let strongInside =
      distinguishStrong && content.hasPrefix("**") && content.hasSuffix("**")
      && !(content.hasPrefix("***") && content.hasSuffix("***"))
    if selection.length >= p + s, content.hasPrefix(prefix), content.hasSuffix(suffix),
      !strongInside
    {
      let inner = (content as NSString).substring(
        with: NSRange(location: p, length: selection.length - p - s))
      return EditorTransaction(
        edit: TextEdit(range: selection, replacement: inner),
        selection: NSRange(location: selection.location, length: inner.utf16.count))
    }
    return EditorTransaction(
      edit: TextEdit(range: selection, replacement: prefix + content + suffix),
      selection: NSRange(location: selection.location + p, length: selection.length))
  }

  private struct Line {
    let content: NSRange
    let full: NSRange
  }
  private static func line(at offset: Int, in text: NSString) -> Line {
    var start = 0
    var end = 0
    var contentsEnd = 0
    text.getLineStart(
      &start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
    return Line(
      content: NSRange(location: start, length: contentsEnd - start),
      full: NSRange(location: start, length: end - start))
  }

  private static func newline(for current: Line, in text: NSString) -> String {
    if current.full.length > current.content.length {
      return text.substring(
        with: NSRange(
          location: current.content.location + current.content.length,
          length: current.full.length - current.content.length))
    }
    if current.content.location > 0 {
      let previous = line(at: current.content.location - 1, in: text)
      if previous.full.length > previous.content.length { return newline(for: previous, in: text) }
    }
    return "\n"
  }

  private static func insertion(_ value: String, selection: NSRange) -> EditorTransaction {
    EditorTransaction(
      edit: TextEdit(range: selection, replacement: value),
      selection: NSRange(location: selection.location + value.utf16.count, length: 0))
  }

  private struct Prefix {
    struct ListMarker {
      let start: Int
      let end: Int
      let spelling: String
      let number: Int?
      let delimiter: String
    }
    let indentEnd: Int
    let quoteEnd: Int
    let list: ListMarker?
    init(_ value: String) {
      let units = Array(value.utf16)
      var index = 0
      while index < units.count && (units[index] == 32 || units[index] == 9) { index += 1 }
      indentEnd = index
      while index < units.count && units[index] == 62 {
        index += 1
        if index < units.count && units[index] == 32 { index += 1 }
      }
      quoteEnd = index
      let start = index
      var number: Int?
      if index < units.count && [42, 43, 45].contains(units[index]) {
        index += 1
      } else {
        var digits = ""
        while index < units.count && (48...57).contains(units[index]) && digits.count < 9 {
          digits.append(Character(UnicodeScalar(units[index]) ?? " "))
          index += 1
        }
        guard !digits.isEmpty, index < units.count && [46, 41].contains(units[index]) else {
          list = nil
          return
        }
        number = Int(digits)
        index += 1
      }
      guard index < units.count && (units[index] == 32 || units[index] == 9) else {
        list = nil
        return
      }
      let delimiter = index > start ? String(UnicodeScalar(units[index - 1]) ?? " ") : "."
      while index < units.count && (units[index] == 32 || units[index] == 9) { index += 1 }
      list = ListMarker(
        start: start, end: index,
        spelling: (value as NSString).substring(
          with: NSRange(location: start, length: index - start)), number: number,
        delimiter: delimiter)
    }
  }

  private static func taskPrefixLength(_ text: String) -> Int {
    let units = Array(text.utf16)
    guard units.count >= 3, units[0] == 91, [32, 88, 120].contains(units[1]), units[2] == 93,
      units.count == 3 || units[3] == 32 || units[3] == 9
    else { return 0 }
    return units.count > 3 ? 4 : 3
  }

  private static func transformLines(
    _ command: MarkdownCommand, in text: String, selection: NSRange,
    behavior: EditorBehavior
  ) throws -> EditorTransaction? {
    let string = text as NSString
    let block = string.lineRange(for: selection)
    var lines: [Line] = []
    var cursor = block.location
    repeat {
      let current = line(at: cursor, in: string)
      lines.append(current)
      cursor = current.full.location + current.full.length
    } while cursor < block.location + block.length
    let contents = lines.map { string.substring(with: $0.content) }
    let prefixes = contents.map(Prefix.init)
    let remove: Bool
    switch command {
    case .orderedList: remove = prefixes.allSatisfy { $0.list?.number != nil }
    case .unorderedList: remove = prefixes.allSatisfy { $0.list != nil && $0.list?.number == nil }
    case .blockquote: remove = prefixes.allSatisfy { $0.quoteEnd > $0.indentEnd }
    default: remove = false
    }
    let allChecked = zip(contents, prefixes).allSatisfy { content, prefix in
      guard let list = prefix.list,
        taskPrefixLength((content as NSString).substring(from: list.end)) > 0
      else { return false }
      return (content as NSString).substring(from: list.end).hasPrefix("[x]")
        || (content as NSString).substring(from: list.end).hasPrefix("[X]")
    }
    var edits: [TextEdit] = []
    for (index, current) in lines.enumerated() {
      let content = contents[index]
      let units = Array(content.utf16)
      let prefix = prefixes[index]
      var start = 0
      var length = 0
      var replacement = ""
      switch command {
      case .indent: replacement = behavior.convertTabs ? "    " : "\t"
      case .outdent:
        while length < min(4, units.count), units[length] == 32 { length += 1 }
        if length < min(4, units.count), units[length] == 9 { length += 1 }
      case .heading, .paragraph:
        let level: Int
        if case .heading(let value) = command { level = value } else { level = 0 }
        guard (0...6).contains(level) else { return nil }
        if lines.count > 1 && content.allSatisfy(\.isWhitespace) { continue }
        start = prefix.indentEnd <= 3 ? prefix.indentEnd : 0
        var end = start
        while end < units.count && units[end] == 35 { end += 1 }
        if end > start, end == units.count || units[end] == 32 || units[end] == 9 {
          while end < units.count && (units[end] == 32 || units[end] == 9) { end += 1 }
          length = end - start
        }
        replacement = level == 0 ? "" : String(repeating: "#", count: level) + " "
      case .orderedList, .unorderedList:
        start = prefix.list?.start ?? prefix.quoteEnd
        length = prefix.list.map { $0.end - $0.start } ?? 0
        if !remove {
          if case .orderedList = command {
            replacement = "\(index + 1). "
          } else {
            replacement =
              (["*", "+", "-"].contains(behavior.unorderedMarker) ? behavior.unorderedMarker : "*")
              + " "
          }
        }
      case .blockquote:
        start = prefix.indentEnd
        if remove {
          length = 1 + ((start + 1 < units.count && units[start + 1] == 32) ? 1 : 0)
        } else {
          replacement = "> "
        }
      case .toggleTask:
        if let marker = prefix.list {
          start = marker.end
          length = taskPrefixLength((content as NSString).substring(from: start))
          replacement = length == 0 || allChecked ? "[ ] " : "[x] "
        } else {
          start = prefix.quoteEnd
          replacement = "- [ ] "
        }
      default: return nil
      }
      if length == 0 && replacement.isEmpty { continue }
      edits.append(
        TextEdit(
          range: NSRange(location: current.content.location + start, length: length),
          replacement: replacement))
    }
    guard !edits.isEmpty else { return nil }
    var replacement = ""
    var position = block.location
    for edit in edits {
      replacement += string.substring(
        with: NSRange(location: position, length: edit.range.location - position))
      replacement += edit.replacement
      position = edit.range.location + edit.range.length
    }
    replacement += string.substring(
      with: NSRange(location: position, length: block.location + block.length - position))
    func mapped(_ offset: Int) -> Int {
      var shift = 0
      for edit in edits {
        if offset < edit.range.location { break }
        if offset < edit.range.location + edit.range.length {
          return edit.range.location + shift + edit.replacement.utf16.count
        }
        shift += edit.replacement.utf16.count - edit.range.length
      }
      return offset + shift
    }
    let start = mapped(selection.location)
    let end = mapped(selection.location + selection.length)
    return EditorTransaction(
      edit: TextEdit(range: block, replacement: replacement),
      selection: NSRange(location: start, length: max(0, end - start)))
  }
}
