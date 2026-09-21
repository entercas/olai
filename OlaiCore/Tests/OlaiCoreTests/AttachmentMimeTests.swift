import Testing
@testable import OlaiCore

struct AttachmentMimeTests {
    @Test func recognisedImageTypesSurvive() {
        for mime in ["image/png", "image/jpeg", "image/gif", "image/heic", "image/webp", "application/pdf"] {
            #expect(Attachment.safeMimeType(mime) == mime)
        }
    }

    @Test func spellingAndParametersAreNormalised() {
        #expect(Attachment.safeMimeType("IMAGE/PNG") == "image/png")
        #expect(Attachment.safeMimeType("  image/png  ") == "image/png")
        #expect(Attachment.safeMimeType("image/jpg") == "image/jpeg")
        #expect(Attachment.safeMimeType("image/png; charset=utf-8") == "image/png")
    }

    /// The point of the whitelist: attachments are served from olai://editor, the same
    /// origin as the editor, so nothing may be served as a type the web view executes.
    @Test func typesTheWebViewWouldExecuteAreRefused() {
        for mime in [
            "text/html",
            "image/svg+xml",
            "application/xhtml+xml",
            "text/javascript",
            "application/javascript",
            "image/png, text/html",
            "text/html; charset=utf-8",
        ] {
            #expect(Attachment.safeMimeType(mime) == Attachment.fallbackMimeType)
        }
    }

    @Test func emptyAndJunkFallBack() {
        #expect(Attachment.safeMimeType("") == Attachment.fallbackMimeType)
        #expect(Attachment.safeMimeType(";") == Attachment.fallbackMimeType)
        #expect(Attachment.safeMimeType("nonsense") == Attachment.fallbackMimeType)
    }
}
