// Drives the running Olai app through the accessibility API, for the UI smoke test.
//
//   swift Driver.swift dump [text]          print the element tree, optionally filtered
//   swift Driver.swift press <text> [n]     AXPress the nth element whose label contains text
//   swift Driver.swift click <text> [n]     click the centre of that element
//   swift Driver.swift rightclick <text> [n]
//   swift Driver.swift frame <text> [n]     print that element's frame
//   swift Driver.swift count <text>         how many elements match
//
// Every click is guarded: before the mouse goes down, the window under that exact point
// must belong to Olai. An earlier version checked only which app was frontmost, focus
// moved between the check and the click, and the click landed in someone's mail.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let appName = "Olai"

struct Node {
    let element: AXUIElement
    let role: String
    let label: String
    let frame: CGRect?
    let depth: Int
    /// Inside the editor's web content, as opposed to the page list or the toolbar.
    let inEditor: Bool
}

func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func frame(of element: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard
        let p: AXValue = attribute(element, kAXPositionAttribute),
        let s: AXValue = attribute(element, kAXSizeAttribute),
        AXValueGetValue(p, .cgPoint, &position),
        AXValueGetValue(s, .cgSize, &size)
    else { return nil }
    return CGRect(origin: position, size: size)
}

/// Everything a person could read off the element: its title, its description, its help
/// tag, its value. Matching against all of them is what makes `press "Close"` find a
/// button whose only name is its tooltip.
func label(of element: AXUIElement) -> String {
    let parts: [String?] = [
        attribute(element, kAXTitleAttribute),
        attribute(element, kAXDescriptionAttribute),
        attribute(element, kAXHelpAttribute),
        (attribute(element, kAXValueAttribute) as Any?).flatMap { $0 as? String },
        attribute(element, kAXIdentifierAttribute),
        // A search field's only name is its placeholder.
        attribute(element, kAXPlaceholderValueAttribute),
    ]
    return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ")
}

func walk(_ element: AXUIElement, depth: Int = 0, inEditor: Bool = false, into nodes: inout [Node]) {
    guard depth < 60 else { return }
    let role: String = attribute(element, kAXRoleAttribute) ?? "?"
    let within = inEditor || role == "AXWebArea"
    nodes.append(Node(element: element, role: role, label: label(of: element), frame: frame(of: element),
                      depth: depth, inEditor: within))
    let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
    for child in children { walk(child, depth: depth + 1, inEditor: within, into: &nodes) }
}

func olai() -> (NSRunningApplication, AXUIElement) {
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
        fputs("Olai is not running\n", stderr); exit(2)
    }
    return (app, AXUIElementCreateApplication(app.processIdentifier))
}

func nodes() -> [Node] {
    var result: [Node] = []
    walk(olai().1, into: &result)
    return result
}

/// How a query narrows the tree, applied in this order:
///   `editor/`          only the page's own text, not the page list's previews of it
///   `AXButton:`        only that role
///   `=Inbox`           a label that is exactly this, not "Inbox · Edited now"
///   anything else      a label containing the text, ignoring case
func matching(_ query: String) -> [Node] {
    var rest = query
    var editorOnly = false
    if rest.hasPrefix("editor/") {
        editorOnly = true
        rest = String(rest.dropFirst("editor/".count))
    }

    var role: String?
    if rest.hasPrefix("AX"), let colon = rest.firstIndex(of: ":") {
        role = String(rest[..<colon])
        rest = String(rest[rest.index(after: colon)...])
    }

    var exact = false
    if rest.hasPrefix("=") {
        exact = true
        rest = String(rest.dropFirst())
    }
    let text = rest

    return nodes().filter { node in
        guard !editorOnly || node.inEditor else { return false }
        guard role == nil || node.role == role else { return false }
        guard !text.isEmpty else { return true }
        if exact {
            return node.label.split(separator: "|").contains {
                $0.trimmingCharacters(in: .whitespaces) == text
            }
        }
        return node.label.localizedCaseInsensitiveContains(text)
    }
}

func pick(_ text: String, _ index: Int) -> Node {
    let found = matching(text)
    guard found.indices.contains(index) else {
        fputs("no element #\(index) matching \"\(text)\" (found \(found.count))\n", stderr); exit(3)
    }
    return found[index]
}

/// Which app owns the topmost normal window at this point, right now.
func ownerOfWindow(at point: CGPoint) -> String? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for window in list where (window[kCGWindowLayer as String] as? Int ?? 0) == 0 {
        guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                          width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
        if rect.contains(point) { return window[kCGWindowOwnerName as String] as? String }
    }
    return nil
}

func click(at point: CGPoint, button: CGMouseButton = .left) {
    if NSWorkspace.shared.frontmostApplication?.localizedName != appName {
        olai().0.activate()
        usleep(500_000)
    }
    func post(_ type: CGEventType) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }
    // Checked after the pointer arrives and again immediately before pressing, with no
    // sleep in between: the gap is where focus moved last time.
    post(.mouseMoved)
    usleep(150_000)
    guard ownerOfWindow(at: point) == appName else {
        fputs("REFUSED: the window at \(point) belongs to \(ownerOfWindow(at: point) ?? "nothing")\n", stderr)
        exit(4)
    }
    post(button == .left ? .leftMouseDown : .rightMouseDown)
    usleep(60_000)
    post(button == .left ? .leftMouseUp : .rightMouseUp)
}

