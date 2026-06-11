import SwiftUI

// MARK: - FoundryCard
// The core bento widget container. All dashboard and overview widgets use this.
//
// Header: "01 // TITLE" — SF Mono 10px, uppercase, 1.2px tracking, neutral tone.
// Border: hairline (0.5px), 10px radius.
// This is the macOS implementation of the DESIGN.md `FoundryCard` pattern.

struct FoundryCard<Content: View>: View {
    let index: Int
    let title: String
    private let trailingView: AnyView
    let content: Content

    init(
        index: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.index = index
        self.title = title
        self.trailingView = AnyView(EmptyView())
        self.content = content()
    }

    init<T: View>(
        index: Int,
        title: String,
        @ViewBuilder trailing: () -> T,
        @ViewBuilder content: () -> Content
    ) {
        self.index = index
        self.title = title
        self.trailingView = AnyView(trailing())
        self.content = content()
    }

    private var headerText: String {
        String(format: "%02d // %@", index, title.uppercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header strip — 36pt, hairline bottom border
            HStack(alignment: .center, spacing: 0) {
                Text(headerText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                trailingView
            }
            .frame(height: 36)
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.03))

            Divider().opacity(0.5)

            content
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - StatDisplay
// Large editorial stat figure (New York serif) + mono uppercase label.
// Used inside FoundryCard bodies for key metric readouts.

struct StatDisplay: View {
    let value: String
    let label: String
    var tint: Color = .primary
    var size: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .regular, design: .serif))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - FoundryBadge
// Non-pill inline badge. Contrast with StatusChip (capsule) — use FoundryBadge for
// counts, labels, and indicators where the rectangular form reads as data, not state.

struct FoundryBadge: View {
    let text: String
    let tint: Color
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - UnreadDot
// Compact unread indicator: a filled circle (≤9) or a badge (10+). Used in Care rows.

struct UnreadDot: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count < 10 ? "\(count)" : "9+")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, count < 10 ? 0 : 4)
                .padding(.vertical, 2)
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.foundryBlue, in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

// MARK: - InitialAvatar
// Circular initial letter for clients/contacts where no logo is available.

struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 32
    var tint: Color = .foundryBlue

    private var initial: String {
        String(name.first ?? "?").uppercased()
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.38, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: Circle())
    }
}

// MARK: - FoundryDivider
// Hairline divider — thinner than the system Divider for use inside cards.

struct FoundryDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }
}
