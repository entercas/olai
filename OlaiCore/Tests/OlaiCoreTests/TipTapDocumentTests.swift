import Foundation
import Testing
@testable import OlaiCore

struct TipTapDocumentTests {
    @Test func plainTextRoundTripsThroughDocument() throws {
        let original = "First line\n\nThird line"
        let data = TipTapDocument.document(fromPlainText: original)
        #expect(TipTapDocument.plainText(from: data) == original)
    }

    @Test func emptyTextProducesOneEmptyParagraph() throws {
        let data = TipTapDocument.document(fromPlainText: "")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        #expect(json?["type"] as? String == "doc")
        #expect(content?.count == 1)
        #expect(content?.first?["content"] == nil)
        #expect(TipTapDocument.plainText(from: data) == "")
    }

    @Test func plainTextConcatenatesNestedTextNodes() throws {
        let doc = """
        {"type":"doc","content":[
          {"type":"heading","attrs":{"level":1},"content":[{"type":"text","text":"Title"}]},
          {"type":"paragraph","content":[
            {"type":"text","text":"bold "},
            {"type":"text","marks":[{"type":"bold"}],"text":"word"}
          ]}
        ]}
        """
        #expect(TipTapDocument.plainText(from: Data(doc.utf8)) == "Title\nbold word")
    }

    @Test func nonDocumentDataReturnsNil() {
        #expect(TipTapDocument.plainText(from: Data("not json".utf8)) == nil)
        #expect(TipTapDocument.plainText(from: Data(#"{"type":"paragraph"}"#.utf8)) == nil)
    }
}

struct AttachmentReferenceTests {
    private func document(_ json: String) -> Data { Data(json.utf8) }

    @Test func findsImagesAtAnyDepth() throws {
        let data = document("""
        {"type":"doc","content":[
          {"type":"image","attrs":{"src":"attachment://AAAAAAA1-0000-0000-0000-000000000001"}},
          {"type":"bulletList","content":[{"type":"listItem","content":[
            {"type":"paragraph","content":[
              {"type":"image","attrs":{"src":"attachment://AAAAAAA1-0000-0000-0000-000000000002"}}
            ]}
          ]}]}
        ]}
        """)
        let found = try #require(TipTapDocument.attachmentIDs(in: data))
        #expect(found == Set([
            UUID(uuidString: "AAAAAAA1-0000-0000-0000-000000000001")!,
            UUID(uuidString: "AAAAAAA1-0000-0000-0000-000000000002")!,
        ]))
    }

    @Test func ignoresImagesThatAreNotOurAttachments() throws {
        let data = document("""
        {"type":"doc","content":[
          {"type":"image","attrs":{"src":"https://example.com/cat.png"}},
          {"type":"image","attrs":{"src":"attachment://not-a-uuid"}},
          {"type":"image","attrs":{}}
        ]}
        """)
        #expect(try #require(TipTapDocument.attachmentIDs(in: data)).isEmpty)
    }

    /// The caller deletes whatever this does not name, so "cannot tell" has to be
    /// distinguishable from "references nothing" -- otherwise a body that fails to
    /// parse costs the page every image it has.
    @Test func unreadableBodyAnswersNilRatherThanEmpty() {
        #expect(TipTapDocument.attachmentIDs(in: Data("not json".utf8)) == nil)
        #expect(TipTapDocument.attachmentIDs(in: Data(#"{"type":"fragment"}"#.utf8)) == nil)
        #expect(TipTapDocument.attachmentIDs(in: Data(#"{"type":"doc","content":[]}"#.utf8)) == [])
    }
}
