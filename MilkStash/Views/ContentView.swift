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
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            InventoryView()
                .tabItem { Label("Inventory", systemImage: "list.bullet.rectangle.fill") }
                .tag(1)

            GoalView()
                .tabItem { Label("Journey", systemImage: "heart.circle.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Color.milkIndigo)
        .task {
            if settings.isEmpty {
                let s = AppSettings()
                context.insert(s)
                try? context.save()
            }
        }
    }
}

// MARK: - Design System

extension Color {
    // Each color adapts: richer/darker in light mode, brighter/lighter in dark mode.
    // UIColor(dynamicProvider:) gives us full control over both appearances.

    // Primary — indigo
    // Light: deep indigo  |  Dark: soft periwinkle (much easier to read)
    static let milkIndigo = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.62, blue: 1.00, alpha: 1)   // bright periwinkle
            : UIColor(red: 0.22, green: 0.25, blue: 0.58, alpha: 1)   // deep indigo
    })

    // Accent — coral
    // Light: deep coral (4.7:1 on white)  |  Dark: soft peach
    static let milkCoral = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.68, blue: 0.62, alpha: 1)   // soft peach
            : UIColor(red: 0.76, green: 0.30, blue: 0.24, alpha: 1)   // deep coral
    })

    // Positive — sage green
    // Light: deep sage (4.8:1 on white)  |  Dark: mint (pops on dark)
    static let milkSage = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.90, blue: 0.68, alpha: 1)   // bright mint
            : UIColor(red: 0.22, green: 0.50, blue: 0.35, alpha: 1)   // deep sage
    })

    // Warning — amber
    // Light: dark amber (4.7:1 on white)  |  Dark: soft yellow
    static let milkWarn = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.85, blue: 0.40, alpha: 1)   // soft yellow
            : UIColor(red: 0.60, green: 0.42, blue: 0.00, alpha: 1)   // dark amber
    })

    // Danger — rose red
    // Light: deep red (5.5:1 on white)  |  Dark: bright salmon
    static let milkDanger = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.45, blue: 0.45, alpha: 1)   // bright salmon
            : UIColor(red: 0.75, green: 0.22, blue: 0.22, alpha: 1)   // deep red
    })

    // Cream background tint
    static let milkCream = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1)   // dark blue-tinted bg
            : UIColor(red: 0.99, green: 0.97, blue: 0.94, alpha: 1)   // warm cream
    })

    // Card background — system handles this automatically
    static let cardBg = Color(.secondarySystemGroupedBackground)

    // Aliases
    static let milkBlue  = Color.milkIndigo
    static let milkTeal  = Color.milkCoral
    static let milkGreen = Color.milkSage
}


// MARK: - Keyboard Helpers

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
