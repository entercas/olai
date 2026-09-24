import OlaiCore
import SwiftData
import SwiftUI

/// The strip of open pages above the editor.
///
/// Hidden when only one page is open: a bar with a single tab in it is a row of chrome
/// that says nothing, and most of the time one page is all there is.
///
/// Two things here are deliberate, because the first version worked on macOS 26 and
/// was dead on macOS 15:
///
/// - It is a plain row, not a horizontal `ScrollView`. A scroll view at the top of a
///   column extends itself up under the window toolbar and relies on a content inset to
///   push its contents back down; how, and whether, that inset applies to a horizontal
///   scroller differs between releases. Where it did not, the tabs sat beneath the
///   toolbar, which took every click. Tabs now shrink to share the width instead, the
///   way a browser's do, and `OpenTabs` caps how many there can be.
/// - Each tab is a real button, with the close button beside it rather than inside a
///   tap gesture. A tap gesture on a container competes with any button inside it, it
///   cannot be triggered from the keyboard or VoiceOver, and the accessibility system --
///   which is how the UI smoke test drives the app -- saw only static text.
struct EditorTabBar: View {
    let tabs: OpenTabs
    let pages: [Page]

    private var openPages: [Page] {
        tabs.ids.compactMap { id in pages.first { $0.id == id } }
    }

    var body: some View {
        if openPages.count > 1 {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(openPages) { page in
                        TabItem(
                            title: page.title.isEmpty ? "Untitled" : page.title,
                            isActive: tabs.active == page.id,
                            activate: { tabs.activate(page.id) },
                            close: { tabs.close(page.id) },
                            closeOthers: { tabs.closeOthers(than: page.id) },
                            closeAll: { tabs.closeAll() }
                        )
                        Divider().frame(height: 16)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 32)
                .background(.bar)
                Divider()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Open pages")
        }
    }
}

private struct TabItem: View {
    let title: String
    let isActive: Bool
    let activate: () -> Void
    let close: () -> Void
    let closeOthers: () -> Void
    let closeAll: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: activate) {
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isActive ? .isSelected : [])

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(Color.primary.opacity(isHovering ? 0.12 : 0))
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.trailing, 6)
            .onHover { isHovering = $0 }
            .help("Close “\(title)”")
            .accessibilityLabel("Close \(title)")
        }
        // Shares the row with its neighbours: at least wide enough to hit, at most as
        // wide as a readable title.
        .frame(minWidth: 64, maxWidth: 180)
        .background(isActive ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(.tint).frame(height: 2)
            }
        }
        .pointingHandCursor()
        .contextMenu {
            Button("Close", action: close)
            Button("Close Others", action: closeOthers)
            Button("Close All", action: closeAll)
        }
        .help(title)
    }
}
