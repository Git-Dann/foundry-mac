import SwiftUI
import WidgetKit

/// The "Today" widget's content. Lives in Shared so the app can render it for screenshots too.
struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily

    private var items: [WidgetSnapshot.Item] { snapshot.today(at: date) }
    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge, .systemExtraLarge: 9
        default: 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            header
            if !snapshot.signedIn {
                Spacer(minLength: 0)
                Text("Open Foundry to sign in.").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if items.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing due today.")
                    .font(family == .systemSmall ? .callout : .body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(items.prefix(limit)) { item in
                    Link(destination: URL(string: "foundry://commitment/\(item.id)")!) {
                        row(item).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                if items.count > limit {
                    Text("+\(items.count - limit) more").font(.caption).foregroundStyle(.secondary)
                }
                let tomorrow = snapshot.items.filter { item in
                    guard let due = item.dueAt else { return false }
                    return due >= date && !Calendar.current.isDate(due, inSameDayAs: date)
                }
                if family == .systemLarge, items.count < limit, !tomorrow.isEmpty {
                    Text("Tomorrow").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(tomorrow.prefix(limit - items.count)) { item in
                        Link(destination: URL(string: "foundry://commitment/\(item.id)")!) {
                            row(item).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today").font(.headline)
            Spacer()
            if snapshot.signedIn && !items.isEmpty {
                Text("\(items.count)").font(.headline).foregroundStyle(.tint).monospacedDigit()
            }
            if snapshot.signedIn && snapshot.reviewCount > 0 && family != .systemSmall {
                Text("· \(snapshot.reviewCount) to review").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        let overdue = snapshot.isOverdue(item, at: date)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(family == .systemSmall ? .caption : .callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                if family != .systemSmall, let due = item.dueAt {
                    Text(overdue ? "Overdue" : due.formatted(.dateTime.hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
        }
    }
}