// MARK: Commands

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fputs("usage: see header\n", stderr); exit(1) }
let text = args.count > 1 ? args[1] : ""
let index = args.count > 2 ? Int(args[2]) ?? 0 : 0

switch command {
case "dump":
    for node in nodes() where text.isEmpty || node.label.localizedCaseInsensitiveContains(text)
        || node.role.localizedCaseInsensitiveContains(text) {
        let f = node.frame.map { String(format: "(%.0f,%.0f %.0fx%.0f)", $0.minX, $0.minY, $0.width, $0.height) } ?? ""
        print(String(repeating: " ", count: min(node.depth, 30)) + "\(node.role) \(f) \(node.label)")
    }
case "count":
    print(matching(text).count)
case "frame":
    let node = pick(text, index)
    print(node.frame.map { "\($0.minX) \($0.minY) \($0.width) \($0.height)" } ?? "no frame")
case "press":
    let node = pick(text, index)
    let result = AXUIElementPerformAction(node.element, kAXPressAction as CFString)
    print(result == .success ? "pressed \(node.role) \(node.label)" : "AXPress failed (\(result.rawValue)) on \(node.role) \(node.label)")
    if result != .success { exit(5) }
case "clickend":
    // clickend <text> [n]: click 10pt in from the element's right edge -- the chevron of
    // a split button, which opens its menu where a plain click takes the default action.
    let node = pick(text, index)
    guard let f = node.frame else { fputs("element has no frame\n", stderr); exit(3) }
    let point = CGPoint(x: f.maxX - 10, y: f.midY)
    click(at: point)
    print("clicked the end of \(node.role) \(node.label) at \(Int(point.x)),\(Int(point.y))")
case "showmenu":
    // Opens a menu button's menu, for a button whose click does something else -- New
    // Page makes a blank page on a click and keeps its templates behind the menu.
    let node = pick(text, index)
    let result = AXUIElementPerformAction(node.element, kAXShowMenuAction as CFString)
    print(result == .success ? "opened menu of \(node.label)" : "AXShowMenu failed (\(result.rawValue))")
    if result != .success { exit(5) }
case "click", "rightclick":
    let node = pick(text, index)
    guard let f = node.frame else { fputs("element has no frame\n", stderr); exit(3) }
    let centre = CGPoint(x: f.midX, y: f.midY)
    click(at: centre, button: command == "click" ? .left : .right)
    print("\(command)ed \(node.role) \(node.label) at \(Int(centre.x)),\(Int(centre.y))")
case "value":
    let node = pick(text, index)
    let value = attribute(node.element, kAXValueAttribute) as Any?
    print((value as? String) ?? (value.map { "\($0)" } ?? ""))
case "type":
    // Typed only into Olai: refuses if anything else has keyboard focus.
    guard NSWorkspace.shared.frontmostApplication?.localizedName == appName else {
        fputs("REFUSED: Olai is not the frontmost app\n", stderr); exit(4)
    }
    for scalar in text.unicodeScalars {
        var unit = [UniChar](String(scalar).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: unit.count, unicodeString: &unit)
            event?.post(tap: .cghidEventTap)
        }
        usleep(12_000)
    }
    print("typed \(text.count) characters")
case "key":
    // key <virtual keycode> [cmd,shift,opt,ctrl]
    guard NSWorkspace.shared.frontmostApplication?.localizedName == appName else {
        fputs("REFUSED: Olai is not the frontmost app\n", stderr); exit(4)
    }
    let code = CGKeyCode(Int(text) ?? 0)
    var flags: CGEventFlags = []
    let mods = args.count > 2 ? args[2] : ""
    if mods.contains("cmd") { flags.insert(.maskCommand) }
    if mods.contains("shift") { flags.insert(.maskShift) }
    if mods.contains("opt") { flags.insert(.maskAlternate) }
    if mods.contains("ctrl") { flags.insert(.maskControl) }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
    print("key \(code) \(mods)")
case "windowid":
    // For `screencapture -l`, so a screenshot shows Olai's window and nothing else on screen.
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let window = list.first {
        ($0[kCGWindowOwnerName as String] as? String) == appName && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    print((window?[kCGWindowNumber as String] as? Int).map(String.init) ?? "")
case "resize":
    // resize <width> <height>: the main window, through the accessibility API.
    let width = Double(text) ?? 1200
    let height = args.count > 2 ? Double(args[2]) ?? 760 : 760
    guard let window = nodes().first(where: { $0.role == "AXWindow" }) else { exit(3) }
    var size = CGSize(width: width, height: height)
    let value = AXValueCreate(.cgSize, &size)!
    let result = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, value)
    print(result == .success ? "resized to \(Int(width))x\(Int(height))" : "resize failed (\(result.rawValue))")
case "maxx":
    // Right edge of the window, for checking a control is actually inside it.
    guard let window = nodes().first(where: { $0.role == "AXWindow" }), let f = window.frame else { exit(3) }
    print(Int(f.maxX))
case "activate":
    olai().0.activate()
    usleep(400_000)
    print("activated")
default:
    fputs("unknown command \(command)\n", stderr); exit(1)
}
