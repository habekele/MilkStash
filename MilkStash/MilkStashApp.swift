// MilkStashApp.swift

import SwiftUI
import SwiftData

@main
struct MilkStashApp: App {
    let container: ModelContainer
    let isScreenshotMode: Bool

    init() {
        let schema = Schema([MilkBag.self, AppSettings.self, UsageEvent.self])
        let args = ProcessInfo.processInfo.arguments
        let screenshotMode = args.contains("-ScreenshotMode")
        self.isScreenshotMode = screenshotMode

        if screenshotMode {
            let c = try! ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            ScreenshotData.populate(c.mainContext)
            container = c
        } else if let c = try? ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) {
            container = c
        } else if let c = try? ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, cloudKitDatabase: .none)) {
            container = c
        } else {
            container = try! ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
    }

    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    var body: some Scene {
        WindowGroup {
            Group {
                if isScreenshotMode {
                    ScreenshotHost()
                } else {
                    SplashGate()
                }
            }
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

// MARK: - Launch fade-in

struct SplashGate: View {
    @State private var selectedTab: Int = 0
    @State private var appOpacity: Double = 0

    var body: some View {
        ContentView(selectedTab: $selectedTab)
            .opacity(appOpacity)
            .task {
                withAnimation(.easeOut(duration: 0.35)) {
                    appOpacity = 1.0
                }
            }
    }
}
