import XCTest
import SwiftUI
@testable import Foundry

final class NotesMarkdownTests: XCTestCase {
    private func roundTrip(_ md: String, file: StaticString = #filePath, line: UInt = #line) {
        let once = NotesMarkdown.markdown(from: NotesMarkdown.attributed(from: md))
        XCTAssertEqual(once, md, "first round trip", file: file, line: line)
        let twice = NotesMarkdown.markdown(from: NotesMarkdown.attributed(from: once))
        XCTAssertEqual(twice, once, "second round trip", file: file, line: line)
    }

    private func plain(_ md: String) -> String {
        String(NotesMarkdown.attributed(from: md).characters)
    }

    func testEmpty() {
        XCTAssertEqual(plain(""), "")
        XCTAssertEqual(NotesMarkdown.markdown(from: AttributedString()), "")
        roundTrip("")
    }

    func testBold() {
        roundTrip("Call **Valu** today")
        let a = NotesMarkdown.attributed(from: "Call **Valu** today")
        XCTAssertEqual(String(a.characters), "Call Valu today")
        let bold = a.runs.first { String(a[$0.range].characters) == "Valu" }
        XCTAssertTrue(NotesMarkdown.style(of: bold?.font).bold)
    }

    func testItalic() {
        roundTrip("A *quiet* word")
        let a = NotesMarkdown.attributed(from: "A *quiet* word")
        let it = a.runs.first { String(a[$0.range].characters) == "quiet" }
        XCTAssertTrue(NotesMarkdown.style(of: it?.font).italic)
    }

    func testBoldItalicAndCode() {
        roundTrip("Both ***loud*** and `code` here")
    }

    func testLink() {
        roundTrip("See [the brief](https://gitwork.co.uk/brief) first")
        let a = NotesMarkdown.attributed(from: "See [the brief](https://gitwork.co.uk/brief) first")
        let link = a.runs.first { $0.link != nil }
        XCTAssertEqual(link?.link?.absoluteString, "https://gitwork.co.uk/brief")
        XCTAssertEqual(link.map { String(a[$0.range].characters) }, "the brief")
    }

    func testHeadings() {
        roundTrip("# Plan\n\n## Next\n\n### Later\n\nBody text")
        XCTAssertEqual(plain("# Plan\n\nBody"), "Plan\n\nBody")
        let a = NotesMarkdown.attributed(from: "## Next")
        XCTAssertEqual(NotesMarkdown.style(of: a.runs.first?.font).heading, 2)
    }

    func testBulletList() {
        roundTrip("- one\n- two\n- three")
        XCTAssertEqual(plain("- one\n- two"), "\u{2022} one\n\u{2022} two")
    }

    func testOrderedList() {
        roundTrip("1. first\n2. second")
    }

    func testChecklist() {
        roundTrip("- [ ] send the quote\n- [x] book the call")
        XCTAssertEqual(plain("- [ ] a\n- [x] b"), "\u{2610} a\n\u{2611} b")
    }

    func testMixedDocument() {
        roundTrip("# Valu\n\nSpoke to **Sam** about *timings*.\nSecond line of the same paragraph.\n\n- [ ] send [quote](https://example.com)\n- [x] agree scope\n- plain bullet\n\nClosing words.")
    }

    func testPlainTextPunctuationIsEscaped() {
        roundTrip("Price is 5 \\* 3 and a\\_b")
        XCTAssertEqual(plain("Price is 5 \\* 3"), "Price is 5 * 3")
    }

    func testEditorTextSerialises() {
        // What a person types in the editor: plain lines and prefixed list lines.
        var a = AttributedString("Title\n\n\u{2022} a\n\u{2610} b\nnext")
        if let r = a.range(of: "Title") { a[r].font = NotesMarkdown.Style(heading: 1).font }
        XCTAssertEqual(NotesMarkdown.markdown(from: a), "# Title\n\n- a\n- [ ] b\n\nnext")
    }
}
