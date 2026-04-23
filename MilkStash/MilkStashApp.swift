// MilkStashApp.swift

import SwiftUI
import SwiftData

@main
struct MilkStashApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([MilkBag.self, AppSettings.self])
        // Try CloudKit-backed store first, fall back to local-only, then in-memory.
        // Each tier handles the case where the previous one fails (e.g. entitlement
        // missing in debug builds, or a store that can't be migrated in the field).
        if let c = try? ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) {
            container = c
        } else if let c = try? ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, cloudKitDatabase: .none)) {
            container = c
        } else {
            // Last resort: in-memory store so the app launches rather than crashes.
            // Data entered in this session will not persist.
            container = try! ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
    }

    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    var body: some Scene {
        WindowGroup {
            SplashGate()
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(container)
    }

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

// MARK: - Splash Screen

struct SplashGate: View {
    @State private var showSplash = true
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            ContentView(selectedTab: $selectedTab)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.4)) {
                showSplash = false
            }
        }
    }
}

struct SplashView: View {
    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "snowflake")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                Text("FreezeFlow")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(textOpacity)
            }
        }
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeIn(duration: 0.4)) {
                textOpacity = 1.0
            }
        }
    }
}
