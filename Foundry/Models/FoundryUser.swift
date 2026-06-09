import Foundation

/// The signed-in user. Returned by `/api/auth/mobile-callback` (`{ token, user }`) and also
/// recoverable from the JWT's own claims (the desktop bridge returns only the token).
struct FoundryUser: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let email: String
    var name: String?
    let role: String
    let permissions: [String]

    var displayName: String { name?.isEmpty == false ? name! : email }

    var roleLabel: String {
        switch role {
        case "SUPER_ADMIN": return "Super Admin"
        case "ADMIN": return "Admin"
        case "STAFF": return "Staff"
        case "DEVELOPER": return "Developer"
        default: return role.capitalized
        }
    }

    func can(_ permission: String) -> Bool {
        role == "SUPER_ADMIN" || role == "ADMIN" || permissions.contains(permission)
    }
}

extension FoundryUser {
    /// Best-effort decode of the user identity from a Foundry mobile JWT's payload.
    ///
    /// This only *reads* the claims for display (id/email/role/permissions). It does NOT verify
    /// the signature — the server re-verifies every request — so it never trusts the token for
    /// authorization, only to populate the account UI without an extra round-trip.
    init?(jwt: String) {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3,
              let payload = FoundryUser.base64URLDecode(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sub = json["sub"] as? String,
              let email = json["email"] as? String
        else { return nil }

        self.id = sub
        self.email = email
        self.name = json["name"] as? String
        self.role = (json["role"] as? String) ?? "STAFF"
        self.permissions = (json["permissions"] as? [String]) ?? []
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 { base64 += String(repeating: "=", count: 4 - padding) }
        return Data(base64Encoded: base64)
    }
}

/// `/api/auth/mobile-callback` response shape (kept for parity / future native sign-in paths).
struct MobileAuthResponse: Codable, Sendable {
    let token: String
    let user: FoundryUser
}
