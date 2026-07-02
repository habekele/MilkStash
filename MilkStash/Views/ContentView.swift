// ContentView.swift

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Query private var settings: [AppSettings]

    private var appSettings: AppSettings {
        if let s = settings.first { return s }
        return AppSettings()
    }

    @Environment(\.modelContext) private var context
    @Binding var selectedTab: Int
    @StateObject private var tabBar = TabBarVisibility()

    var body: some View {
        ZStack {
            // All five tabs stay mounted (opacity-toggled), so hidden ones must
            // be explicitly removed from the accessibility tree or VoiceOver
            // can walk into invisible screens.
            HomeView(onShowHistory: { selectedTab = 3 })
                .opacity(selectedTab == 0 ? 1 : 0)
                .accessibilityHidden(selectedTab != 0)
            InventoryView()
                .opacity(selectedTab == 1 ? 1 : 0)
                .accessibilityHidden(selectedTab != 1)
            GoalView(isActive: selectedTab == 2)
                .opacity(selectedTab == 2 ? 1 : 0)
                .accessibilityHidden(selectedTab != 2)
            HistoryView()
                .opacity(selectedTab == 3 ? 1 : 0)
                .accessibilityHidden(selectedTab != 3)
            SettingsView(onEditGoal: { selectedTab = 2 })
                .opacity(selectedTab == 4 ? 1 : 0)
                .accessibilityHidden(selectedTab != 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FFTabBar(selectedTab: $selectedTab)
        }
        .environmentObject(tabBar)
        .onChange(of: selectedTab) { _, _ in tabBar.reveal() }
        .onReceive(NotificationCenter.default.publisher(for: ExpiryNotifications.openUseMilk)) { _ in
            // Expiry notification tapped: land on Home, where the Use Milk
            // sheet opens (HomeView listens for the same signal).
            selectedTab = 0
        }
        .task {
            if settings.isEmpty {
                let s = AppSettings()
                context.insert(s)
                try? context.save()
            } else if settings.count > 1 {
                // CloudKit first-launch on two devices can each seed a row.
                // Keep the oldest goal (deterministic on every device) so all
                // `settings.first` reads agree.
                if let keep = settings.min(by: { $0.goalStartDate < $1.goalStartDate }) {
                    for extra in settings where extra !== keep {
                        context.delete(extra)
                    }
                    try? context.save()
                }
            }
        }
    }
}

// MARK: - Scroll-aware Tab Bar

/// Drives the floating tab bar's hide/show as the user scrolls, matching the
/// Instagram-style "collapse on scroll down, reveal on scroll up" behavior.
final class TabBarVisibility: ObservableObject {
    @Published private(set) var hidden = false

    private var lastOffset: CGFloat = 0
    private var accumulated: CGFloat = 0

    /// Distance the user must drag in one direction before the bar reacts —
    /// keeps it steady against tiny scroll jitters.
    private let threshold: CGFloat = 28
    /// Within this distance of the top the bar is always shown.
    private let topRevealZone: CGFloat = 36

    /// Always bring the bar back (e.g. when switching tabs).
    func reveal() {
        accumulated = 0
        setHidden(false)
    }

    /// `offsetY` is the normalized vertical scroll offset (0 at the very top,
    /// growing as the user scrolls down).
    func onScroll(offsetY: CGFloat) {
        let delta = offsetY - lastOffset
        lastOffset = offsetY

        if offsetY < topRevealZone {
            accumulated = 0
            setHidden(false)
            return
        }

        // Accumulate movement in one direction; a direction flip resets it.
        if (delta > 0) == (accumulated >= 0) {
            accumulated += delta
        } else {
            accumulated = delta
        }

        if accumulated > threshold {            // scrolled down -> hide
            accumulated = 0
            setHidden(true)
        } else if accumulated < -threshold {    // scrolled up -> show
            accumulated = 0
            setHidden(false)
        }
    }

    private func setHidden(_ value: Bool) {
        guard hidden != value else { return }
        hidden = value
    }
}

@available(iOS 18.0, *)
private struct TabBarScrollTracker: ViewModifier {
    @EnvironmentObject private var tabBar: TabBarVisibility
    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            tabBar.onScroll(offsetY: newValue)
        }
    }
}

extension View {
    /// Attach to a `ScrollView` so it drives the floating tab bar's
    /// hide-on-scroll behavior. No-op below iOS 18.
    @ViewBuilder
    func tracksTabBar() -> some View {
        if #available(iOS 18.0, *) {
            modifier(TabBarScrollTracker())
        } else {
            self
        }
    }
}

