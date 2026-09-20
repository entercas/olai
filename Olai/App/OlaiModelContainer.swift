import Foundation
import OlaiCore
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// The store syncs through the CloudKit private database. When that container cannot be
/// opened — no iCloud account on the device, or a simulator without one — the app falls
/// back to a local store so it still runs; sync is verified on real devices.
enum OlaiModelContainer {
    static func make() -> ModelContainer {
        let schema = OlaiSchema.schema

        do {
            let cloud = ModelConfiguration(
                "Olai",
                schema: schema,
                cloudKitDatabase: .private(OlaiSchema.identifier)
            )
            return try ModelContainer(for: schema, configurations: cloud)
        } catch {
            NSLog("Olai: CloudKit store unavailable (\(error)); falling back to a local store.")
        }

        do {
            let local = ModelConfiguration("Olai", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Olai: could not open a local store: \(error)")
        }
    }
}
