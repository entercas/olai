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
