import OlaiCore
import SwiftData
import SwiftUI

/// The colours a folder can be tabbed with, the way a ring binder has coloured dividers.
///
/// Index 0 is "no tag" and draws nothing, so a library nobody has coloured stays quiet
/// rather than being assigned colours it did not ask for.
enum FolderTag {
    struct Choice: Identifiable {
        let index: Int
        let name: String
        let color: Color
        var id: Int { index }
    }

    static let choices: [Choice] = [
        Choice(index: 0, name: "None", color: .clear),
        Choice(index: 1, name: "Red", color: Color(red: 0.84, green: 0.29, blue: 0.26)),
        Choice(index: 2, name: "Orange", color: Color(red: 0.90, green: 0.55, blue: 0.19)),
        Choice(index: 3, name: "Yellow", color: Color(red: 0.90, green: 0.76, blue: 0.20)),
        Choice(index: 4, name: "Green", color: Color(red: 0.31, green: 0.63, blue: 0.36)),
        Choice(index: 5, name: "Teal", color: Color(red: 0.22, green: 0.62, blue: 0.63)),
        Choice(index: 6, name: "Blue", color: Color(red: 0.20, green: 0.49, blue: 0.85)),
        Choice(index: 7, name: "Purple", color: Color(red: 0.55, green: 0.38, blue: 0.78)),
        Choice(index: 8, name: "Pink", color: Color(red: 0.85, green: 0.40, blue: 0.60)),
        Choice(index: 9, name: "Grey", color: Color(red: 0.48, green: 0.51, blue: 0.55)),
    ]

    static func color(_ index: Int) -> Color? {
        guard index > 0, index < choices.count else { return nil }
        return choices[index].color
    }

    /// A folder with no tag of its own takes its nearest tagged ancestor's, so a
    /// subfolder reads as part of the same section of the binder.
    static func inheritedColor(for folder: Folder) -> Color? {
        var node: Folder? = folder
        var depth = 0
        while let current = node, depth < 64 {
            if let color = color(current.colorIndex) { return color }
            node = current.parent
            depth += 1
        }
        return nil
    }
}

/// The colour picker offered in a folder's context menu.
struct FolderTagMenu: View {
    @Bindable var folder: Folder
    let onChange: () -> Void

    var body: some View {
        Menu("Tag Colour") {
            ForEach(FolderTag.choices) { choice in
                Button {
                    folder.colorIndex = choice.index
                    onChange()
                } label: {
                    if choice.index == folder.colorIndex {
                        Label(choice.name, systemImage: "checkmark")
                    } else {
                        Text(choice.name)
                    }
                }
            }
        }
    }
}

/// The strip of coloured tabs that stands in for the notebook column while it is hidden.
///
/// Collapsing the folders used to mean losing the only way to change folder without
/// bringing them back. These are the top-level folders as binder tabs: the colour and
/// the first letter, with the full name on hover.
struct FolderTagRail: View {
    let folders: [Folder]
    @Binding var scope: NotebookScope?

    var body: some View {
        VStack(spacing: 6) {
            tab(
                label: "All",
                color: .secondary,
                isSelected: scope == .allPages,
                title: "All Pages"
            ) { scope = .allPages }

            Divider().frame(width: 18)

            ForEach(folders) { folder in
                tab(
                    label: String(folder.name.prefix(1)).uppercased(),
                    color: FolderTag.inheritedColor(for: folder) ?? .secondary,
                    isSelected: scope == .folder(folder.id),
                    title: folder.name
                ) { scope = .folder(folder.id) }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(width: 34)
        .background(.bar)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func tab(
        label: String,
        color: Color,
        isSelected: Bool,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : color)
                .frame(width: 22, height: 26)
                .background(
                    // Rounded on the right only, so each one reads as a tab sticking out
                    // of the edge rather than a button.
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 6,
                        topTrailingRadius: 6
                    )
                    .fill(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.22)))
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(title)
        .accessibilityLabel(title)
    }
}
