import SwiftUI

/// Formatting controls above the web view. Everything here is SwiftUI; the editor only
/// receives command names.
struct EditorToolbar: View {
    let controller: EditorController
    let dictation: DictationService
    let onInsertImage: () -> Void
    let onScheduleTask: () -> Void

    private var state: EditorState { controller.state }

    /// One place to tune how big the controls read.
    private enum Metrics {
        static let symbol: CGFloat = 16
        static let width: CGFloat = 34
        static let wideWidth: CGFloat = 46
        static let height: CGFloat = 30
        static let corner: CGFloat = 7
        static let spacing: CGFloat = 3
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.spacing) {
                group {
                    button("arrow.uturn.backward", "Undo", enabled: state.canUndo) { controller.run("undo") }
                    button("arrow.uturn.forward", "Redo", enabled: state.canRedo) { controller.run("redo") }
                }

                divider

                group {
                    button("bold", "Bold", on: state.bold) { controller.run("bold") }
                    button("italic", "Italic", on: state.italic) { controller.run("italic") }
                    button("underline", "Underline", on: state.underline) { controller.run("underline") }
                    button("strikethrough", "Strikethrough", on: state.strike) { controller.run("strike") }
                }

                divider

                group {
                    colorMenu(
                        symbol: "character",
                        title: "Text Colour",
                        selected: state.textColor,
                        swatches: Palette.text,
                        clearTitle: "Default"
                    ) { controller.run("setTextColor", payload: $0.map { ["color": $0] } ?? [:]) }

                    colorMenu(
                        symbol: "highlighter",
                        title: "Highlight",
                        selected: state.highlightColor,
                        swatches: Palette.highlight,
                        clearTitle: "No Highlight"
                    ) { controller.run("setHighlightColor", payload: $0.map { ["color": $0] } ?? [:]) }
                }

                divider

                styleMenu

                divider

                group {
                    button("list.bullet", "Bullet List", on: state.bulletList, wide: true) { controller.run("bulletList") }
                    button("list.number", "Numbered List", on: state.orderedList, wide: true) { controller.run("orderedList") }
                    button("checklist", "Checklist", on: state.taskList, wide: true) { controller.run("taskList") }
                    button("increase.indent", "Indent") { controller.run("indent") }
                    button("decrease.indent", "Outdent") { controller.run("outdent") }
                }

                divider

                group {
                    button(
                        "point.topleft.down.to.point.bottomright.curvepath",
                        state.mindMap ? "Back to the Page" : "Mind Map",
                        on: state.mindMap
                    ) { controller.run("toggleMindMap") }

                    button(
                        dictation.state.isRunning ? "mic.fill" : "mic",
                        dictationTitle,
                        on: dictation.state.isRunning
                    ) {
                        Task { await dictation.toggle() }
                    }

                    button("photo", "Insert Image", action: onInsertImage)
                    button(
                        state.task.reminderID == nil ? "bell" : "bell.fill",
                        reminderTitle,
                        on: state.task.reminderID != nil,
                        wide: true,
                        action: scheduleTask
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// Paragraph style as one control. Four separate buttons said the same thing four
    /// times over and still left the current style to be inferred from which one was lit.
    private var styleMenu: some View {
        Menu {
            ForEach(BlockStyle.all) { style in
                Button {
                    controller.run(style.command)
                } label: {
                    if style.command == currentStyle.command {
                        Label(style.name, systemImage: "checkmark")
                    } else {
                        Text(style.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentStyle.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 96, height: Metrics.height)
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 96)
        .pointingHandCursor()
        .help("Paragraph Style")
        .accessibilityLabel("Paragraph Style")
    }

    private var currentStyle: BlockStyle {
        if state.h1 { return BlockStyle.all[1] }
        if state.h2 { return BlockStyle.all[2] }
        if state.h3 { return BlockStyle.all[3] }
        return BlockStyle.all[0]
    }

    /// Only a checklist item can be scheduled, so a caret anywhere else used to leave
    /// this greyed out with nothing saying why -- and since the reminder lives on the
    /// task, there was no way to get there but to know the rule. It now makes the
    /// current line a task first, then asks for the date.
    private func scheduleTask() {
        guard !state.task.active else {
            onScheduleTask()
            return
        }
        controller.run("taskList")
        Task {
            // The editor reports the new task back over the bridge; the sheet reads the
            // task's text from that, so it is worth the moment's wait.
            try? await Task.sleep(for: .milliseconds(150))
            onScheduleTask()
        }
    }

    private var reminderTitle: String {
        if state.task.reminderID != nil { return "Change Reminder" }
        return state.task.active ? "Schedule Task" : "Make this a task and schedule it"
    }

    private var dictationTitle: String {
        switch dictation.state {
        case .idle: "Dictate"
        case .starting: "Starting…"
        case .listening: "Stop Dictating"
        case let .failed(message): message
        }
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Metrics.spacing) { content() }
    }

    private var divider: some View {
        Divider().frame(height: 20).padding(.horizontal, 6)
    }

    // MARK: Controls

    /// - Parameter wide: for the controls reached for constantly -- lists, checklist,
    ///   the reminder -- which were the same 34pt as everything else and easy to miss.
    private func button(
        _ symbol: String,
        _ title: String,
        on: Bool = false,
        enabled: Bool = true,
        wide: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        control(
            title: title,
            on: on,
            enabled: enabled,
            width: wide ? Metrics.wideWidth : Metrics.width,
            action: action
        ) {
            Image(systemName: symbol)
                .font(.system(size: wide ? Metrics.symbol + 2 : Metrics.symbol, weight: .medium))
        }
    }

    private func control<Content: View>(
        title: String,
        on: Bool,
        enabled: Bool,
        width: CGFloat? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(minWidth: width ?? Metrics.width, minHeight: Metrics.height)
                .contentShape(.rect)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.corner)
                        .fill(.tint.opacity(on ? 0.22 : 0))
                )
                .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(ToolbarButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(title)
        .accessibilityLabel(title)
    }

    private func colorMenu(
        symbol: String,
        title: String,
        selected: String?,
        swatches: [Palette.Swatch],
        clearTitle: String,
        apply: @escaping (String?) -> Void
    ) -> some View {
        Menu {
            Button(clearTitle) { apply(nil) }
            Divider()
            ForEach(swatches) { swatch in
                Button {
                    apply(swatch.hex)
                } label: {
                    Label {
                        Text(swatch.name)
                    } icon: {
                        Image(systemName: selected?.caseInsensitiveCompare(swatch.hex) == .orderedSame
                              ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: Metrics.symbol - 2, weight: .medium))
                // The bar under the glyph shows what colour is in force, the way every
                // other editor does it.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: selected) ?? .secondary.opacity(0.35))
                    .frame(height: 3)
                    .padding(.horizontal, 5)
            }
            .frame(width: Metrics.width, height: Metrics.height)
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Metrics.width)
        .pointingHandCursor()
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Presses need to look like presses: a plain button gives no feedback at all, so a
/// click on a formatting control felt like nothing had happened even when it had.
private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .pointingHandCursor()
    }
}

extension View {
    /// The web view sets an I-beam as the pointer crosses it, and that cursor was still
    /// showing over the toolbar above it, so the controls did not read as clickable.
    func pointingHandCursor() -> some View {
        #if os(macOS)
        onHover { inside in
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        #else
        self
        #endif
    }
}

/// What the style menu offers. Ordered so the first entry is the one a page is in by
/// default, which is also what the menu falls back to showing.
struct BlockStyle: Identifiable {
    let name: String
    let command: String
    var id: String { command }

    static let all: [BlockStyle] = [
        BlockStyle(name: "Body", command: "paragraph"),
        BlockStyle(name: "Heading 1", command: "h1"),
        BlockStyle(name: "Heading 2", command: "h2"),
        BlockStyle(name: "Heading 3", command: "h3"),
    ]
}

/// The colours offered for text and highlight. Deliberately a short list: a full picker
/// invites a page where every line is a different colour, and none of it survives into
/// the Markdown mirror.
enum Palette {
    struct Swatch: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    static let text: [Swatch] = [
        Swatch(name: "Red", hex: "#D1453B"),
        Swatch(name: "Orange", hex: "#C2610B"),
        Swatch(name: "Green", hex: "#2F7D4F"),
        Swatch(name: "Blue", hex: "#1F6FEB"),
        Swatch(name: "Purple", hex: "#7C4DBE"),
        Swatch(name: "Grey", hex: "#6E7178"),
    ]

    static let highlight: [Swatch] = [
        Swatch(name: "Yellow", hex: "#FBEBA0"),
        Swatch(name: "Green", hex: "#B4E1A0"),
        Swatch(name: "Blue", hex: "#A9D3F5"),
        Swatch(name: "Pink", hex: "#F5B8D0"),
        Swatch(name: "Orange", hex: "#F8CD9C"),
        Swatch(name: "Grey", hex: "#DCDEE1"),
    ]
}

extension Color {
    /// `#RRGGBB` as the editor reports it. Anything else is no colour rather than black,
    /// so an unreadable value shows as "no colour set" instead of a wrong one.
    init?(hex: String?) {
        guard var value = hex?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number & 0xFF0000) >> 16) / 255,
            green: Double((number & 0x00FF00) >> 8) / 255,
            blue: Double(number & 0x0000FF) / 255
        )
    }
}
