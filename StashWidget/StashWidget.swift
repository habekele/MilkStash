// StashWidget.swift
// Home/Lock Screen widget: the stash total and days of supply at a glance.
// Reads the snapshot the app publishes to the App Group on every background.

import WidgetKit
import SwiftUI

// MARK: - Snapshot

struct StashSnapshot {
    var totalOz: Double = 0
    var bricks: Int = 0
    var bags: Int = 0
    var days: Double = 0
    var unitRaw: String = "oz"
    var soonestExpiry: Date? = nil
    var hasData: Bool = false

    static func load() -> StashSnapshot {
        guard let defaults = UserDefaults(suiteName: "group.Henok.MilkStash"),
              let dict = defaults.dictionary(forKey: "stash_snapshot_v1") else {
            return StashSnapshot()
        }
        var snap = StashSnapshot()
        snap.totalOz = dict["totalOz"] as? Double ?? 0
        snap.bricks = dict["bricks"] as? Int ?? 0
        snap.bags = dict["bags"] as? Int ?? 0
        snap.days = dict["days"] as? Double ?? 0
        snap.unitRaw = dict["unitRaw"] as? String ?? "oz"
        if let t = dict["soonestExpiry"] as? Double {
            snap.soonestExpiry = Date(timeIntervalSince1970: t)
        }
        snap.hasData = true
        return snap
    }

    /// Volume formatted in the user's preferred unit (canonical storage is oz).
    var volumeText: String {
        if unitRaw == "mL" {
            return String(format: "%.0f mL", totalOz * 29.5735)
        }
        return String(format: "%.1f oz", totalOz)
    }

    var daysText: String {
        "about \(Int(days.rounded())) day\(Int(days.rounded()) == 1 ? "" : "s")"
    }
}

// MARK: - Timeline

struct StashEntry: TimelineEntry {
    let date: Date
    let snapshot: StashSnapshot
}

struct StashProvider: TimelineProvider {
    func placeholder(in context: Context) -> StashEntry {
        var snap = StashSnapshot()
        snap.totalOz = 251.5
        snap.bricks = 12
        snap.bags = 54
        snap.days = 9
        snap.hasData = true
        return StashEntry(date: .now, snapshot: snap)
    }

    func getSnapshot(in context: Context, completion: @escaping (StashEntry) -> Void) {
        completion(StashEntry(date: .now, snapshot: StashSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StashEntry>) -> Void) {
        // The app reloads timelines whenever data changes; this refresh only
        // keeps relative things (like "days") from going too stale.
        let entry = StashEntry(date: .now, snapshot: StashSnapshot.load())
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Palette (mirrors the app's warm tokens)

private extension Color {
    static let wInk   = Color(red: 0.165, green: 0.133, blue: 0.094)
    static let wInk2  = Color(red: 0.361, green: 0.306, blue: 0.251)
    static let wInk3  = Color(red: 0.549, green: 0.494, blue: 0.439)
    static let wTerra = Color(red: 0.769, green: 0.471, blue: 0.251)
    static let wBgTop = Color(red: 0.992, green: 0.980, blue: 0.961)
    static let wBgBot = Color(red: 0.961, green: 0.949, blue: 0.922)
}

// MARK: - Views

struct StashWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StashEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "snowflake")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.wTerra)
                Text("YOUR STASH")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color.wInk3)
            }
            Spacer(minLength: 0)
            if entry.snapshot.hasData {
                Text(entry.snapshot.volumeText)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(Color.wInk)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(entry.snapshot.daysText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wInk2)
                Text("\(entry.snapshot.bags) bags · \(entry.snapshot.bricks) bricks")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.wInk3)
            } else {
                Text("Open FreezeFlow to start tracking")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wInk2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [.wBgTop, .wBgBot], startPoint: .top, endPoint: .bottom)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "snowflake")
                Text("Stash")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 13))
            if entry.snapshot.hasData {
                Text(entry.snapshot.volumeText)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(entry.snapshot.daysText)
                    .font(.system(size: 12))
            } else {
                Text("Open the app")
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: "snowflake")
                .font(.system(size: 12, weight: .semibold))
            Text(entry.snapshot.hasData ? "\(Int(entry.snapshot.days.rounded()))d" : "—")
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget

struct StashWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StashWidget", provider: StashProvider()) { entry in
            StashWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Stash at a Glance")
        .description("Your frozen milk total and days of supply.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct StashWidgetBundle: WidgetBundle {
    var body: some Widget {
        StashWidget()
    }
}
