import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Reads an image off the system pasteboard.
///
/// A screenshot is on the clipboard as raw image data with no file behind it, and a web
/// view's `clipboardData.files` is empty for that — the page cannot get at the bytes at
/// all, so WebKit inserts a `webkit-fake-url:` image that resolves to nothing. Swift can
/// read the pasteboard directly, so the editor asks for it instead.
enum PasteboardImage {
    static func current() -> (data: Data, mime: String)? {
        #if os(macOS)
        let pasteboard = NSPasteboard.general

        if let png = pasteboard.data(forType: .png) {
            return (png, "image/png")
        }
        // Screenshots and many apps put TIFF on the pasteboard; re-encode it so the
        // stored attachment is something every platform renders.
        if
            let tiff = pasteboard.data(forType: .tiff),
            let representation = NSBitmapImageRep(data: tiff),
            let png = representation.representation(using: .png, properties: [:])
        {
            return (png, "image/png")
        }
        return nil
        #else
        guard let image = UIPasteboard.general.image, let png = image.pngData() else {
            return nil
        }
        return (png, "image/png")
        #endif
    }
}
