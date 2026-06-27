// HistoryView.swift

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \UsageEvent.timestamp, order: .reverse) private var events: [UsageEvent]
    @Query private var settings: [AppSettings]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    private var grouped: [(day: Date, events: [UsageEvent])] {
        StashService.groupedByDay(events)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Space.l) {
                    headerSection

                    if events.isEmpty {
                        emptyState
                    } else {
                        ForEach(grouped, id: \.day) { group in
                            VStack(alignment: .leading, spacing: Space.s) {
                                FFEyebrow(text: HistoryView.dayLabel(group.day).uppercased())
                                ForEach(group.events) { event in
                                    UsageEventCard(event: event, unit: appSettings.preferredUnit)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.screenPad)
                .padding(.top, Space.s)
                .padding(.bottom, Space.tabBarClearance)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .tracksTabBar()
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
            FFEyebrow(text: summaryEyebrow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryEyebrow: String {
        let unit = appSettings.preferredUnit
        let usedOz = events.filter { $0.kind == .used }.map(\.totalVolumeOz).reduce(0, +)
        let count = events.count
        let entries = "\(count) ENTR\(count == 1 ? "Y" : "IES")"
        return "\(entries) · \(UnitConversion.formatted(usedOz, in: unit)) USED"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(Color.ffTerra.opacity(0.5))
            Text("No history yet")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
            Text("When you use or discard milk, it'll show up here.")
                .font(.subheadline)
                .foregroundStyle(Color.ffInk2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Day label

    static func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return DateFormatter.historyDay.string(from: day)
    }
}

// MARK: - Usage Event Card

private struct UsageEventCard: View {
    let event: UsageEvent
    let unit: MilkUnit

    private var isUsed: Bool { event.kind == .used }
    private var accent: Color { isUsed ? Color.ffSage : Color.ffButter }
    private var accentSoft: Color { isUsed ? Color.ffSageSoft : Color.ffButterSoft }

    var body: some View {
        let lines = event.lines   // decode JSON once per render
        return FFCard {
            VStack(alignment: .leading, spacing: Space.m) {
                // Kind badge + time
                HStack(spacing: Space.s) {
                    HStack(spacing: 5) {
                        Image(systemName: isUsed ? "drop.fill" : "trash.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(event.kind.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentSoft)
                    .clipShape(Capsule())

                    Spacer()

                    Text(DateFormatter.historyTime.string(from: event.timestamp))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.ffInk3)
                }

                // Totals
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(UnitConversion.formatted(event.totalVolumeOz, in: unit))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ffInk)
                    Text("· \(event.totalBags) bag\(event.totalBags == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.ffInk2)
                }

                // Per-Ziplock snapshot lines
                if !lines.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                            if idx > 0 { FFDivider() }
                            HStack(spacing: Space.s) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.labelCode.isEmpty ? "Brick" : line.labelCode)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.ffInk)
                                    Text("Frozen \(DateFormatter.freeze.string(from: line.freezeDate))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.ffInk3)
                                }
                                Spacer()
                                Text("\(line.milkBags) · \(UnitConversion.formatted(line.volumeOz, in: unit))")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color.ffInk2)
                            }
                            .padding(.vertical, Space.s)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .background(Color.ffSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.l))
                }
            }
        }
    }
}

// MARK: - Date Formatters

extension DateFormatter {
    static let historyDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    static let historyTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}

#Preview {
    HistoryView()
        .modelContainer(PreviewData.container())
}
