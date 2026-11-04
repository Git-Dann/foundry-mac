import SwiftUI

/// A calm rich-text editor for a to-do's notes. Edits an `AttributedString` with the macOS 26
/// rich `TextEditor`; stores Markdown through `NotesMarkdown`.
///
/// Commits (writes `markdown` and calls `onCommit`) when the editor loses focus and on ⌘S.
struct NotesEditor: View {
    @Binding var markdown: String
    var onCommit: () -> Void

    @State private var text = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var loadedMarkdown: String?
    @FocusState private var focused: Bool

    private var storedLength: Int { NotesMarkdown.storedLength(of: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar

            TextEditor(text: $text, selection: $selection)
                .font(.system(size: NotesMarkdown.bodySize))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                .focused($focused)
                .frame(minHeight: 160)
                .accessibilityLabel("Notes")

            HStack {
                Spacer()
                counter
            }
        }
        .onAppear { load(markdown) }
        .onChange(of: markdown) { _, new in
            // Pick up changes from outside (a refresh, another device) unless someone is typing.
            if !focused, new != loadedMarkdown { load(new) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .background {
            Button("Save notes", action: commit)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!focused)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button { toggleInline(\.bold) } label: { Label("Bold", systemImage: "bold") }
                    .help("Bold")
                Button { toggleInline(\.italic) } label: { Label("Italic", systemImage: "italic") }
                    .help("Italic")
            }
            .controlGroupStyle(.navigation)

            Menu {
                Button("Body") { setHeading(0) }
                Button("Heading 1") { setHeading(1) }
                Button("Heading 2") { setHeading(2) }
                Button("Heading 3") { setHeading(3) }
            } label: {
                Label("Text style", systemImage: "textformat.size")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Text style")

            ControlGroup {
                Button { toggleLinePrefix(NotesMarkdown.bullet) } label: { Label("Bulleted list", systemImage: "list.bullet") }
                    .help("Bulleted list")
                Button { toggleLinePrefix(NotesMarkdown.unchecked) } label: { Label("Checklist", systemImage: "checklist") }
                    .help("Checklist")
                Button { toggleChecked() } label: { Label("Tick off", systemImage: "checkmark.square") }
                    .help("Tick or untick checklist items")
            }
            .controlGroupStyle(.navigation)

            Spacer()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
    }

    private var counter: some View {
        let n = storedLength
        let limit = NotesMarkdown.maxLength
        let colour: Color = n > limit ? .red : (n >= limit * 9 / 10 ? .orange : .secondary)
        return Text("\(n) / \(limit)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(colour)
            .accessibilityLabel(n > limit ? "\(n - limit) characters over the limit" : "\(limit - n) characters left")
    }

    // MARK: Loading and committing

    private func load(_ md: String) {
        text = NotesMarkdown.attributed(from: md)
        selection = AttributedTextSelection()
        loadedMarkdown = md
    }

    private func commit() {
        let md = NotesMarkdown.markdown(from: text)
        guard md.count <= NotesMarkdown.maxLength else { return }
        guard md != loadedMarkdown else { return }
        loadedMarkdown = md
        markdown = md
        onCommit()
    }

    // MARK: Formatting

    private func toggleInline(_ flag: WritableKeyPath<NotesMarkdown.Style, Bool>) {
        let fonts = selection.attributes(in: text)[\.font]
        let allOn = fonts.allSatisfy { NotesMarkdown.style(of: $0)[keyPath: flag] }
        text.transformAttributes(in: &selection) { container in
            var style = NotesMarkdown.style(of: container.font)
            guard style.heading == 0 else { return }
            style[keyPath: flag] = !allOn
            container.font = style.font
        }
    }

    /// Ranges of the whole lines the selection touches (or the line holding the caret).
    private func selectedLineRanges() -> [Range<AttributedString.Index>] {
        let chars = text.characters
        var touched: [Range<AttributedString.Index>]
        switch selection.indices(in: text) {
        case .insertionPoint(let i): touched = [i..<i]
        case .ranges(let set): touched = set.ranges.map { $0 }
        }
        var lines: [Range<AttributedString.Index>] = []
        for r in touched {
            var start = r.lowerBound
            while start > chars.startIndex, chars[chars.index(before: start)] != "\n" { start = chars.index(before: start) }
            var cursor = start
            repeat {
                var end = cursor
                while end < chars.endIndex, chars[end] != "\n" { end = chars.index(after: end) }
                if !lines.contains(where: { $0.lowerBound == cursor }) { lines.append(cursor..<end) }
                guard end < chars.endIndex else { break }
                cursor = chars.index(after: end)
            } while cursor < r.upperBound
        }
        return lines.sorted { $0.lowerBound < $1.lowerBound }
    }

    private func setHeading(_ level: Int) {
        let lines = selectedLineRanges()
        text.transform(updating: &selection) { t in
            for line in lines {
                t[line].font = NotesMarkdown.Style(heading: level).font
            }
        }
    }

    private static let linePrefixes = [NotesMarkdown.bullet, NotesMarkdown.unchecked, NotesMarkdown.checked]

    /// Adds `prefix` to every selected line, or removes it when every line already has it.
    private func toggleLinePrefix(_ prefix: String) {
        let lines = selectedLineRanges()
        let all = lines.allSatisfy { line in
            let s = String(text[line].characters)
            return prefix == NotesMarkdown.unchecked
                ? (s.hasPrefix(NotesMarkdown.unchecked) || s.hasPrefix(NotesMarkdown.checked))
                : s.hasPrefix(prefix)
        }
        text.transform(updating: &selection) { t in
            // Work from the end so earlier ranges stay valid.
            for line in lines.reversed() {
                let s = String(t[line].characters)
                if let existing = Self.linePrefixes.first(where: { s.hasPrefix($0) }) {
                    let end = t.characters.index(line.lowerBound, offsetBy: existing.count)
                    t.removeSubrange(line.lowerBound..<end)
                }
                if !all {
                    t.insert(AttributedString(prefix), at: line.lowerBound)
                }
            }
        }
    }

    private func toggleChecked() {
        let lines = selectedLineRanges()
        text.transform(updating: &selection) { t in
            for line in lines.reversed() {
                let s = String(t[line].characters)
                let replacement: String
                if s.hasPrefix(NotesMarkdown.unchecked) { replacement = NotesMarkdown.checked }
                else if s.hasPrefix(NotesMarkdown.checked) { replacement = NotesMarkdown.unchecked }
                else { continue }
                let end = t.characters.index(line.lowerBound, offsetBy: replacement.count)
                t.replaceSubrange(line.lowerBound..<end, with: AttributedString(replacement))
            }
        }
    }
}
