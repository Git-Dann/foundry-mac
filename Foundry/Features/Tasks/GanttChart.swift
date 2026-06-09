import SwiftUI

/// Dependency-free Gantt: feature blocks as bars on a day-scale axis, milestones as diamonds, a
/// red "today" line, month gridlines, and a fixed left rail of block names. Zoomable. Read-only —
/// a block is a bar only when it has both a start and end date.
struct GanttView: View {
    let blocks: [FeatureBlock]
    let milestones: [Milestone]

    enum Zoom: String, CaseIterable, Identifiable {
        case month = "Month", quarter = "Quarter", half = "6 mo", year = "Year"
        var id: String { rawValue }
        var pointsPerDay: CGFloat {
            switch self {
            case .month: return 22
            case .quarter: return 9
            case .half: return 4.5
            case .year: return 2.4
            }
        }
    }

    @State private var zoom: Zoom = .quarter

    private let headerHeight: CGFloat = 26
    private let milestoneLaneHeight: CGFloat = 28
    private let rowHeight: CGFloat = 32
    private let railWidth: CGFloat = 168

    private var datedBlocks: [FeatureBlock] {
        blocks
            .filter { $0.startDate != nil && $0.endDate != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private var range: (start: Date, end: Date)? {
        var dates: [Date] = []
        for block in datedBlocks {
            if let start = block.startDate { dates.append(start) }
            if let end = block.endDate { dates.append(end) }
        }
        dates.append(contentsOf: milestones.map(\.date))
        guard let minDate = dates.min(), let maxDate = dates.max() else { return nil }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -3, to: minDate) ?? minDate
        let end = cal.date(byAdding: .day, value: 4, to: maxDate) ?? maxDate
        return (cal.startOfDay(for: start), cal.startOfDay(for: end))
    }

    var body: some View {
        if datedBlocks.isEmpty && milestones.isEmpty {
            ContentUnavailableView {
                Label("Nothing scheduled", systemImage: "chart.bar.xaxis")
            } description: {
                Text("Add start and end dates to a feature block to see it on the timeline.")
            }
        } else if let range {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Zoom", selection: $zoom) { ForEach(Zoom.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .padding([.horizontal, .top], 12)
                chart(range)
            }
        }
    }

    // MARK: Geometry

    private func days(_ from: Date, _ to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
    }

    private func xPosition(_ date: Date, _ range: (start: Date, end: Date)) -> CGFloat {
        CGFloat(days(range.start, date)) * zoom.pointsPerDay
    }

    private func monthStarts(_ range: (start: Date, end: Date)) -> [Date] {
        let cal = Calendar.current
        var result: [Date] = []
        guard var cursor = cal.date(from: cal.dateComponents([.year, .month], from: range.start)) else { return [] }
        while cursor <= range.end {
            if cursor >= range.start { result.append(cursor) }
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: Chart

    private func chart(_ range: (start: Date, end: Date)) -> some View {
        let totalDays = max(1, days(range.start, range.end))
        let totalWidth = CGFloat(totalDays) * zoom.pointsPerDay
        let contentHeight = headerHeight + milestoneLaneHeight + CGFloat(datedBlocks.count) * rowHeight

        return HStack(alignment: .top, spacing: 0) {
            rail
            ScrollView(.horizontal, showsIndicators: true) {
                timeline(range)
                    .frame(width: totalWidth, height: contentHeight, alignment: .topLeading)
            }
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            railCell(height: headerHeight) { EmptyView() }
            railCell(height: milestoneLaneHeight) {
                Text("Milestones").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(datedBlocks) { block in
                railCell(height: rowHeight) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.featureBlock(block.color)).frame(width: 7, height: 7)
                        Text(block.name).font(.caption).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: railWidth, alignment: .top)
        .overlay(Divider(), alignment: .trailing)
    }

    private func railCell<V: View>(height: CGFloat, @ViewBuilder content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .padding(.horizontal, 8)
    }

    private func timeline(_ range: (start: Date, end: Date)) -> some View {
        ZStack(alignment: .topLeading) {
            monthMarkers(range)
            todayLine(range)
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)
                milestoneLane(range).frame(height: milestoneLaneHeight)
                ForEach(datedBlocks) { block in
                    blockRow(block, range).frame(height: rowHeight)
                }
            }
        }
    }

    private func monthMarkers(_ range: (start: Date, end: Date)) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthStarts(range), id: \.self) { month in
                let x = xPosition(month, range)
                Rectangle().fill(.quaternary.opacity(0.5)).frame(width: 1).frame(maxHeight: .infinity).offset(x: x)
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2).foregroundStyle(.secondary)
                    .offset(x: x + 3, y: 4)
            }
        }
    }

    @ViewBuilder private func todayLine(_ range: (start: Date, end: Date)) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        if today >= range.start && today <= range.end {
            Rectangle().fill(.red).frame(width: 1.5).frame(maxHeight: .infinity).offset(x: xPosition(today, range))
        }
    }

    private func milestoneLane(_ range: (start: Date, end: Date)) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(milestones) { milestone in
                Image(systemName: "diamond.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.featureBlock(milestone.color))
                    .help("\(milestone.name) · \(Formatters.medium(milestone.date))")
                    .offset(x: xPosition(milestone.date, range) - 5, y: 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func blockRow(_ block: FeatureBlock, _ range: (start: Date, end: Date)) -> some View {
        if let start = block.startDate, let end = block.endDate {
            let startX = xPosition(start, range)
            let width = max(8, xPosition(end, range) - startX)
            let tint = Color.featureBlock(block.color)
            RoundedRectangle(cornerRadius: 5)
                .fill(tint.opacity(0.22))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(tint.opacity(0.5))
                        .frame(width: width * CGFloat(min(max(block.progress, 0), 100)) / 100)
                }
                .overlay(alignment: .leading) {
                    Text(block.name).font(.caption2).lineLimit(1).padding(.horizontal, 6)
                }
                .frame(width: width, height: rowHeight - 12)
                .offset(x: startX, y: 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
