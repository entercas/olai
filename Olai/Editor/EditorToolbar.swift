import SwiftUI

/// Formatting controls above the web view. Everything here is SwiftUI; the editor only
/// receives command names.
struct EditorToolbar: View {
    let controller: EditorController
    let onInsertImage: () -> Void
    let onScheduleTask: () -> Void

    private var state: EditorState { controller.state }

    /// One place to tune how big the controls read.
    private enum Metrics {
        static let symbol: CGFloat = 16
        static let width: CGFloat = 34
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
                    button("highlighter", "Highlight", on: state.highlight) { controller.run("highlight") }
                }

                divider

                group {
                    button("textformat.size.larger", "Heading 1", on: state.h1) { controller.run("h1") }
                    button("textformat.size", "Heading 2", on: state.h2) { controller.run("h2") }
                    button("textformat.size.smaller", "Heading 3", on: state.h3) { controller.run("h3") }
                }

                divider

                group {
                    button("list.bullet", "Bullet List", on: state.bulletList) { controller.run("bulletList") }
                    button("list.number", "Numbered List", on: state.orderedList) { controller.run("orderedList") }
                    button("checklist", "Checklist", on: state.taskList) { controller.run("taskList") }
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

                    button("photo", "Insert Image", action: onInsertImage)
                    button(
                        state.task.reminderID == nil ? "bell" : "bell.fill",
                        state.task.reminderID == nil ? "Schedule Task" : "Change Reminder",
                        on: state.task.reminderID != nil,
                        enabled: state.task.active,
                        action: onScheduleTask
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Metrics.spacing) { content() }
    }

    private var divider: some View {
        Divider().frame(height: 20).padding(.horizontal, 6)
    }

    private func button(
        _ symbol: String,
        _ title: String,
        on: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Metrics.symbol, weight: .medium))
                .frame(width: Metrics.width, height: Metrics.height)
                .contentShape(.rect)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.corner)
                        .fill(.tint.opacity(on ? 0.22 : 0))
                )
                .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(title)
        .accessibilityLabel(title)
    }
}
