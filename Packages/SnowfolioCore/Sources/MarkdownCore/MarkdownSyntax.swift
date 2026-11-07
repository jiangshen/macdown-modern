import Foundation

public enum MarkdownSyntaxToken: Hashable, Sendable {
  case heading(Int)
  case emphasis, strong, inlineCode, codeBlock, link, automaticURL, automaticEmail
  case entity, referenceDefinition, note
  case image, blockquote, comment, inlineHTML, blockHTML, horizontalRule, listBullet, listEnumerator
}

public struct MarkdownSyntaxStyle: Equatable, Sendable {
  public enum Role: Sendable { case text, heading, code, link, quote, comment, marker }
  public var role: Role = .text
  public var tokens: [MarkdownSyntaxToken] = []
  public var highlighted = false
  public var bold = false
  public var italic = false
  public var strikethrough = false
  public var underlined = false

  mutating func include(_ token: MarkdownSyntaxToken) {
    // A nested span needs each semantic theme category only once. Keeping this
    // vocabulary bounded avoids copying an ever-growing stack for deep emphasis.
    if !tokens.contains(token) { tokens.append(token) }
  }
}

public struct MarkdownSyntaxRun: Equatable, Sendable {
  public let range: NSRange
  public let style: MarkdownSyntaxStyle
}

/// Sorted, disjoint UTF-16 runs. The parser builds this off the main actor. TextKit
/// can binary-search only the runs intersecting its current layout fragment.
public struct MarkdownSyntax: Sendable {
  public let id = UUID()
  public let runs: [MarkdownSyntaxRun]

