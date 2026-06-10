import Foundation
import WidgetKit

/// Reads/writes the `WidgetSnapshot` in the shared App Group defaults. Compiled into BOTH the
/// main app (writer) and the widget extension (reader). Mirrors the iOS app's
/// AppGroupStore/WidgetSnapshot pattern. Failures are silent by design — widget data is
/// best-effort and must never affect app behaviour.
enum AppGroupStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: FoundryAppGroup.identifier)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func read() -> WidgetSnapshot {
        guard let raw = defaults?.data(forKey: FoundryAppGroup.snapshotKey),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: raw)
        else { return .empty }
        return snapshot
    }

    /// Load → mutate one slice → save → ask WidgetKit to refresh.
    static func update(_ mutate: (inout WidgetSnapshot) -> Void) {
        var snapshot = read()
        mutate(&snapshot)
        snapshot.updatedAt = Date()
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults?.set(data, forKey: FoundryAppGroup.snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