// MARK: - Custom Tab Bar

struct FFTabBar: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var tabBar: TabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let items: [(icon: String, selectedIcon: String, label: String)] = [
        ("house",       "house.fill",       "Today"),
        ("shippingbox", "shippingbox.fill", "Stash"),
        ("heart",       "heart.fill",       "Journey"),
        ("clock",       "clock.fill",       "History"),
        ("gearshape",   "gearshape.fill",   "Settings"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<items.count, id: \.self) { idx in
                let selected = selectedTab == idx
                Button {
                    if reduceMotion {
                        selectedTab = idx
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = idx
                        }
                    }
                } label: {
                    Image(systemName: selected ? items[idx].selectedIcon : items[idx].icon)
                        .font(.ff(size: 21, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.ffTerra : Color.ffInk4)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle()
                                .fill(Color.ffTerraSoft)
                                .opacity(selected ? 1 : 0)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[idx].label)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            ZStack {
                // Solid surface when Reduce Transparency is on; blur otherwise.
                Color.ffSurface.opacity(reduceTransparency ? 1 : 0.92)
                if !reduceTransparency {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(Color.ffLine, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        .offset(y: tabBar.hidden && !reduceMotion ? 130 : 0)
        .opacity(tabBar.hidden ? 0 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: tabBar.hidden)
        .padding(.bottom, 6)
    }
}

// MARK: - Design System: Typography

extension Font {
    /// Dynamic-Type-scaling replacement for `.system(size:weight:design:)`.
    /// A fixed `.system(size:)` font ignores the user's text-size setting;
    /// this scales the base size with the body style's metrics instead.
    static func ff(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
        return .system(size: scaled, weight: weight, design: design)
    }
}

// MARK: - Design System: Layout Tokens

/// 8pt-based spacing scale (with 4pt half-steps). Use these everywhere instead of
/// raw magic numbers so vertical/horizontal rhythm stays consistent.
enum Space {
    static let xs: CGFloat = 4
    static let s:  CGFloat = 8
    static let m:  CGFloat = 12
    static let l:  CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Standard horizontal screen padding. Matches iOS system default feel.
    static let screenPad: CGFloat = 20
    /// Extra breathing room above the floating tab bar (the bar itself
    /// already reserves space via safeAreaInset).
    static let tabBarClearance: CGFloat = 8
}

/// Four-tier corner radius scale. Small inline tiles, buttons/rows, cards, and hero.
enum Radius {
    static let xs: CGFloat = 6   // chart bars, mini dots
    static let s:  CGFloat = 8   // calendar blocks, tiny tiles
    static let m:  CGFloat = 12  // icon tiles, small menu backdrops
    static let l:  CGFloat = 14  // buttons, rows, search bars, inner cards
    static let xl: CGFloat = 20  // standard card
    static let hero: CGFloat = 24 // hero card only
}

/// Square icon-tile used in list rows (At a Glance, milestones, etc.).
enum IconTile {
    static let size: CGFloat = 40
    static let radius: CGFloat = Radius.m
    static let iconPt: CGFloat = 16
}

// MARK: - Design System: Color Tokens

extension Color {

    // Background
    static let ffBg = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.133, blue: 0.094, alpha: 1)  // #2A2218
            : UIColor(red: 0.961, green: 0.949, blue: 0.922, alpha: 1)  // #F5F2EB
    })

    // Surface (card)
    static let ffSurface = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.200, green: 0.173, blue: 0.133, alpha: 1)  // #332C22
            : UIColor(red: 0.992, green: 0.980, blue: 0.961, alpha: 1)  // #FDFAF5
    })

    // Surface 2 (nested card)
    static let ffSurface2 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.239, green: 0.204, blue: 0.157, alpha: 1)  // #3D3428
            : UIColor(red: 0.969, green: 0.953, blue: 0.925, alpha: 1)  // #F7F3EC
    })

    // Divider / border line
    static let ffLine = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.290, green: 0.251, blue: 0.208, alpha: 1)  // #4A4035
            : UIColor(red: 0.878, green: 0.851, blue: 0.800, alpha: 1)  // #E0D9CC
    })

    // Primary text
    static let ffInk = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.961, green: 0.941, blue: 0.910, alpha: 1)  // #F5F0E8
            : UIColor(red: 0.165, green: 0.133, blue: 0.094, alpha: 1)  // #2A2218
    })

    // Secondary text
    static let ffInk2 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.784, green: 0.722, blue: 0.604, alpha: 1)  // #C8B89A
            : UIColor(red: 0.361, green: 0.306, blue: 0.251, alpha: 1)  // #5C4E40
    })

    // Tertiary text
    static let ffInk3 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.549, green: 0.494, blue: 0.416, alpha: 1)  // #8C7E6A
            : UIColor(red: 0.549, green: 0.494, blue: 0.439, alpha: 1)  // #8C7E70
    })

    // Quaternary / icons
    static let ffInk4 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.831, green: 0.753, blue: 0.659, alpha: 1)  // #D4C0A8
            : UIColor(red: 0.690, green: 0.627, blue: 0.565, alpha: 1)  // #B0A090
    })

    // Terracotta (primary accent)
    static let ffTerra = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.831, green: 0.533, blue: 0.353, alpha: 1)  // #D4885A
            : UIColor(red: 0.769, green: 0.471, blue: 0.251, alpha: 1)  // #C47840
    })

    // Terracotta soft background
    static let ffTerraSoft = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.290, green: 0.180, blue: 0.102, alpha: 1)  // #4A2E1A
            : UIColor(red: 0.961, green: 0.918, blue: 0.878, alpha: 1)  // #F5EAE0
    })

    // Sage green
    static let ffSage = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.510, green: 0.745, blue: 0.565, alpha: 1)  // brighter in dark
            : UIColor(red: 0.420, green: 0.620, blue: 0.471, alpha: 1)  // #6B9E78
    })

    // Sage soft background
    static let ffSageSoft = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.157, green: 0.255, blue: 0.180, alpha: 1)  // dark sage tint
            : UIColor(red: 0.910, green: 0.953, blue: 0.918, alpha: 1)  // #E8F3EA
    })

    // Butter / warning
    static let ffButter = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.878, green: 0.749, blue: 0.404, alpha: 1)  // brighter in dark
            : UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1)  // #C9A84C
    })

    // Butter soft background
    static let ffButterSoft = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.251, green: 0.212, blue: 0.102, alpha: 1)  // dark butter tint
            : UIColor(red: 0.961, green: 0.929, blue: 0.855, alpha: 1)  // #F5EDDA
    })

    // Legacy aliases kept for compatibility with other files
    static let milkIndigo  = Color.ffTerra
    static let milkCoral   = Color.ffTerra
    static let milkSage    = Color.ffSage
    static let milkWarn    = Color.ffButter
    static let milkDanger  = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.45, blue: 0.45, alpha: 1)
            : UIColor(red: 0.75, green: 0.22, blue: 0.22, alpha: 1)
    })
    static let milkCream   = Color.ffBg
    static let cardBg      = Color.ffSurface
    static let milkBlue    = Color.ffTerra
    static let milkTeal    = Color.ffTerra
    static let milkGreen   = Color.ffSage
}

