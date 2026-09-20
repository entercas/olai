#if os(macOS)

import SwiftUI

/// Settings for the Markdown mirror: where it goes, and a way to write it now.
struct MirrorSettingsView: View {
    let settings: MirrorSettings
    let exporter: MirrorExporter

    @State private var isChoosing = false

    var body: some View {
        Form {
            Section("Markdown mirror") {
                LabeledContent("Folder") {
                    Text(settings.root?.path(percentEncoded: false) ?? "Not set")
                        .foregroundStyle(settings.root == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("Choose Folder…") { isChoosing = true }
                    if settings.root != nil {
                        Button("Export Now") { exporter.exportNow() }
                        Button("Stop Mirroring") { settings.clear() }
                    }
                }

                Text("""
                Every page is written as Markdown, and rewritten when it changes. Olai \
                never reads this folder back — files it did not write are left alone.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if let error = importError ?? settings.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fileImporter(
            isPresented: $isChoosing,
            allowedContentTypes: [.folder],
            onCompletion: choose
        )
        .fileDialogDefaultDirectory(settings.suggestedRoot)
    }

    @State private var importError: String?

    private func choose(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            settings.choose(url)
            exporter.exportNow()
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}

#endif
