// ContentView.swift

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var settings: [AppSettings]

    private var appSettings: AppSettings {
        if let s = settings.first { return s }
        return AppSettings()
    }

    @Environment(\.modelContext) private var context
    @Binding var selectedTab: Int

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                HomeView()    .opacity(selectedTab == 0 ? 1 : 0)
                InventoryView().opacity(selectedTab == 1 ? 1 : 0)
                GoalView()    .opacity(selectedTab == 2 ? 1 : 0)
                SettingsView().opacity(selectedTab == 3 ? 1 : 0)
            }

            FFTabBar(selectedTab: $selectedTab)
                .padding(.bottom, 8)
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            if settings.isEmpty {
                let s = AppSettings()
                context.insert(s)
                try? context.save()
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct FFTabBar: View {
    @Binding var selectedTab: Int

    private let items: [(icon: String, label: String)] = [
        ("house.fill",      "Today"),
        ("shippingbox.fill","Stash"),
        ("heart.fill",      "Journey"),
        ("gearshape.fill",  "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { idx in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = idx
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[idx].icon)
                            .font(.system(size: 20, weight: selectedTab == idx ? .semibold : .regular))
                            .foregroundStyle(selectedTab == idx ? Color.ffTerra : Color.ffInk4)
                            .scaleEffect(selectedTab == idx ? 1.08 : 1.0)
                            .shadow(color: selectedTab == idx ? Color.ffTerra.opacity(0.45) : .clear,
                                    radius: 6, x: 0, y: 2)

                        Text(items[idx].label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selectedTab == idx ? Color.ffTerra : Color.ffInk4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.ffLine, lineWidth: 0.5))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
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
    /// Safe clearance above the floating tab bar.
    static let tabBarClearance: CGFloat = 104
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ffSage)
            Text(message)
                .font(.system(size: 14, weight: .regular))
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
            .font(.system(size: 11, weight: .medium))
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
