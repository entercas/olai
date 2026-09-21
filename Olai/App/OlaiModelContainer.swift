import Foundation
import OlaiCore
import SwiftData
#if os(macOS)
import Security
#endif

/// Builds the app's `ModelContainer`.
///
/// The store syncs through the CloudKit private database. When that container cannot be
/// opened — no iCloud account on the device, or a simulator without one — the app falls
/// back to a local store so it still runs; sync is verified on real devices.
enum OlaiModelContainer {
    static func make() -> ModelContainer {
        let schema = OlaiSchema.schema

        // Only ask for CloudKit when this build is actually entitled to the container.
        // Asking without the entitlement does not fail in a way that can be caught:
        // CloudKit traps on its own queue during setup, taking the app down before any
        // fallback here could run.
        if isEntitledToCloudKit {
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
        } else {
            NSLog("Olai: built without the iCloud entitlement; using a local store. Notes do not sync.")
        }

        do {
            let local = ModelConfiguration("Olai", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Olai: could not open a local store: \(error)")
        }
    }

    /// Whether this build carries an iCloud container entitlement.
    ///
    /// Only the Mac can be built without one — the local variant, signed with no Apple
    /// ID and no provisioning profile. An iPhone build always has a profile, and
    /// `SecTaskCreateFromSelf` is macOS-only, so the question does not arise there.
    private static var isEntitledToCloudKit: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let key = "com.apple.developer.icloud-container-identifiers" as CFString
        let containers = SecTaskCopyValueForEntitlement(task, key, nil) as? [String]
        return !(containers ?? []).isEmpty
        #else
        return true
        #endif
    }
}
