import Foundation
import Testing
@testable import OlaiCore

struct MarkdownConverterTests {
    private func markdown(_ json: String, attachments: [UUID: String] = [:]) -> String {
        MarkdownConverter.markdown(from: Data(json.utf8), attachmentExtensions: attachments)
    }

    @Test func headingsBecomeHashes() {
        let out = markdown("""
        {"type":"doc","content":[
          {"type":"heading","attrs":{"level":1},"content":[{"type":"text","text":"Week"}]},
          {"type":"heading","attrs":{"level":3},"content":[{"type":"text","text":"Wins"}]}
        ]}
        """)
        #expect(out == "# Week\n\n### Wins")
    }

    @Test func taskItemsBecomeCheckboxes() {
        let out = markdown("""
        {"type":"doc","content":[{"type":"taskList","content":[
          {"type":"taskItem","attrs":{"checked":true},
           "content":[{"type":"paragraph","content":[{"type":"text","text":"ship it"}]}]},
          {"type":"taskItem","attrs":{"checked":false},
           "content":[{"type":"paragraph","content":[{"type":"text","text":"write it up"}]}]}
        ]}]}
        """)
        #expect(out == "- [x] ship it\n- [ ] write it up")
    }

    @Test func marksWrapTheirText() {
        let out = markdown("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","marks":[{"type":"bold"}],"text":"bold"},
          {"type":"text","text":" "},
          {"type":"text","marks":[{"type":"italic"}],"text":"italic"},
          {"type":"text","text":" "},
          {"type":"text","marks":[{"type":"highlight"}],"text":"note"},
          {"type":"text","text":" "},
          {"type":"text","marks":[{"type":"underline"}],"text":"under"},
          {"type":"text","text":" "},
          {"type":"text","marks":[{"type":"code"}],"text":"code"}
        ]}]}
        """)
        #expect(out == "**bold** *italic* ==note== <u>under</u> `code`")
    }

    @Test func linksCarryTheirHref() {
        let out = markdown("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","marks":[{"type":"link","attrs":{"href":"https://example.com"}}],"text":"site"}
        ]}]}
        """)
        #expect(out == "[site](https://example.com)")
    }

    @Test func imagesPointAtTheAttachmentFileBesideThePage() {
        let id = UUID(uuidString: "5D470D12-0E29-4E7B-8B96-66B3FA8E4ED4")!
        let out = markdown("""
        {"type":"doc","content":[
          {"type":"image","attrs":{"src":"attachment://5D470D12-0E29-4E7B-8B96-66B3FA8E4ED4","alt":"chart"}}
        ]}
        """, attachments: [id: "jpg"])
        #expect(out == "![chart](attachments/5D470D12-0E29-4E7B-8B96-66B3FA8E4ED4.jpg)")
    }

    @Test func anImageWithNoKnownExtensionFallsBackToPNG() {
        let out = markdown("""
        {"type":"doc","content":[
          {"type":"image","attrs":{"src":"attachment://5D470D12-0E29-4E7B-8B96-66B3FA8E4ED4"}}
        ]}
        """)
        #expect(out.hasSuffix(".png)"))
    }

    @Test func numberedListsCount() {
        let out = markdown("""
        {"type":"doc","content":[{"type":"orderedList","content":[
          {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"one"}]}]},
          {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"two"}]}]}
        ]}]}
        """)
        #expect(out == "1. one\n2. two")
    }

    @Test func nestedListsIndent() {
        let out = markdown("""
        {"type":"doc","content":[{"type":"bulletList","content":[
          {"type":"listItem","content":[
            {"type":"paragraph","content":[{"type":"text","text":"outer"}]},
            {"type":"bulletList","content":[
              {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"inner"}]}]}
            ]}
          ]}
        ]}]}
        """)
        #expect(out == "- outer\n  - inner")
    }

    @Test func aBlockNestedInAListItemIsIndentedWithIt() {
        let out = markdown("""
        {"type":"doc","content":[{"type":"taskList","content":[
          {"type":"taskItem","attrs":{"checked":false},"content":[
            {"type":"paragraph","content":[{"type":"text","text":"with a picture"}]},
            {"type":"image","attrs":{"src":"attachment://5D470D12-0E29-4E7B-8B96-66B3FA8E4ED4"}}
          ]}
        ]}]}
        """)
        #expect(out == "- [ ] with a picture\n  ![](attachments/5D470D12-0E29-4E7B-8B96-66B3FA8E4ED4.png)")
    }

    @Test func blockquotesAndCodeBlocksSurvive() {
        let out = markdown("""
        {"type":"doc","content":[
          {"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"quoted"}]}]},
          {"type":"codeBlock","attrs":{"language":"swift"},"content":[{"type":"text","text":"let x = 1"}]},
          {"type":"horizontalRule"}
        ]}
        """)
        #expect(out == "> quoted\n\n```swift\nlet x = 1\n```\n\n---")
    }

    @Test func anUnknownBlockKeepsItsText() {
        let out = markdown("""
        {"type":"doc","content":[
          {"type":"mysteryBlock","content":[{"type":"text","text":"still here"}]}
        ]}
        """)
        #expect(out == "still here")
    }

    @Test func somethingThatIsNotADocumentConvertsToNothing() {
        #expect(markdown("not json") == "")
        #expect(markdown(#"{"type":"paragraph"}"#) == "")
    }
}
