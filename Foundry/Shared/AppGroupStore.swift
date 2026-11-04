import Foundation
import WidgetKit

/// Reads/writes the `WidgetSnapshot` in the shared App Group defaults. Compiled into both the app
/// (writer) and the widget (reader). Failures are silent: widget data must never affect the app.
enum AppGroupStore {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: FoundryAppGroup.identifier) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    static func read() -> WidgetSnapshot {
        guard let raw = defaults?.data(forKey: FoundryAppGroup.snapshotKey),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: raw)
        else { return .empty }
        return snapshot
    }

    /// Writes only when the content changed, so the widget isn't reloaded for nothing.
    static func write(_ snapshot: WidgetSnapshot) {
        var old = read(); old.updatedAt = snapshot.updatedAt
        guard old != snapshot, let data = try? encoder.encode(snapshot) else { return }
        defaults?.set(data, forKey: FoundryAppGroup.snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
