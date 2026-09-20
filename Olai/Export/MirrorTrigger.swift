import SwiftUI

/// How views ask for a mirror export without knowing whether there is one.
///
/// An earlier version listened for `ModelContext.didSave`, which never arrived: the
/// store saved and the mirror sat unchanged. Asking explicitly at the points that
/// change something is one line per mutation and cannot silently stop working.
private struct ScheduleMirrorExportKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var scheduleMirrorExport: @MainActor () -> Void {
        get { self[ScheduleMirrorExportKey.self] }
        set { self[ScheduleMirrorExportKey.self] = newValue }
    }
}
