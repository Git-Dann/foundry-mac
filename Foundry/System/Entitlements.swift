import Foundation
import Security

/// What this build was signed with. An ad-hoc local build has no App Group, and touching the
/// group's defaults then makes macOS ask about accessing other apps' data, so the widget feed
/// is skipped instead.
enum Entitlements {
    static let hasAppGroup: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil),
              let groups = value as? [String]
        else { return false }
        return groups.contains(FoundryAppGroup.identifier)
    }()
}
