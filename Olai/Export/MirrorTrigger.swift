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

/// Where the mirror is written, when there is one.
///
/// The importer needs it to refuse importing the mirror back into itself, which would
/// make a second copy of every page. Nil on iOS, where there is no mirror at all.
private struct MirrorRootKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

extension EnvironmentValues {
    var mirrorRoot: URL? {
        get { self[MirrorRootKey.self] }
        set { self[MirrorRootKey.self] = newValue }
    }
}
