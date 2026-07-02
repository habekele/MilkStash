// MilkStashApp.swift

import SwiftUI
import SwiftData

@main
struct MilkStashApp: App {
    let container: ModelContainer
    let isScreenshotMode: Bool
    @Environment(\.scenePhase) private var scenePhase

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

        if !screenshotMode {
            NotificationRouter.shared.attach()
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
            // Fonts scale with Dynamic Type (Font.ff); cap the extremes so
            // fixed-frame layouts (arcs, tiles, tab bar) stay usable.
            .dynamicTypeSize(.xSmall ... .accessibility2)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding is the moment stash state stops changing — refresh
            // everything the system shows while the app is closed.
            guard phase == .background, !isScreenshotMode else { return }
            let bags = (try? container.mainContext.fetch(FetchDescriptor<MilkBag>())) ?? []
            let settings = (try? container.mainContext.fetch(FetchDescriptor<AppSettings>()))?.first
            ExpiryNotifications.refresh(bags: bags)
            StashWidgetBridge.publish(bags: bags, settings: settings)
        }
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
