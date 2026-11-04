import Foundation
import SwiftUI

/// The bridge between a to-do's notes as stored (Markdown, `Commitment.notes`) and as edited
/// (an `AttributedString` the SwiftUI rich `TextEditor` can show).
///
/// The editor only draws visible attributes (fonts, links), not Markdown's block structure, so
/// the editor form is deliberately simple:
/// - inline styles are fonts: bold, italic, bold italic, monospaced code (see `Style`);
/// - links keep the `link` attribute;
/// - headings are a whole line in a heading font (sizes 22 / 19 / 17);
/// - list items are ordinary text with a visible prefix: "• " for a bullet, "☐ " / "☑ " for a
///   checklist item, "1. " for a numbered item.
///
/// Supported Markdown subset (stable through a round trip): `**bold**`, `*italic*`,
/// `***both***`, `` `code` ``, `[text](url)`, `#`/`##`/`###` headings, `- ` bullets,
/// `- [ ] ` / `- [x] ` checklist items, `1. ` numbered items, and paragraphs. Anything else
/// Markdown can express is read as its text and written back as that text.
enum NotesMarkdown {
    static let bodySize: CGFloat = 15
    static let maxLength = 4000

    static let bullet = "\u{2022} "
    static let unchecked = "\u{2610} "
    static let checked = "\u{2611} "

    // MARK: Styles

    struct Style: Equatable, Sendable {
        var bold = false
        var italic = false
        var code = false
        /// 0 = not a heading, 1–3 = heading level.
        var heading = 0

        var font: Font? {
            switch heading {
            case 1: return .system(size: 22, weight: .bold)
            case 2: return .system(size: 19, weight: .semibold)
            case 3: return .system(size: 17, weight: .semibold)
            default: break
            }
            if code { return .system(size: bodySize - 1, design: .monospaced) }
            switch (bold, italic) {
            case (true, true): return .system(size: bodySize, weight: .bold).italic()
            case (true, false): return .system(size: bodySize, weight: .bold)
            case (false, true): return .system(size: bodySize).italic()
            case (false, false): return nil
            }
        }
    }

    /// Reads a font back into a style. Works for fonts this file made and for fonts the text
    /// system wrote itself (it resolves the font rather than comparing values).
    static func style(of font: Font?) -> Style {
        guard let font else { return Style() }
        let r = font.resolve(in: EnvironmentValues().fontResolutionContext)
        var s = Style()
        if r.pointSize >= 21 { s.heading = 1 } else if r.pointSize >= 18.5 { s.heading = 2 } else if r.pointSize >= 16.5 { s.heading = 3 }
        s.code = r.isMonospaced
        s.bold = r.isBold || [.semibold, .bold, .heavy, .black].contains(r.weight)
        s.italic = r.isItalic
        return s
    }

    // MARK: Markdown -> editor

    static func attributed(from markdown: String) -> AttributedString {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return AttributedString() }
        let parsed: AttributedString
        do {
            parsed = try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        } catch {
            return AttributedString(markdown)
        }

        struct Block {
            var key: Int
            var listKey: Int?
            var kind: Kind
            var text = AttributedString()
            enum Kind { case paragraph, heading(Int), bullet, ordered(Int) }
        }

        var blocks: [Block] = []
        for run in parsed.runs {
            let comps = run.presentationIntent?.components ?? []
            let key = comps.first?.identity ?? -1
            var kind = Block.Kind.paragraph
            var listKey: Int?
            var ordinal = 1
            var ordered = false
            for c in comps {
                switch c.kind {
                case .header(let level): kind = .heading(min(max(level, 1), 3))
                case .listItem(let n): ordinal = n
                case .orderedList: ordered = true; if listKey == nil { listKey = c.identity }
                case .unorderedList: if listKey == nil { listKey = c.identity }
                default: break
                }
            }
            if listKey != nil { kind = ordered ? .ordered(ordinal) : .bullet }

            var piece = AttributedString(parsed[run.range].characters)
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.softBreak) || inline.contains(.lineBreak) {
                piece = AttributedString("\n")
            } else {
                var s = Style()
                s.bold = inline.contains(.stronglyEmphasized)
                s.italic = inline.contains(.emphasized)
                s.code = inline.contains(.code)
                if case .heading(let level) = kind { s = Style(heading: level) }
                piece.font = s.font
                piece.link = run.link
            }

