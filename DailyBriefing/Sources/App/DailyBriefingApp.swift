import SwiftUI
import SwiftData

@main
struct DailyBriefingApp: App {
    let container: ModelContainer

    @StateObject private var appState = AppState()

    init() {
        do {
            let schema = Schema([
                UserSettings.self,
                SourceConfiguration.self,
                CachedBriefing.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(container)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 420, height: 680)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .modelContainer(container)
        }
    }
}
