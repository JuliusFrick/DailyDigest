import SwiftUI
import Combine

/// Central app state management
@MainActor
final class AppState: ObservableObject {

    // MARK: - Navigation

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard
        case sources
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "Briefing"
            case .sources: return "Quellen"
            case .settings: return "Einstellungen"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: return "sun.horizon.fill"
            case .sources: return "square.stack.3d.up.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @Published var selectedTab: Tab = .dashboard
    @Published var showOnboarding: Bool = false

    // MARK: - Briefing State

    @Published var isLoadingBriefing: Bool = false
    @Published var isPlayingAudio: Bool = false
    @Published var currentBriefing: Briefing?

    // MARK: - Source Management

    @Published var connectedSources: [any BriefingSource] = []
    @Published var availableSources: [any BriefingSource.Type] = []

    // MARK: - Initialization

    init() {
        checkOnboardingStatus()
    }

    private func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        showOnboarding = !hasCompletedOnboarding
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showOnboarding = false
    }

    // MARK: - Briefing Actions

    func refreshBriefing() async {
        isLoadingBriefing = true
        defer { isLoadingBriefing = false }

        // TODO: Implement briefing generation
        try? await Task.sleep(for: .seconds(2))
    }

    func toggleAudioPlayback() {
        isPlayingAudio.toggle()
        // TODO: Implement audio playback
    }
}