            if blocks.last?.key == key {
                blocks[blocks.count - 1].text.append(piece)
            } else {
                blocks.append(Block(key: key, listKey: listKey, kind: kind, text: piece))
            }
        }

        var out = AttributedString()
        var previousListKey: Int?? = nil
        for block in blocks {
            if let prev = previousListKey {
                let sameList = prev != nil && prev == block.listKey
                out.append(AttributedString(sameList ? "\n" : "\n\n"))
            }
            previousListKey = .some(block.listKey)
            var text = block.text
            switch block.kind {
            case .bullet:
                let chars = String(text.characters)
                if chars.hasPrefix("[ ] ") {
                    text.removeSubrange(text.startIndex..<text.index(text.startIndex, offsetByCharacters: 4))
                    text.insert(AttributedString(unchecked), at: text.startIndex)
                } else if chars.hasPrefix("[x] ") || chars.hasPrefix("[X] ") {
                    text.removeSubrange(text.startIndex..<text.index(text.startIndex, offsetByCharacters: 4))
                    text.insert(AttributedString(checked), at: text.startIndex)
                } else {
                    text.insert(AttributedString(bullet), at: text.startIndex)
                }
            case .ordered(let n):
                text.insert(AttributedString("\(n). "), at: text.startIndex)
            case .paragraph, .heading:
                break
            }
            out.append(text)
        }
        return out
    }

    // MARK: Editor -> Markdown

    private enum LineKind: Equatable {
        case blank, plain, heading(Int), bullet, task(Bool), ordered(Int)

        var family: Int {
            switch self {
            case .bullet, .task: return 1
            case .ordered: return 2
            default: return 0
            }
        }
    }

    static func markdown(from text: AttributedString) -> String {
        var blocks: [(LineKind, String)] = []
        for line in lines(of: text) {
            let (kind, content) = classify(line)
            switch kind {
            case .blank:
                blocks.append((.blank, ""))
            case .plain:
                let body = escapeLineStart(inline(content))
                if case .plain? = blocks.last?.0 {
                    blocks[blocks.count - 1].1 += "\n" + body
                } else {
                    blocks.append((.plain, body))
                }
            case .heading(let level):
                blocks.append((kind, String(repeating: "#", count: level) + " " + escape(String(content.characters))))
            case .bullet:
                blocks.append((kind, "- " + inline(content)))
            case .task(let done):
                blocks.append((kind, (done ? "- [x] " : "- [ ] ") + inline(content)))
            case .ordered(let n):
                blocks.append((kind, "\(n). " + inline(content)))
            }
        }

        var out = ""
        var previous: LineKind?
        for (kind, body) in blocks where kind != .blank {
            if let previous {
                out += (previous.family != 0 && previous.family == kind.family) ? "\n" : "\n\n"
            }
            out += body
            previous = kind
        }
        // A blank line between list items ends the list: keep that as a paragraph break.
        return out
    }

    /// Splits the editor text into lines, keeping attributes.
    private static func lines(of text: AttributedString) -> [AttributedSubstring] {
        var result: [AttributedSubstring] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            if text.characters[i] == "\n" {
                result.append(text[start..<i])
                start = text.characters.index(after: i)
            }
            i = text.characters.index(after: i)
        }
        result.append(text[start..<text.endIndex])
        return result
    }

    private static func dropping(_ n: Int, from line: AttributedSubstring) -> AttributedSubstring {
        let cut = line.characters.index(line.startIndex, offsetBy: n)
        return line[cut..<line.endIndex]
    }

    private static func classify(_ line: AttributedSubstring) -> (LineKind, AttributedSubstring) {
        let s = String(line.characters)
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return (.blank, line) }
        for (prefix, kind) in [(unchecked, LineKind.task(false)), (checked, .task(true)),
                               ("- [ ] ", .task(false)), ("- [x] ", .task(true)), ("- [X] ", .task(true)),
                               (bullet, .bullet), ("- ", .bullet), ("* ", .bullet)] where s.hasPrefix(prefix) {
            return (kind, dropping(prefix.count, from: line))
        }
        if let digits = orderedNumber(s), let n = Int(digits) {
            return (.ordered(n), dropping(digits.count + 2, from: line))
        }
        let hashes = s.prefix(while: { $0 == "#" }).count
        if (1...3).contains(hashes), s.dropFirst(hashes).hasPrefix(" ") {
            return (.heading(hashes), dropping(hashes + 1, from: line))
        }
        if let first = line.runs.first(where: { !String(line[$0.range].characters).trimmingCharacters(in: .whitespaces).isEmpty }) {
            let level = style(of: first.font).heading
            if level > 0 { return (.heading(level), line) }
        }
        return (.plain, line)
    }

    private struct Format: Equatable {
        var bold = false, italic = false, code = false
        var link: URL?
    }

    private static func inline(_ text: AttributedSubstring) -> String {
        var segments: [(String, Format)] = []
        for run in text.runs {
            let s = style(of: run.font)
            let f = Format(bold: s.bold && s.heading == 0, italic: s.italic, code: s.code, link: run.link)
            let chunk = String(text[run.range].characters)
            if let last = segments.last, last.1 == f {
                segments[segments.count - 1].0 += chunk
            } else {
                segments.append((chunk, f))
            }
        }

        var out = ""
        for (chunk, f) in segments {
            var inner: String
            if f.code {
                let tick = chunk.contains("`") ? "``" : "`"
                inner = tick + chunk + tick
            } else {
                // Markers must hug the words: move surrounding spaces outside them.
                let core = chunk.trimmingCharacters(in: .whitespaces)
                if core.isEmpty || (!f.bold && !f.italic) {
                    inner = escape(chunk)
                } else {
                    let lead = String(chunk.prefix(while: { $0 == " " || $0 == "\t" }))
                    let trail = String(chunk.reversed().prefix(while: { $0 == " " || $0 == "\t" }))
                    let marker = f.bold && f.italic ? "***" : (f.bold ? "**" : "*")
                    inner = lead + marker + escape(core) + marker + trail
                }
            }
            if let url = f.link {
                inner = "[" + inner + "](" + url.absoluteString + ")"
            }
            out += inner
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\*_`[]".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// A plain paragraph must not start with something Markdown would read as block syntax.
    private static func escapeLineStart(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let l = String(line)
            if l.hasPrefix(">") || l.hasPrefix("+ ") || l.hasPrefix("#") { return "\\" + l }
            if let digits = orderedNumber(l) {
                return digits + "\\" + l.dropFirst(digits.count)
            }
            return l
        }.joined(separator: "\n")
    }

    /// The number of a "12. " line start, if the line has one.
    private static func orderedNumber(_ line: String) -> String? {
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        guard (1...9).contains(digits.count), line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return String(digits)
    }

    /// Length of the stored form, which is what the 4000-character limit applies to.
    static func storedLength(of text: AttributedString) -> Int {
        markdown(from: text).count
    }
}