// MARK: - Shared Design Components

/// Pressed-state feedback (subtle scale + dim) so chips and CTAs respond to
/// touch like native controls. Rows and icon buttons keep `.plain`.
/// Falls back to a plain dim when Reduce Motion is on.
struct FFPressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FFPressableBody(configuration: configuration)
    }

    private struct FFPressableBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: Configuration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8),
                           value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == FFPressable {
    static var ffPressable: FFPressable { FFPressable() }
}

/// Standard card container
struct FFCard<Content: View>: View {
    let content: () -> Content
    var padding: CGFloat = Space.l

    init(padding: CGFloat = Space.l, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(Color.ffSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ffLine, lineWidth: 0.5))
    }
}

/// Encouragement strip with leaf icon and sage tint
struct FFEncouragement: View {
    let message: String
    var icon: String = "leaf.fill"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.ff(size: 14, weight: .semibold))
                .foregroundStyle(Color.ffSage)
            Text(message)
                .font(.ff(size: 14, weight: .regular))
                .italic()
                .foregroundStyle(Color.ffInk2)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ffSageSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.ffSage.opacity(0.25), lineWidth: 0.5))
    }
}

/// Thin divider in ffLine color
struct FFDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ffLine)
            .frame(height: 0.5)
    }
}

/// Standard section eyebrow label
struct FFEyebrow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.ff(size: 11, weight: .medium))
            .tracking(2)
            .foregroundStyle(Color.ffInk3)
    }
}

// MARK: - Shared Date Formatters

extension DateFormatter {
    static let calMonth: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    static let calDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
}

// MARK: - Keyboard Helper

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

#Preview {
    ContentView(selectedTab: .constant(0))
        .modelContainer(PreviewData.container())
}
