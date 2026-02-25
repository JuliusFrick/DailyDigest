import SwiftUI

enum PanelLaunchButtonStyle {
    case dock
    case module
}

struct PanelLaunchButton: View {
    @Binding var selectedPanel: AppState.AppPanel
    let panel: AppState.AppPanel
    let style: PanelLaunchButtonStyle
    var customTitle: String? = nil
    var actionOverride: (() -> Void)? = nil

    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @State private var isHovered = false
    @State private var showSetupWizard = false

    var body: some View {
        Button {
            handleTap()
        } label: {
            switch style {
            case .dock:
                dockLabel
            case .module:
                moduleLabel
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showSetupWizard) {
            IntegrationSetupWizardView()
        }
    }

    private var isSelected: Bool {
        selectedPanel == panel
    }

    private var requiredServices: [ServiceType]? {
        switch panel {
        case .slack:
            return [.slack]
        case .jira:
            return [.jira]
        case .mail:
            return [.gmail, .appleMail]
        default:
            return nil
        }
    }

    private var isSetupRequired: Bool {
        guard let requiredServices else { return false }
        return !requiredServices.contains(where: { connectionManager.isConnected($0) })
    }

    private var helpText: String {
        if isSetupRequired {
            switch panel {
            case .slack:
                return "Slack ist nicht verbunden. Setup-Wizard öffnen."
            case .jira:
                return "Jira ist nicht verbunden. Setup-Wizard öffnen."
            case .mail:
                return "Mail ist nicht verbunden. Setup-Wizard öffnen."
            default:
                return panel.title
            }
        }
        return panel.title
    }

    private func handleTap() {
        if let actionOverride {
            actionOverride()
            return
        }

        if isSetupRequired {
            showSetupWizard = true
            return
        }

        withAnimation(.tuiSnappy) {
            selectedPanel = panel
        }
    }

    private var dockLabel: some View {
        VStack(spacing: 4) {
            Image(systemName: panel.icon)
                .font(.system(size: 16))

            Circle()
                .fill(isSelected ? Color.tuiAccent : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .background(isSelected ? Color.tuiAccent.opacity(0.15) : Color.clear)
        .foregroundStyle(isSelected ? Color.tuiAccent : Color.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.tuiAccent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSetupRequired {
                disconnectedBadge
            }
        }
    }

    private var moduleLabel: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: panel.icon)
                .font(.system(size: 24))
                .foregroundStyle(isHovered || isSelected ? panel.moduleAccentColor : .secondary)

            Text(customTitle ?? panel.title)
                .font(.tuiMonoSmall)
                .fontWeight(.medium)
                .foregroundStyle(isHovered || isSelected ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(isHovered || isSelected ? Color.tuiHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovered || isSelected ? Color.tuiBorder : Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSetupRequired {
                disconnectedBadge
            }
        }
    }

    private var disconnectedBadge: some View {
        ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: 14, height: 14)

            Text("!")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
        }
        .offset(x: 4, y: -4)
    }
}

extension AppState.AppPanel {
    var moduleAccentColor: Color {
        switch self {
        case .dashboard: return .purple
        case .openClawChat: return .mint
        case .slack: return .blue
        case .jira: return .indigo
        case .mail: return .yellow
        case .terminals: return .green
        case .settings: return .orange
        }
    }
}
