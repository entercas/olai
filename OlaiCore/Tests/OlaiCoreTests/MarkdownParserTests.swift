import Foundation
import Testing
@testable import OlaiCore

struct MarkdownParserTests {
    private func blocks(_ markdown: String) -> [[String: Any]] {
        MarkdownParser.documentObject(from: markdown)["content"] as? [[String: Any]] ?? []
    }

    private func type(_ node: [String: Any]) -> String { node["type"] as? String ?? "" }

    private func text(_ node: [String: Any]) -> String {
        if let value = node["text"] as? String { return value }
        let children = node["content"] as? [[String: Any]] ?? []
        return children.map(text).joined()
    }

    private func marks(_ node: [String: Any]) -> [String] {
        (node["marks"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String }
    }

    // MARK: Blocks

    @Test func headingsCarryTheirLevel() {
        let parsed = blocks("# One\n\n## Two\n\n### Three")
        #expect(parsed.map(type) == ["heading", "heading", "heading"])
        #expect(parsed.map { ($0["attrs"] as? [String: Any])?["level"] as? Int } == [1, 2, 3])
        #expect(parsed.map(text) == ["One", "Two", "Three"])
    }

    /// The editor only offers three levels, so a deeper heading has to land somewhere
    /// the schema accepts rather than being dropped on the way in.
    @Test func headingsBelowTheEditorsRangeAreClamped() {
        let parsed = blocks("##### Deep")
        #expect((parsed[0]["attrs"] as? [String: Any])?["level"] as? Int == 3)
        #expect(text(parsed[0]) == "Deep")
    }

    @Test func aHashWithNoSpaceIsNotAHeading() {
        #expect(type(blocks("#hashtag")[0]) == "paragraph")
    }

    @Test func paragraphsRunUntilABlankLine() {
        let parsed = blocks("one\ntwo\n\nthree")
        #expect(parsed.map(type) == ["paragraph", "paragraph"])
        #expect(text(parsed[0]) == "one two")
        #expect(text(parsed[1]) == "three")
    }

    @Test func twoTrailingSpacesBecomeAHardBreak() {
        let parsed = blocks("one  \ntwo")
        let content = parsed[0]["content"] as? [[String: Any]] ?? []
        #expect(content.map(type) == ["text", "hardBreak", "text"])
    }

    @Test func rulesAndFencedCodeSurvive() {
        let parsed = blocks("---\n\n```swift\nlet x = 1\n```")
        #expect(parsed.map(type) == ["horizontalRule", "codeBlock"])
        #expect((parsed[1]["attrs"] as? [String: Any])?["language"] as? String == "swift")
        #expect(text(parsed[1]) == "let x = 1")
    }

    /// Markdown inside a fence is literal, not markup.
    @Test func codeBlocksKeepTheirContentUnparsed() {
        let parsed = blocks("```\n# not a heading\n- not a list\n```")
        #expect(type(parsed[0]) == "codeBlock")
        #expect(text(parsed[0]) == "# not a heading\n- not a list")
    }

    @Test func blockquotesHoldBlocks() {
        let parsed = blocks("> quoted\n> ## inside")
        #expect(type(parsed[0]) == "blockquote")
        let inner = parsed[0]["content"] as? [[String: Any]] ?? []
        #expect(inner.map(type) == ["paragraph", "heading"])
    }

    // MARK: Lists

    @Test func bulletsOrderedAndTasksBecomeTheirOwnLists() {
        let parsed = blocks("- a\n- b")
        #expect(type(parsed[0]) == "bulletList")
        #expect((parsed[0]["content"] as? [[String: Any]])?.count == 2)

        let ordered = blocks("1. a\n2. b")
        #expect(type(ordered[0]) == "orderedList")

        let tasks = blocks("- [ ] open\n- [x] done")
        #expect(type(tasks[0]) == "taskList")
        let items = tasks[0]["content"] as? [[String: Any]] ?? []
        #expect(items.map { ($0["attrs"] as? [String: Any])?["checked"] as? Bool } == [false, true])
        #expect(items.map(text) == ["open", "done"])
    }

    @Test func indentationNests() {
        let parsed = blocks("- outer\n  - inner\n    - deepest")
        let outerItems = parsed[0]["content"] as? [[String: Any]] ?? []
        #expect(outerItems.count == 1)

        let outerContent = outerItems[0]["content"] as? [[String: Any]] ?? []
        #expect(outerContent.map(type) == ["paragraph", "bulletList"])
        #expect(text(outerContent[0]) == "outer")

        let innerItems = outerContent[1]["content"] as? [[String: Any]] ?? []
        let innerContent = innerItems[0]["content"] as? [[String: Any]] ?? []
        #expect(text(innerContent[0]) == "inner")
        #expect(type(innerContent[1]) == "bulletList")
    }

    @Test func aChangeOfListKindStartsANewList() {
        let parsed = blocks("- bullet\n1. numbered")
        #expect(parsed.map(type) == ["bulletList", "orderedList"])
    }

    // MARK: Inline

    @Test func everyMarkTheConverterWritesIsReadBack() {
        let parsed = blocks("**b** *i* ~~s~~ `c` ==h== <u>u</u>")
        let content = parsed[0]["content"] as? [[String: Any]] ?? []
        let byText = Dictionary(uniqueKeysWithValues: content.compactMap { node -> (String, [String])? in
            guard let value = node["text"] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return (value, marks(node))
        })
        #expect(byText["b"] == ["bold"])
        #expect(byText["i"] == ["italic"])
        #expect(byText["s"] == ["strike"])
        #expect(byText["c"] == ["code"])
        #expect(byText["h"] == ["highlight"])
        #expect(byText["u"] == ["underline"])
    }

    @Test func inlineCodeIsLiteral() {
        let parsed = blocks("`**not bold**`")
        let content = parsed[0]["content"] as? [[String: Any]] ?? []
        #expect(content.count == 1)
        #expect(content[0]["text"] as? String == "**not bold**")
        #expect(marks(content[0]) == ["code"])
    }

    @Test func linksCarryTheirHref() {
        let parsed = blocks("see [the docs](https://example.com/a(b))")
        let content = parsed[0]["content"] as? [[String: Any]] ?? []
        let link = content.first { marks($0).contains("link") }
        #expect(link?["text"] as? String == "the docs")
        let href = ((link?["marks"] as? [[String: Any]])?.first { $0["type"] as? String == "link" }?["attrs"] as? [String: Any])?["href"] as? String
        #expect(href == "https://example.com/a(b)")
    }

    @Test func anImageOnItsOwnLineIsABlock() {
        let parsed = blocks("![a cat](attachments/cat.png)")
        #expect(type(parsed[0]) == "image")
        let attrs = parsed[0]["attrs"] as? [String: Any] ?? [:]
        #expect(attrs["src"] as? String == "attachments/cat.png")
        #expect(attrs["alt"] as? String == "a cat")
    }

    @Test func imagePathsCanBeRewrittenOnTheWayIn() {
        let object = MarkdownParser.documentObject(from: "![](attachments/x.png)") { path in
            path == "attachments/x.png" ? "attachment://ABCDEF01-0000-0000-0000-000000000001" : nil
        }
        let content = object["content"] as? [[String: Any]] ?? []
        let attrs = content[0]["attrs"] as? [String: Any] ?? [:]
        #expect(attrs["src"] as? String == "attachment://ABCDEF01-0000-0000-0000-000000000001")
    }

    @Test func aBackslashEscapesTheCharacterAfterIt() {
        let parsed = blocks(#"\*not italic\*"#)
        #expect(text(parsed[0]) == "*not italic*")
    }

    // MARK: Round trip

    /// The parser is the converter's inverse, so a document that goes out as Markdown
    /// and comes back has to be the same document. This is the test that actually keeps
    /// the two in step as either changes.
    @Test func convertingAndParsingBackGivesTheSameDocument() throws {
        let markdown = """
        # Weekly

        Some **bold** and *italic* and a [link](https://example.com).

        ## To-do

        - [ ] open item
        - [x] done item

        ## Notes

        - outer
          - inner

        1. first
        2. second

        > quoted line

        ```swift
        let x = 1
        ```

        ---
        """

        let document = MarkdownParser.document(from: markdown)
        let roundTripped = MarkdownConverter.markdown(from: document)

        #expect(roundTripped == markdown.trimmingCharacters(in: .newlines))
    }

    @Test func emptyMarkdownIsStillAValidDocument() throws {
        let object = MarkdownParser.documentObject(from: "")
        #expect(object["type"] as? String == "doc")
        let content = try #require(object["content"] as? [[String: Any]])
        #expect(content.map(type) == ["paragraph"])
    }
}
