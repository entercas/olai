import OlaiCore
import SwiftData
import SwiftUI

/// The strip of open pages above the editor.
///
/// Hidden when only one page is open: a bar with a single tab in it is a row of chrome
/// that says nothing, and most of the time one page is all there is.
struct EditorTabBar: View {
    let tabs: OpenTabs
    let pages: [Page]

    var body: some View {
        if tabs.ids.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.ids, id: \.self) { id in
                        if let page = pages.first(where: { $0.id == id }) {
                            tab(for: page)
                            Divider().frame(height: 16)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(.bar)
            Divider()
        }
    }

    private func tab(for page: Page) -> some View {
        let isActive = tabs.active == page.id

        return HStack(spacing: 5) {
            Text(page.title.isEmpty ? "Untitled" : page.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                tabs.close(page.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 180)
        .background(isActive ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
        .contentShape(.rect)
        .onTapGesture { tabs.activate(page.id) }
        .pointingHandCursor()
        .contextMenu {
            Button("Close") { tabs.close(page.id) }
            Button("Close Others") { tabs.closeOthers(than: page.id) }
            Button("Close All") { tabs.closeAll() }
        }
        .help(page.title.isEmpty ? "Untitled" : page.title)
    }
}
