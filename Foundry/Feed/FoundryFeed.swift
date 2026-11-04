import Foundation
import Observation

/// One thing happening in Foundry that may need you: a Slack message that @mentions you, or a
/// recent message in one of your clients' channels. Read from what Foundry already collects
/// (`/api/desk/mentions`, `/api/desk/slack`), so no AI runs and no credit is spent.
struct FeedItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case mention, clientMessage }
    var id: String
    var kind: Kind
    var author: String
    var text: String
    var at: Date
    var clientName: String
    var clientSlug: String
    var link: URL?

    /// "Reply to Luke (Wedge): Can you check the course…" — what this becomes as a to-do.
    var suggestedToDo: String {
        let gist = FeedItem.clip(text, to: 70)
        return "Reply to \(author) (\(clientName)): \(gist)"
    }

    static func clip(_ s: String, to n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count > n ? String(one.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…" : one
    }
}

/// Wire shapes (camelCase, as is).
struct DeskMessageDTO: Decodable, Sendable {
    var id: String
    var author: String
    var text: String
    var ts: Date
    var clientName: String
    var clientSlug: String
    var link: String?
}
struct DeskMentionsDTO: Decodable, Sendable {
    var configured: Bool
    var mapped: Bool
    var items: [DeskMessageDTO]
}
struct DeskSlackDTO: Decodable, Sendable {
    var configured: Bool
    var reason: String?
    var messages: [DeskMessageDTO]
}

enum FeedRules {
    /// The feed: mentions first (they're asking you), then other people's recent client messages,
    /// newest first. Your own messages, ones you've cleared, and anything over a week old drop out.
    static func build(
        mentions: [DeskMessageDTO], messages: [DeskMessageDTO], myName: String?, cleared: Set<String>,
        now: Date, base: URL
    ) -> [FeedItem] {
        let week = now.addingTimeInterval(-7 * 86_400)
        let me = myName.map(firstName) ?? ""
        func item(_ d: DeskMessageDTO, _ kind: FeedItem.Kind) -> FeedItem {
            FeedItem(
                id: d.id, kind: kind, author: d.author, text: d.text, at: d.ts,
                clientName: d.clientName, clientSlug: d.clientSlug,
                link: Commitment.link(d.link, base: base) ?? Commitment.link("/app/portal/\(d.clientSlug)", base: base)
            )
        }
        var seen = Set<String>()
        var out: [FeedItem] = []
        for d in mentions.sorted(by: { $0.ts > $1.ts }) where d.ts > week && !cleared.contains(d.id) && seen.insert(d.id).inserted {
            out.append(item(d, .mention))
        }
        for d in messages.sorted(by: { $0.ts > $1.ts }) where d.ts > week && !cleared.contains(d.id) {
            if !me.isEmpty, firstName(d.author) == me { continue }
            guard seen.insert(d.id).inserted else { continue }
            out.append(item(d, .clientMessage))
        }
        return out
    }

    static func firstName(_ s: String) -> String {
        s.split(separator: " ").first.map { $0.lowercased() } ?? ""
    }
}

@MainActor
@Observable
final class FoundryFeedStore {
    private(set) var items: [FeedItem] = []
    private(set) var problem: String?
    private(set) var isLoading = false
    private(set) var loadedAt: Date?

    @ObservationIgnored private let baseURL: @Sendable () async -> URL
    @ObservationIgnored private let token: @Sendable () async -> String?
    @ObservationIgnored private let network = NetworkClient()
    @ObservationIgnored var myName: () -> String? = { nil }
    @ObservationIgnored private var raw: (mentions: [DeskMessageDTO], messages: [DeskMessageDTO]) = ([], [])

    private static let clearedKey = "feed.cleared.v1"
    private var cleared: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.clearedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(500)), forKey: Self.clearedKey) }
    }

    init(baseURL: @escaping @Sendable () async -> URL, token: @escaping @Sendable () async -> String?) {
        self.baseURL = baseURL
        self.token = token
    }

    var mentionCount: Int { items.filter { $0.kind == .mention }.count }

    func refresh(force: Bool = false) async {
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 120 { return }
        guard !isLoading, let token = await token() else { return }
        isLoading = true
        defer { isLoading = false }
        let base = await baseURL()
        func req(_ path: String) -> APIRequest {
            APIRequest(url: base.appending(path: "api/desk/" + path), headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"])
        }
        async let m: DeskMentionsDTO = network.execute(req("mentions"))
        async let s: DeskSlackDTO = network.execute(req("slack"))
        var notes: [String] = []
        do {
            let mentions = try await m
            raw.mentions = mentions.items
            if mentions.configured && !mentions.mapped { notes.append("Your Foundry email isn't on a Slack account, so @mentions can't be found.") }
        } catch { notes.append("Slack mentions couldn't be read just now.") }
        do {
            let slack = try await s
            raw.messages = slack.messages
            if !slack.configured { notes.append("Slack isn't connected to Foundry.") }
        } catch { notes.append("Client Slack channels couldn't be read just now.") }
        problem = notes.isEmpty ? nil : notes.joined(separator: " ")
        loadedAt = Date()
        rebuild(base: base)
    }

    func clear(_ id: String) {
        cleared.insert(id)
        items.removeAll { $0.id == id }
    }

    private func rebuild(base: URL) {
        items = FeedRules.build(mentions: raw.mentions, messages: raw.messages, myName: myName(), cleared: cleared, now: Date(), base: base)
    }

    #if DEBUG
    func loadForPreview(_ items: [FeedItem]) {
        self.items = items
        loadedAt = Date()
    }
    #endif
}