  static func build(source: String, nodes: [MarkdownNode], metadata: MarkdownSourceMetadata? = nil)
    throws -> Self
  {
    let bytes = metadata?.bytes ?? Array(source.utf8)
    let lines = metadata?.lines ?? MarkdownSourceMetadata.lineRanges(bytes)

    func byteRange(_ range: MarkdownSourceRange) -> Range<Int>? {
      guard range.start.line > 0, range.start.line <= lines.count,
        range.end.line >= range.start.line, range.end.line <= lines.count,
        range.start.column > 0, range.end.column >= 0
      else { return nil }
      let first = lines[range.start.line - 1]
      let last = lines[range.end.line - 1]
      guard range.start.column - 1 <= first.count, range.end.column <= last.count else {
        return nil
      }
      let lower = first.lowerBound + range.start.column - 1
      let upper = last.lowerBound + range.end.column
      return upper > lower ? lower..<upper : nil
    }

    struct Interval {
      let range: Range<Int>
      let style: MarkdownSyntaxStyle
      let priority: Int
    }
    var intervals: [Interval] = []
    var styles: [MarkdownSyntaxStyle] = []
    let notePriorities = Dictionary(
      nodes.filter { $0.kind == .footnoteDefinition }.compactMap { node in
        node.range.map { ($0.start.line, node.id) }
      }, uniquingKeysWith: max)
    let quotedNotes = Set(
      (metadata?.definitions ?? []).filter { $0.kind == .note && $0.quoted }.map {
        $0.range.start.line
      })
    for node in nodes {
      if node.id.isMultiple(of: 256) { try Task.checkCancellation() }
      let parent = node.parentID.flatMap { $0 < styles.count ? styles[$0] : nil } ?? .init()
      var style = parent
      switch node.kind {
      case .heading:
        style.role = .heading
        style.bold = true
      case .highlight: style.highlighted = true
      case .strong: style.bold = true
      case .emphasis: style.italic = true
      case .strikethrough: style.strikethrough = true
      case .underline: style.underlined = true
      case .codeBlock, .inlineCode, .frontMatter, .math, .diagram: style.role = .code
      case .link, .image: style.role = .link
      case .blockquote, .quotation: style.role = .quote
      case .html: style.role = (node.literal?.hasPrefix("<!--") == true) ? .comment : .code
      case .thematicBreak: style.role = .marker
      case .footnoteReference: style.role = .link
      default: break
      }
      switch node.kind {
      case .heading: style.include(.heading(node.headingLevel ?? 1))
      case .strong: style.include(.strong)
      case .emphasis: style.include(.emphasis)
      case .inlineCode: style.include(.inlineCode)
      case .codeBlock, .frontMatter, .math, .diagram: style.include(.codeBlock)
      case .image: style.include(.image)
      case .link:
        if let sourceRange = node.range, let range = byteRange(sourceRange),
          bytes[range.lowerBound] != 91
        {
          style.include(
            node.destination?.hasPrefix("mailto:") == true ? .automaticEmail : .automaticURL)
        } else {
          style.include(.link)
        }
      case .blockquote, .quotation: style.include(.blockquote)
      case .html:
        if style.role == .comment {
          style.include(.comment)
        } else if node.parentID.map({ nodes[$0].kind }) == .paragraph {
          style.include(.inlineHTML)
        } else {
          style.include(.blockHTML)
        }
      case .thematicBreak: style.include(.horizontalRule)
      case .footnoteDefinition, .footnoteReference:
        if node.kind == .footnoteDefinition, let line = node.range?.start.line,
          quotedNotes.contains(line)
        {
          style.role = .quote
          style.include(.blockquote)
        }
        style.include(.note)
      default: break
      }
      styles.append(style)
      guard let sourceRange = node.range, let range = byteRange(sourceRange) else { continue }
      if style != parent {
        var presentationRange = range
        // Native inline-code coordinates identify the body. Theme presentation
        // also includes its paired delimiters, as in the original CODE rule.
        // Expand only around an AST-confirmed code span with matching tick runs.
        if node.kind == .inlineCode {
          var lower = range.lowerBound
          var upper = range.upperBound
          while lower > 0, bytes[lower - 1] == 96 { lower -= 1 }
          while upper < bytes.count, bytes[upper] == 96 { upper += 1 }
          if range.lowerBound - lower > 0, range.lowerBound - lower == upper - range.upperBound {
            presentationRange = lower..<upper
          }
        }
        intervals.append(Interval(range: presentationRange, style: style, priority: node.id))
      }
      if node.kind == .text {
        for entity in try MarkdownEntities.ranges(in: bytes, within: range) {
          var entityStyle = style
          entityStyle.include(.entity)
          intervals.append(Interval(range: entity, style: entityStyle, priority: node.id))
        }
      }
      // Marker detection is confined to AST-recognized headings/list items, never
      // a document-wide regular expression. The actual Markdown stays fully visible.
      if node.kind == .heading || node.kind == .listItem {
        var end = range.lowerBound
        if node.kind == .heading {
          while end < range.upperBound, bytes[end] == 35 { end += 1 }
        } else if [42, 43, 45].contains(bytes[end]) {
          end += 1
        } else {
          while end < range.upperBound, (48...57).contains(bytes[end]) { end += 1 }
          if end < range.upperBound, [41, 46].contains(bytes[end]) {
            end += 1
          } else {
            end = range.lowerBound
          }
        }
        if end > range.lowerBound {
          var marker = style
          marker.role = .marker
          if node.kind == .listItem {
            marker.include(
              [42, 43, 45].contains(bytes[range.lowerBound]) ? .listBullet : .listEnumerator)
          }
          intervals.append(
            Interval(range: range.lowerBound..<end, style: marker, priority: nodes.count + node.id))
        }
      }
    }
    for definition in metadata?.definitions ?? [] {
      guard let range = byteRange(definition.range) else { continue }
      var style = MarkdownSyntaxStyle()
      style.role = definition.kind == .reference ? .link : (definition.quoted ? .quote : .text)
      if definition.quoted { style.include(.blockquote) }
      if definition.inNote { style.include(.note) }
      if definition.kind == .reference { style.include(.referenceDefinition) }
      // Notes fill discarded definitions and marker prefixes. Surviving native
      // descendants keep their more specific code/emphasis/etc. presentation.
      let priority =
        definition.kind == .note
        ? notePriorities[definition.range.start.line] ?? nodes.count
        : nodes.count * 2 + intervals.count
      intervals.append(Interval(range: range, style: style, priority: priority))
    }
    if intervals.isEmpty { return Self(runs: []) }

    // Resolve every requested UTF-8 boundary in a SINGLE scalar pass. Repeated
    // prefix conversions on a long line would otherwise become quadratic.
    let boundaries = Set(intervals.flatMap { [$0.range.lowerBound, $0.range.upperBound] }).sorted()
    var offsets: [Int: Int] = [:]
    let scalars = source.unicodeScalars
    var scalarIndex = scalars.startIndex
    var byteOffset = 0
    var utf16Offset = 0
    for target in boundaries {
      while scalarIndex != scalars.endIndex, byteOffset < target {
        let scalar = scalars[scalarIndex]
        guard byteOffset + scalar.utf8.count <= target else { break }
        byteOffset += scalar.utf8.count
        utf16Offset += scalar.utf16.count
        scalarIndex = scalars.index(after: scalarIndex)
      }
      if byteOffset == target { offsets[target] = utf16Offset }
    }
    try Task.checkCancellation()
    intervals = intervals.compactMap { item in
      guard let lower = offsets[item.range.lowerBound], let upper = offsets[item.range.upperBound],
        upper > lower
      else { return nil }
      return Interval(range: lower..<upper, style: item.style, priority: item.priority)
    }
    struct Event {
      let offset: Int
      let index: Int
      let entering: Bool
    }
    let events = intervals.enumerated().flatMap { index, item in
      [
        Event(offset: item.range.lowerBound, index: index, entering: true),
        Event(offset: item.range.upperBound, index: index, entering: false),
      ]
    }.sorted { $0.offset < $1.offset }
    var active = Array(repeating: false, count: intervals.count)
    var heap: [Int] = []
    func higher(_ a: Int, _ b: Int) -> Bool { intervals[a].priority > intervals[b].priority }
    func insert(_ index: Int) {
      heap.append(index)
      var child = heap.count - 1
      while child > 0 {
        let parent = (child - 1) / 2
        guard higher(heap[child], heap[parent]) else { break }
        heap.swapAt(child, parent)
        child = parent
      }
    }
    func prune() {
      while let first = heap.first, !active[first] {
        let last = heap.removeLast()
        guard !heap.isEmpty else { continue }
        heap[0] = last
        var parent = 0
        while parent * 2 + 1 < heap.count {
          var child = parent * 2 + 1
          if child + 1 < heap.count, higher(heap[child + 1], heap[child]) { child += 1 }
          guard higher(heap[child], heap[parent]) else { break }
          heap.swapAt(parent, child)
          parent = child
        }
      }
    }
    var runs: [MarkdownSyntaxRun] = []
    var eventIndex = 0
    while eventIndex < events.count {
      if eventIndex.isMultiple(of: 256) { try Task.checkCancellation() }
      let position = events[eventIndex].offset
      while eventIndex < events.count, events[eventIndex].offset == position {
        let event = events[eventIndex]
        active[event.index] = event.entering
        if event.entering { insert(event.index) }
        eventIndex += 1
      }
      prune()
      guard eventIndex < events.count, let top = heap.first else { continue }
      let end = events[eventIndex].offset
      let style = intervals[top].style
      if let previous = runs.last, NSMaxRange(previous.range) == position, previous.style == style {
        runs[runs.count - 1] = MarkdownSyntaxRun(
          range: NSRange(location: previous.range.location, length: end - previous.range.location),
          style: style)
      } else {
        runs.append(
          MarkdownSyntaxRun(
            range: NSRange(location: position, length: end - position), style: style))
      }
    }
    return Self(runs: runs)
  }
}
