import SwiftUI

// MARK: - TUI Dashboard View

struct TUIDashboardView: View {
    private static let workspaceLayoutsStorageKey = "dashboard.workspaceLayouts.v1"
    private static let legacyWorkspaceModulesStorageKey = "dashboard.workspaceModules.v1"

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: UserSettingsStore
    @ObservedObject private var connectionManager = ServiceConnectionManager.shared
    @ObservedObject private var actionItemStore = ActionItemStore.shared
    @ObservedObject private var terminalSessionManager = TerminalSessionManager.shared
    @State private var selectedDetailLevel: Briefing.DetailLevel = .quick
    @State private var selectedSection: Int = 0
    @State private var showChat: Bool = false
    @State private var showLeftPanel: Bool = true
    @State private var upcomingMeetings: [BriefingItem] = []
    @State private var isLoadingMeetings: Bool = false
    @State private var historicalBriefings: [Briefing] = []
    @State private var isLoadingHistory: Bool = false
    @State private var workspaceSetups: [WorkspaceTaskSetup] = []
    @State private var selectedWorkspaceSetupID: UUID?
    @State private var didLoadWorkspaceSetups = false
    @State private var showSetupWizard = false
    @Binding var selectedTab: DashboardTab

    enum DashboardTab: String, CaseIterable, Identifiable {
        case cockpit = "Cockpit"
        case workspace = "Aufgaben"
        case briefing = "Briefing"
        case history = "History"
        case calendar = "Kalender"
        case recordings = "Aufnahmen"
        
        var id: String { rawValue }
    }

    var body: some View {
        mainContent
            .background(Color.tuiBackground)
            .onAppear {
                // Load panel states from user settings
                showChat = settingsStore.settings.showChatPanel
                showLeftPanel = settingsStore.settings.showLeftPanel
                if !didLoadWorkspaceSetups {
                    let store = loadWorkspaceLayoutStore()
                    workspaceSetups = store.setups
                    selectedWorkspaceSetupID = store.selectedSetupID ?? store.setups.first?.id
                    didLoadWorkspaceSetups = true
                    syncSelectedWorkspaceSession()
                }
            }
            .onChange(of: showChat) { _, newValue in
                // Save chat panel state to user settings
                settingsStore.update { settings in
                    settings.showChatPanel = newValue
                }
            }
            .onChange(of: showLeftPanel) { _, newValue in
                // Save left panel state to user settings
                settingsStore.update { settings in
                    settings.showLeftPanel = newValue
                }
            }
            .onChange(of: workspaceSetups) { _, _ in
                saveWorkspaceLayoutStore()
            }
            .onChange(of: selectedWorkspaceSetupID) { _, newValue in
                saveWorkspaceLayoutStore()
                if newValue != nil {
                    syncSelectedWorkspaceSession()
                }
            }
            .modifier(KeyboardHandlersModifier(
                appState: appState,
                selectedDetailLevel: $selectedDetailLevel,
                selectedSection: $selectedSection,
                selectedTab: $selectedTab
            ))
            .modifier(PanelKeysModifier(
                showChat: $showChat,
                showLeftPanel: $showLeftPanel
            ))
            .task {
                await loadUpcomingMeetings()
            }
            .sheet(isPresented: $showSetupWizard) {
                IntegrationSetupWizardView()
            }
    }

    private var mainContent: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.md) {
                // Header (Date & Controls)
                HStack(alignment: .top) {
                    dateHeader
                    Spacer()
                    controlsSection
                        .frame(maxWidth: 320)
                }

                dashboardTabBar

                if selectedTab == .workspace || selectedTab == .cockpit {
                    workspaceSetupTabs
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(Spacing.lg)
            .background(Color.tuiPanel.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.tuiBorder, lineWidth: 1))
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            dashboardTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, 100) // Space for the dock
        }
    }

    private var dashboardTabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    withAnimation(.tuiSnappy) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            if selectedTab == tab {
                                Circle()
                                    .fill(Color.tuiAccent)
                                    .frame(width: 6, height: 6)
                            }

                            Text(tab.rawValue.uppercased())
                                .font(.tuiMonoSmall)
                                .fontWeight(selectedTab == tab ? .bold : .regular)
                        }
                        .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary.opacity(0.6))
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.md)
                        .background(
                            selectedTab == tab
                                ? Color.tuiAccent.opacity(0.1)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Rectangle()
                            .fill(selectedTab == tab ? Color.tuiAccent : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            Spacer()

            switch selectedTab {
            case .cockpit:
                Text("Work + Meeting · \(selectedWorkspaceSetup?.name ?? "Aufgaben")")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            case .workspace:
                Text(selectedWorkspaceSetup?.name ?? "Aufgaben")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            case .briefing:
                if let briefing = appState.currentBriefing {
                    Text("\(briefing.sections.count) sources")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            case .history, .calendar, .recordings:
                EmptyView()
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.tuiPanel.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var dashboardTabContent: some View {
        switch selectedTab {
        case .cockpit:
            CockpitView(
                workspaceSetupID: selectedWorkspaceSetup?.id,
                workspaceName: selectedWorkspaceSetup?.name,
                workspaceTerminalSessionIDs: selectedWorkspaceTerminalSessionIDs,
                onCreateWorkspaceTerminalSession: addWorkspaceTerminalSessionFromCockpit
            )
        case .workspace:
            workspaceModules
        case .briefing:
            briefingOverview
        case .history:
            TUIHistoryView()
        case .calendar:
            MeetingsView(showHeader: true)
        case .recordings:
            RecordingsView()
        }
    }

    private var briefingOverview: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.xl),
                GridItem(.flexible(), spacing: Spacing.xl)
            ], spacing: Spacing.xl) {
                VStack(spacing: Spacing.xl) {
                    BentoCard(title: "Overview", icon: "newspaper.fill") {
                        if appState.currentBriefing != nil {
                            summarySection
                        } else {
                            sourcesOverview
                        }
                    }

                    if appState.currentBriefing != nil {
                        BentoCard(title: "Briefing Details", icon: "list.bullet.rectangle.portrait") {
                            briefingContent
                                .frame(minHeight: 400)
                        }
                    }

                    if actionItemStore.openItemsCount > 0 {
                        BentoCard(title: "Action Items", icon: "checklist") {
                            actionItemsWidget
                        }
                    }
                }

                VStack(spacing: Spacing.xl) {
                    if !upcomingMeetings.isEmpty {
                        BentoCard(title: "Upcoming Meetings", icon: "calendar") {
                            nextMeetingWidget
                        }
                    }

                    if showChat {
                        BentoCard(title: "Assistant", icon: "sparkles") {
                            chatPanel
                                .frame(minHeight: 400)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.md)
        }
    }

    private var workspaceModules: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Text(selectedWorkspaceSetup?.name ?? "Konfiguration")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)

                Spacer()

                Menu {
                    ForEach(availableWorkspacePanels) { panel in
                        Button {
                            addWorkspaceModule(for: panel)
                        } label: {
                            Label(panel.title, systemImage: panel.icon)
                        }
                    }
                } label: {
                    Label("Modul hinzufügen", systemImage: "plus")
                        .font(.tuiMonoTiny)
                }
                .menuStyle(.borderlessButton)
            }

            if currentWorkspaceModules.isEmpty {
                Text("Keine Module im aktuellen Aufgaben-Tab. Über + ein Modul hinzufügen.")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 300), spacing: Spacing.md),
                            GridItem(.flexible(minimum: 300), spacing: Spacing.md)
                        ],
                        spacing: Spacing.md
                    ) {
                        ForEach(currentWorkspaceModules) { module in
                            workspaceModuleCard(module)
                        }
                    }
                    .padding(.bottom, Spacing.md)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.tuiPanel.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
    }

    private var availableWorkspacePanels: [AppState.AppPanel] {
        AppState.AppPanel.allCases.filter { $0 != .dashboard }
    }

    private func workspaceModuleCard(_ module: WorkspaceModuleConfig) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: module.panel.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(module.panel.moduleAccentColor)

                Text(module.displayTitle)
                    .font(.tuiMonoSmall)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                Button("Öffnen") {
                    activateWorkspaceModule(module)
                }
                .font(.tuiMonoTiny)
                .buttonStyle(.tui)

                Button {
                    removeWorkspaceModule(module.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.tuiHover.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
                .help("Modul entfernen")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tuiHover.opacity(0.35))

            Divider()
                .background(Color.tuiBorder)

            workspaceModuleContent(module)
                .frame(minHeight: workspaceModuleMinHeight(for: module.panel))
        }
        .background(Color.tuiPanel.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.tuiBorder.opacity(0.8), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func workspaceModuleContent(_ module: WorkspaceModuleConfig) -> some View {
        switch module.panel {
        case .dashboard:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Nutze das Dashboard als zentralen Arbeitsort.")
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.secondary)
                if appState.currentBriefing != nil {
                    summarySection
                } else {
                    sourcesOverview
                }
            }
        case .openClawChat:
            BriefingChatView()
        case .slack:
            SlackPanelView()
        case .jira:
            JiraPanelView()
        case .mail:
            MailPanelView()
        case .terminals:
            TerminalsPanelView()
        case .settings:
            NavigationStack {
                SettingsView()
            }
        }
    }

    private func workspaceModuleMinHeight(for panel: AppState.AppPanel) -> CGFloat {
        switch panel {
        case .openClawChat: return 320
        case .terminals: return 360
        case .settings: return 340
        case .dashboard: return 280
        case .slack, .jira, .mail: return 320
        }
    }

    private var workspaceSetupTabs: some View {
        HStack(spacing: Spacing.md) {
            Text("AUFGABEN")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(workspaceSetups) { setup in
                        workspaceSetupTabButton(setup)
                    }
                }
            }

            Button {
                addWorkspaceSetup()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Neuer Tab")
                        .font(.tuiMonoTiny)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.tuiHover.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.tuiBorder.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Neuen Aufgaben-Tab anlegen")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.tuiPanel.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.tuiBorder.opacity(0.8), lineWidth: 1)
        )
    }

    private func workspaceSetupTabButton(_ setup: WorkspaceTaskSetup) -> some View {
        let isSelected = selectedWorkspaceSetupID == setup.id

        return Button {
            withAnimation(.tuiSnappy) {
                selectedWorkspaceSetupID = setup.id
            }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    if isSelected {
                        Circle()
                            .fill(Color.tuiAccent)
                            .frame(width: 5, height: 5)
                    }

                    Text(setup.name.uppercased())
                        .font(.tuiMonoTiny)
                        .fontWeight(isSelected ? .bold : .regular)
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.75))

                Rectangle()
                    .fill(isSelected ? Color.tuiAccent : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.tuiAccent.opacity(0.09) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.tuiAccent.opacity(0.22) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Duplizieren") {
                duplicateWorkspaceSetup(setup.id)
            }
            Button("Tab löschen", role: .destructive) {
                removeWorkspaceSetup(setup.id)
            }
            .disabled(workspaceSetups.count <= 1)
        }
    }

    private var selectedWorkspaceSetup: WorkspaceTaskSetup? {
        guard let selectedWorkspaceSetupID else { return workspaceSetups.first }
        return workspaceSetups.first { $0.id == selectedWorkspaceSetupID } ?? workspaceSetups.first
    }

    private var selectedWorkspaceSetupIndex: Int? {
        guard let setup = selectedWorkspaceSetup else { return nil }
        return workspaceSetups.firstIndex(where: { $0.id == setup.id })
    }

    private var currentWorkspaceModules: [WorkspaceModuleConfig] {
        selectedWorkspaceSetup?.modules ?? []
    }

    private var selectedWorkspaceTerminalSessionIDs: [UUID] {
        guard let selectedWorkspaceSetup else { return [] }

        return selectedWorkspaceSetup.modules.compactMap { module in
            guard module.panel == .terminals,
                  let terminalSessionID = module.terminalSessionID,
                  let sessionUUID = UUID(uuidString: terminalSessionID),
                  terminalSessionManager.sessions.contains(where: { $0.id == sessionUUID }) else {
                return nil
            }
            return sessionUUID
        }
    }

    private func addWorkspaceModule(for panel: AppState.AppPanel) {
        guard let setupIndex = selectedWorkspaceSetupIndex else { return }
        var modules = workspaceSetups[setupIndex].modules

        switch panel {
        case .terminals:
            let terminalIndex = modules.filter { $0.panel == .terminals }.count + 1
            let label = terminalLabel(for: terminalIndex)
            let title = "\(workspaceSetups[setupIndex].name) \(label)"
            let sessionID = terminalSessionManager.openSession(title: title)
            modules.append(
                WorkspaceModuleConfig(
                    panelRawValue: panel.rawValue,
                    customTitle: label,
                    terminalSessionID: sessionID.uuidString
                )
            )
        default:
            modules.append(
                WorkspaceModuleConfig(panelRawValue: panel.rawValue)
            )
        }

        workspaceSetups[setupIndex].modules = modules
    }

    private func activateWorkspaceModule(_ module: WorkspaceModuleConfig) {
        if module.panel == .terminals,
           let terminalSessionID = module.terminalSessionID,
           let sessionUUID = UUID(uuidString: terminalSessionID) {
            terminalSessionManager.selectSession(sessionUUID)
        }

        withAnimation(.tuiSnappy) {
            appState.selectedPanel = module.panel
        }
    }

    private func removeWorkspaceModule(_ moduleID: UUID) {
        guard let setupIndex = selectedWorkspaceSetupIndex else { return }
        workspaceSetups[setupIndex].modules.removeAll { $0.id == moduleID }
    }

    private func addWorkspaceSetup() {
        let newSetup = WorkspaceTaskSetup(
            name: nextWorkspaceSetupName(),
            modules: defaultWorkspaceModules
        )
        workspaceSetups.append(newSetup)
        selectedWorkspaceSetupID = newSetup.id
        syncSelectedWorkspaceSession()
    }

    private func duplicateWorkspaceSetup(_ setupID: UUID) {
        guard let setup = workspaceSetups.first(where: { $0.id == setupID }) else { return }
        let duplicateName = "\(setup.name) Kopie"
        let duplicate = WorkspaceTaskSetup(
            name: duplicateName,
            modules: duplicatedWorkspaceModules(from: setup.modules, setupName: duplicateName)
        )
        workspaceSetups.append(duplicate)
        selectedWorkspaceSetupID = duplicate.id
        syncSelectedWorkspaceSession()
    }

    private func removeWorkspaceSetup(_ setupID: UUID) {
        guard workspaceSetups.count > 1 else { return }
        workspaceSetups.removeAll { $0.id == setupID }
        if selectedWorkspaceSetupID == setupID {
            selectedWorkspaceSetupID = workspaceSetups.first?.id
        }
    }

    private func nextWorkspaceSetupName() -> String {
        "Aufgaben \(workspaceSetups.count + 1)"
    }

    private func syncSelectedWorkspaceSession() {
        guard let selectedWorkspaceSetupID else { return }
        guard let sessionID = ensureWorkspacePrimaryTerminalSession(for: selectedWorkspaceSetupID) else { return }
        terminalSessionManager.selectSession(sessionID)
    }

    @discardableResult
    private func ensureWorkspacePrimaryTerminalSession(for setupID: UUID) -> UUID? {
        guard let setupIndex = workspaceSetups.firstIndex(where: { $0.id == setupID }) else { return nil }
        var setup = workspaceSetups[setupIndex]

        if let terminalModuleIndex = setup.modules.firstIndex(where: { $0.panel == .terminals }) {
            if let existingSessionID = setup.modules[terminalModuleIndex].terminalSessionID,
               let sessionUUID = UUID(uuidString: existingSessionID),
               terminalSessionManager.sessions.contains(where: { $0.id == sessionUUID }) {
                return sessionUUID
            }

            let terminalNumber = max(1, setup.modules.filter { $0.panel == .terminals }.count)
            let label = terminalLabel(for: terminalNumber)
            let title = "\(setup.name) \(label)"
            let sessionID = terminalSessionManager.openSession(title: title)
            setup.modules[terminalModuleIndex].terminalSessionID = sessionID.uuidString
            if setup.modules[terminalModuleIndex].customTitle?.isEmpty ?? true {
                setup.modules[terminalModuleIndex].customTitle = label
            }
            workspaceSetups[setupIndex] = setup
            return sessionID
        }

        let label = terminalLabel(for: 1)
        let title = "\(setup.name) \(label)"
        let sessionID = terminalSessionManager.openSession(title: title)
        setup.modules.append(
            WorkspaceModuleConfig(
                panelRawValue: AppState.AppPanel.terminals.rawValue,
                customTitle: label,
                terminalSessionID: sessionID.uuidString
            )
        )
        workspaceSetups[setupIndex] = setup
        return sessionID
    }

    private func addWorkspaceTerminalSessionFromCockpit() {
        guard let setupIndex = selectedWorkspaceSetupIndex else { return }
        let setupName = workspaceSetups[setupIndex].name
        let terminalIndex = workspaceSetups[setupIndex].modules.filter { $0.panel == .terminals }.count + 1
        let label = terminalLabel(for: terminalIndex)
        let title = "\(setupName) \(label)"
        let sessionID = terminalSessionManager.openSession(title: title)

        workspaceSetups[setupIndex].modules.append(
            WorkspaceModuleConfig(
                panelRawValue: AppState.AppPanel.terminals.rawValue,
                customTitle: label,
                terminalSessionID: sessionID.uuidString
            )
        )
        terminalSessionManager.selectSession(sessionID)
        appState.selectedPanel = .terminals
    }

    private func duplicatedWorkspaceModules(from modules: [WorkspaceModuleConfig], setupName: String) -> [WorkspaceModuleConfig] {
        var terminalIndex = 1

        return modules.map { module in
            guard module.panel == .terminals else {
                return WorkspaceModuleConfig(
                    panelRawValue: module.panelRawValue,
                    customTitle: module.customTitle,
                    terminalSessionID: module.terminalSessionID
                )
            }

            let label = module.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? module.customTitle!
                : terminalLabel(for: terminalIndex)
            let sessionTitle = "\(setupName) \(label)"
            let sessionID = terminalSessionManager.openSession(title: sessionTitle)
            terminalIndex += 1

            return WorkspaceModuleConfig(
                panelRawValue: module.panelRawValue,
                customTitle: label,
                terminalSessionID: sessionID.uuidString
            )
        }
    }

    private func terminalLabel(for index: Int) -> String {
        "Terminal \(max(1, index))"
    }

    private func loadWorkspaceLayoutStore() -> WorkspaceLayoutStore {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.workspaceLayoutsStorageKey),
           let decoded = try? JSONDecoder().decode(WorkspaceLayoutStore.self, from: data),
           !decoded.setups.isEmpty {
            return decoded.normalized()
        }

        if let legacyData = defaults.data(forKey: Self.legacyWorkspaceModulesStorageKey),
           let legacyModules = try? JSONDecoder().decode([WorkspaceModuleConfig].self, from: legacyData),
           !legacyModules.isEmpty {
            return WorkspaceLayoutStore(
                selectedSetupID: nil,
                setups: [
                    WorkspaceTaskSetup(
                        name: "Aufgaben 1",
                        modules: legacyModules
                    )
                ]
            ).normalized()
        }

        return WorkspaceLayoutStore(
            selectedSetupID: nil,
            setups: [
                WorkspaceTaskSetup(name: "Aufgaben 1", modules: defaultWorkspaceModules)
            ]
        ).normalized()
    }

    private func saveWorkspaceLayoutStore() {
        guard !workspaceSetups.isEmpty else { return }
        let defaults = UserDefaults.standard
        let store = WorkspaceLayoutStore(
            selectedSetupID: selectedWorkspaceSetupID,
            setups: workspaceSetups
        ).normalized()
        if let data = try? JSONEncoder().encode(store) {
            defaults.set(data, forKey: Self.workspaceLayoutsStorageKey)
        }
    }

    private var defaultWorkspaceModules: [WorkspaceModuleConfig] {
        defaultWorkspacePanels.map { panel in
            WorkspaceModuleConfig(panelRawValue: panel.rawValue)
        }
    }

    private var defaultWorkspacePanels: [AppState.AppPanel] {
        [.openClawChat, .slack, .jira, .mail, .terminals]
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        BriefingChatView()
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Date header with quick stats
            dateHeader
                .padding(Spacing.md)

            Divider()
                .background(Color.tuiBorder)

            // Controls
            controlsSection
                .padding(Spacing.md)

            Divider()
                .background(Color.tuiBorder)

            // Next meeting widget (when no briefing)
            if appState.currentBriefing == nil && !upcomingMeetings.isEmpty {
                nextMeetingWidget
                    .padding(Spacing.md)
                
                Divider()
                    .background(Color.tuiBorder)
            }
            
            // Action Items widget (when there are open items)
            if appState.currentBriefing == nil && actionItemStore.openItemsCount > 0 {
                actionItemsWidget
                    .padding(Spacing.md)
                
                Divider()
                    .background(Color.tuiBorder)
            }

            // Summary or Sources overview
            if appState.currentBriefing != nil {
                summarySection
                    .frame(maxHeight: .infinity)
            } else {
                sourcesOverview
                    .frame(maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Collapsed Left Panel
    
    private var collapsedLeftPanel: some View {
        VStack {
            Button {
                withAnimation(.tuiSnappy) {
                    showLeftPanel = true
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                    Text("⌘S")
                        .font(.system(size: 8, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 50)
                .background(Color.tuiHover.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Panel einblenden (⌘S)")
            
            Spacer()
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, 4)
        .background(Color.tuiPanel.opacity(0.2))
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Date and time
            HStack(alignment: .firstTextBaseline) {
                Text(dateText.uppercased())
                    .font(.tuiMonoSmall)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Spacer()

                Text(timeText)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(Color.primary.opacity(0.5))
            }

            // Quick stats row
            HStack(spacing: Spacing.md) {
                QuickStatBadge(
                    icon: "●",
                    value: "\(connectionManager.connectedSources.count)",
                    label: "sources",
                    color: connectionManager.connectedSources.isEmpty ? .secondary : .green
                )
                
                if !upcomingMeetings.isEmpty {
                    QuickStatBadge(
                        icon: "◐",
                        value: "\(upcomingMeetings.count)",
                        label: "meetings",
                        color: .blue
                    )
                }
                
                if let nextTime = appState.nextScheduledBriefingTime {
                    QuickStatBadge(
                        icon: "⏱",
                        value: nextTime,
                        label: "next",
                        color: .orange
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, d. MMM"
        return formatter.string(from: Date())
    }
    
    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private var controlsSection: some View {
        VStack(spacing: Spacing.sm) {
            // Generate/Play button
            Button {
                if appState.currentBriefing != nil {
                    appState.toggleAudioPlayback()
                } else {
                    Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
                }
            } label: {
                HStack {
                    if appState.isLoadingBriefing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Text(appState.currentBriefing != nil ? (appState.isPlayingAudio ? "⏸" : "▶") : "+")
                            .font(.tuiMonoSmall)
                    }

                    Text(buttonLabel)
                        .font(.tuiMonoSmall)

                    Spacer()

                    KeyBadge(key: appState.currentBriefing != nil ? "SPC" : "⌘R")
                }
            }
            .buttonStyle(.tuiPrimary)
            .disabled(appState.isLoadingBriefing)

            // Detail level picker
            HStack(spacing: 2) {
                ForEach(Briefing.DetailLevel.allCases, id: \.self) { level in
                    DetailLevelButton(
                        level: level,
                        isSelected: selectedDetailLevel == level
                    ) {
                        withAnimation(.tuiSnappy) {
                            selectedDetailLevel = level
                        }
                    }
                }
            }

            // Progress indicator
            if appState.isLoadingBriefing {
                progressIndicator
            }

            // Left panel toggle button
            LeftPanelToggleButton(showLeftPanel: $showLeftPanel)

            // Chat toggle button
            ChatToggleButton(showChat: $showChat)
        }
    }

    private var buttonLabel: String {
        if appState.isLoadingBriefing {
            return "generating..."
        } else if appState.currentBriefing != nil {
            return appState.isPlayingAudio ? "pause" : "play"
        } else {
            return "generate"
        }
    }

    private var progressIndicator: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(appState.generationProgress.displayText.lowercased())
                .font(.tuiMonoTiny)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(height: 2)

                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: geo.size.width * progressValue, height: 2)
                        .animation(.tuiSmooth, value: progressValue)
                }
            }
            .frame(height: 2)
        }
        .padding(.top, Spacing.xs)
    }

    private var progressValue: Double {
        switch appState.generationProgress {
        case .idle, .starting: return 0.1
        case .fetchingSources: return 0.3
        case .processingSources: return 0.5
        case .generatingSummary: return 0.7
        case .finalizing: return 0.9
        case .completed: return 1.0
        case .failed: return 0
        }
    }
    
    // MARK: - Next Meeting Widget
    
    private var nextMeetingWidget: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("NEXT MEETING")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if isLoadingMeetings {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
            
            if let nextMeeting = upcomingMeetings.first {
                NextMeetingCard(meeting: nextMeeting)
            }
        }
    }
    
    // MARK: - Action Items Widget
    
    private var actionItemsWidget: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("ACTION ITEMS")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if actionItemStore.overdueItemsCount > 0 {
                    Text("\(actionItemStore.overdueItemsCount) overdue")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            
            VStack(spacing: Spacing.xs) {
                ForEach(actionItemStore.openItems().prefix(5)) { item in
                    ActionItemCompactRow(item: item)
                }
            }
            
            if actionItemStore.openItemsCount > 5 {
                NavigationLink {
                    ActionItemsView()
                } label: {
                    HStack {
                        Text("view all (\(actionItemStore.openItemsCount))")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("→")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.xs)
            }
        }
    }
    
    // MARK: - Sources Overview (Empty State)
    
    private var sourcesOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("SOURCES")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)
                
                if connectionManager.connectedSources.isEmpty {
                    // No sources connected
                    VStack(spacing: Spacing.sm) {
                        Text("no sources connected")
                            .font(.tuiMonoSmall)
                            .foregroundStyle(.tertiary)
                        
                        Text("press ⌘3 for Slack")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)

                        Button("setup wizard") {
                            showSetupWizard = true
                        }
                        .buttonStyle(.tuiPrimary)
                        .padding(.top, Spacing.xs)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                } else {
                    // Show connected sources
                    VStack(spacing: Spacing.xs) {
                        ForEach(ServiceType.allCases, id: \.rawValue) { serviceType in
                            SourceStatusRow(
                                serviceType: serviceType,
                                status: connectionManager.connectionStatus(for: serviceType)
                            )
                        }
                    }
                }
                
                Divider()
                    .background(Color.tuiBorder)
                    .padding(.vertical, Spacing.xs)
                
                // Tip
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("TIP")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.tertiary)
                    
                    Text("press ⌘R to generate your daily briefing with all connected sources.")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
    }

    private var summarySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("SUMMARY")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                if let briefing = appState.currentBriefing {
                    Text(briefing.summary)
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                } else {
                    Text("no briefing yet. press ⌘R to generate.")
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                ForEach(DashboardTab.allCases) { tab in
                    Button {
                        withAnimation(.tuiSnappy) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 4) {
                                // Tab indicator dot for active tab
                                if selectedTab == tab {
                                    Circle()
                                        .fill(Color.tuiAccent)
                                        .frame(width: 6, height: 6)
                                }
                                
                                Text(tab.rawValue.uppercased())
                                    .font(.tuiMonoSmall)
                                    .fontWeight(selectedTab == tab ? .bold : .regular)
                            }
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary.opacity(0.5))
                            .padding(.vertical, Spacing.sm)
                            .padding(.horizontal, Spacing.md)
                            .background(
                                selectedTab == tab
                                    ? Color.tuiAccent.opacity(0.1)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            Rectangle()
                                .fill(
                                    selectedTab == tab
                                        ? Color.tuiAccent
                                        : Color.clear
                                )
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }

                Spacer()

                if selectedTab == .briefing, let briefing = appState.currentBriefing {
                    Text("\(briefing.sections.count) sources")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .padding(.trailing, Spacing.md)
                }
            }
            .background(Color.tuiPanel.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.secondary.opacity(0.2), Color.primary.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }

            // Content
            switch selectedTab {
            case .cockpit:
                CockpitView(
                    workspaceSetupID: selectedWorkspaceSetup?.id,
                    workspaceName: selectedWorkspaceSetup?.name,
                    workspaceTerminalSessionIDs: selectedWorkspaceTerminalSessionIDs,
                    onCreateWorkspaceTerminalSession: addWorkspaceTerminalSessionFromCockpit
                )
            case .workspace:
                workspaceModules
            case .briefing:
                briefingContent
            case .history:
                TUIHistoryView()
            case .calendar:
                MeetingsView(showHeader: false)
            case .recordings:
                RecordingsView()
            }
        }
    }
    
    private var briefingContent: some View {
        Group {
            if let briefing = appState.currentBriefing {
                if briefing.sections.isEmpty {
                    // Show empty state when briefing exists but has no sections
                    emptySectionsState
                } else {
                    ScrollView {
                        HStack {
                            Spacer()
                            LazyVStack(spacing: 0) {
                                ForEach(Array(briefing.sections.sorted { $0.priority > $1.priority }.enumerated()), id: \.element.id) { index, section in
                                    TUISectionRow(section: section, index: index)
                                }
                            }
                            .frame(maxWidth: 800)
                            Spacer()
                        }
                    }
                }
            } else {
                // Show history and upcoming meetings when no current briefing
                enhancedEmptyState
            }
        }
    }
    
    // MARK: - Enhanced Empty State
    
    private var enhancedEmptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Recent Briefings section
                if !historicalBriefings.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("RECENT BRIEFINGS")
                                .font(.tuiMonoTiny)
                                .fontWeight(.bold)
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            if isLoadingHistory {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        }
                        .padding(Spacing.md)
                        
                        ForEach(historicalBriefings.prefix(5)) { briefing in
                            Button {
                                withAnimation(.tuiSnappy) {
                                    appState.currentBriefing = briefing
                                }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Text("󰧟")
                                        .font(.tuiMonoTiny)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 12)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(briefing.generatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.tuiMonoSmall)
                                            .foregroundStyle(.primary)
                                        
                                        Text("\(briefing.sections.count) sources · \(briefing.detailLevel.displayName.lowercased())")
                                            .font(.tuiMonoTiny)
                                            .foregroundStyle(.tertiary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("→")
                                        .font(.tuiMonoTiny)
                                        .foregroundStyle(.quaternary)
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Rectangle()
                                .fill(Color.tuiBorder.opacity(0.3))
                                .frame(height: 1)
                                .padding(.leading, Spacing.md + 12 + Spacing.sm)
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(height: 1)
                }

                // Upcoming meetings section
                if !upcomingMeetings.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("TODAY'S MEETINGS")
                                .font(.tuiMonoTiny)
                                .fontWeight(.bold)
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            Text("\(upcomingMeetings.count) events")
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.quaternary)
                        }
                        .padding(Spacing.md)
                        
                        ForEach(upcomingMeetings) { meeting in
                            UpcomingMeetingRow(meeting: meeting)
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(height: 1)
                }
                
                // Quick actions
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("QUICK ACTIONS")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.tertiary)
                    
                    QuickActionButton(
                        icon: "+",
                        title: "Generate Briefing",
                        shortcut: "⌘R",
                        action: {
                            Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
                        }
                    )
                    .disabled(appState.isLoadingBriefing)
                    
                    if connectionManager.connectedSources.isEmpty {
                        QuickActionButton(
                            icon: "◎",
                            title: "Connect Sources",
                            shortcut: "⌘3",
                            action: {
                                // This will be handled by the keyboard shortcut
                            }
                        )
                    }
                    
                    if appState.hasCachedBriefing {
                        QuickActionButton(
                            icon: "↺",
                            title: "Load Last Briefing",
                            shortcut: "",
                            action: {
                                appState.loadCachedBriefing()
                            }
                        )
                    }
                }
                .padding(Spacing.md)
                
                Spacer(minLength: Spacing.xl)
                
                // Welcome message
                if connectionManager.connectedSources.isEmpty {
                    welcomeMessage
                        .padding(Spacing.md)
                }
            }
        }
    }
    
    private var welcomeMessage: some View {
        VStack(spacing: Spacing.md) {
            Text("────────────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(Color.secondary.opacity(0.3))

            Text("welcome to daily briefing")
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)

            Text("connect your calendar, email, and other\nservices to get started with your\npersonalized daily overview.")
                .font(.tuiMonoTiny)
                .foregroundStyle(Color.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text("────────────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(Color.primary.opacity(0.3))
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Text("─────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(Color.secondary.opacity(0.3))

            Text("no data")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)

            Text("connect sources and generate a briefing")
                .font(.tuiMonoTiny)
                .foregroundStyle(Color.secondary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySectionsState: some View {
        VStack(spacing: Spacing.md) {
            Text("─────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(Color.primary.opacity(0.3))

            Text("no sections")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)

            Text("briefing generated but no sections available")
                .font(.tuiMonoTiny)
                .foregroundStyle(Color.secondary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Data Loading
    
    private func loadUpcomingMeetings() async {
        // Load History
        isLoadingHistory = true
        historicalBriefings = BriefingCacheService.shared.loadAll()
        isLoadingHistory = false

        guard let calendarSource = connectionManager.googleCalendarSource,
              calendarSource.isAuthenticated else {
            return
        }
        
        isLoadingMeetings = true
        defer { isLoadingMeetings = false }
        
        do {
            let items = try await calendarSource.fetchItems(since: Date())
            // Filter to only today's meetings and limit to 5
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            
            upcomingMeetings = items.filter { item in
                guard let timestamp = item.timestamp else { return false }
                return timestamp >= Date() && timestamp < tomorrow
            }
            .prefix(5)
            .map { $0 }
        } catch {
            // Silently fail - meetings are optional
            print("Failed to load upcoming meetings: \(error)")
        }
    }
}

// MARK: - Quick Stat Badge

struct QuickStatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
                .font(.tuiMonoTiny)
                .foregroundStyle(color == .green ? Color.primary : (color == .blue ? Color.secondary : color))
                .shadow(color: color == .green ? Color.primary.opacity(0.5) : Color.clear, radius: 4)

            Text(value)
                .font(.tuiMonoTiny)
                .fontWeight(.medium)
                .foregroundStyle(Color.secondary.opacity(0.8))
        }
    }
}

// MARK: - Source Status Row

struct SourceStatusRow: View {
    let serviceType: ServiceType
    let status: ConnectionStatus
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Status indicator
            Text(statusIcon)
                .font(.tuiMonoTiny)
                .foregroundStyle(status.color)
                .frame(width: 12)
            
            // Service name
            Text(serviceType.displayName.lowercased())
                .font(.tuiMonoTiny)
                .foregroundStyle(status == .connected ? .secondary : .quaternary)
            
            Spacer()
            
            // Status text
            if status == .connected {
                Text("●")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
    
    private var statusIcon: String {
        switch status {
        case .connected: return "✓"
        case .disconnected: return "○"
        case .connecting: return "◐"
        case .error, .tokenExpired: return "!"
        }
    }
}

// MARK: - Next Meeting Card

struct NextMeetingCard: View {
    let meeting: BriefingItem
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Time
            if let subtitle = meeting.subtitle {
                Text(subtitle)
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
            }
            
            // Title
            Text(meeting.title)
                .font(.tuiMonoSmall)
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            // Meeting link button
            if let meetingLink = meeting.metadata["meetingLink"],
               let url = URL(string: meetingLink) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("→")
                            .font(.tuiMonoTiny)
                        Text("join meeting")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
                .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.tuiHighlight.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
    }
}

// MARK: - Upcoming Meeting Row

struct UpcomingMeetingRow: View {
    let meeting: BriefingItem
    @State private var isHovered = false
    @State private var showMeetingPopup = false

    var body: some View {
        Button {
            showMeetingPopup = true
        } label: {
            HStack(spacing: Spacing.sm) {
                // Time
                Text(timeString)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .frame(width: 50, alignment: .leading)

                // Title
                Text(meeting.title)
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Duration
                if let duration = meeting.metadata["duration"] {
                    Text("[\(duration)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                }

                // Meeting link indicator
                if meeting.metadata["meetingLink"] != nil {
                    Text("📹")
                        .font(.tuiMonoTiny)
                }

                // Arrow — immer leicht sichtbar
                Text("→")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
                    .opacity(isHovered ? 1 : 0.4)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isHovered ? Color.tuiHover : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showMeetingPopup) {
            MeetingDetailPopup(meeting: meeting, isPresented: $showMeetingPopup)
        }
    }

    private var timeString: String {
        guard let timestamp = meeting.timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let shortcut: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Text(icon)
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                
                Text(title.lowercased())
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !shortcut.isEmpty {
                    KeyBadge(key: shortcut)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isHovered ? Color.tuiHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - TUI Section Row

struct TUISectionRow: View {
    let section: BriefingSection
    let index: Int
    @State private var isExpanded = true
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.tuiSnappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(isExpanded ? "▼" : "▶")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Text(section.sourceName.uppercased())
                        .font(.tuiMonoSmall)
                        .fontWeight(.medium)

                    Spacer()

                    Text("[\(section.items.count)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isHovered ? Color.tuiHover : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Items
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(section.items) { item in
                        TUIItemRow(item: item)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }

            // Divider
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - TUI Item Row

struct TUIItemRow: View {
    let item: BriefingItem
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var showMeetingPopup = false
    @ObservedObject private var notesService = MeetingNotesService.shared
    @State private var meetingNotes: String?

    /// Kalender-Events öffnen das Popup; andere Items bleiben wie vorher
    private var isMeetingEvent: Bool {
        item.timestamp != nil || item.metadata["meetingLink"] != nil
    }

    private var hasMeetingOrCalendarLink: Bool {
        !(item.metadata["meetingLink"]?.isEmpty ?? true) || !(item.metadata["calendarLink"]?.isEmpty ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row (clickable)
            Button {
                if isMeetingEvent {
                    showMeetingPopup = true
                } else if hasDetails {
                    withAnimation(.tuiSnappy) {
                        isExpanded.toggle()
                    }
                } else if let url = item.deepLink {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    // Priority indicator
                    Text(priorityChar)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(priorityColor)
                        .frame(width: 12)

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Text(item.title)
                                .font(.tuiMonoSmall)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            // Duration badge
                            if let duration = item.metadata["duration"] {
                                Text("[\(duration)]")
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                            }
                        }

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Meeting link indicator
                    if item.metadata["meetingLink"] != nil {
                        Text("📹")
                            .font(.tuiMonoTiny)
                    }

                    // Meeting notes indicator
                    if meetingNotes?.isEmpty == false || item.metadata["meetingNotes"]?.isEmpty == false {
                        Text("📝")
                            .font(.tuiMonoTiny)
                    }

                    // Indikator: Meeting → Pfeil, sonst Expand/Link wie vorher
                    if isMeetingEvent {
                        Text("→")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                            .opacity(isHovered ? 1 : 0.4)
                    } else if hasDetails {
                        Text(isExpanded ? "▼" : "▶")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                    } else if item.deepLink != nil {
                        Text("→")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                            .opacity(isHovered ? 1 : 0)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.leading, Spacing.lg)
                .padding(.vertical, Spacing.xs)
                .background(isHovered ? Color.tuiHover : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.tuiFast, value: isHovered)
            .contextMenu {
                Button("An OpenClaw senden") {
                    _ = OpenClawChatService.shared.openThread(for: item)
                }
                Button("Im Terminal öffnen") {
                    _ = TerminalSessionManager.shared.openSession(for: item)
                }
            }
            .onAppear {
                loadMeetingNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                loadMeetingNotes()
            }
            .sheet(isPresented: $showMeetingPopup) {
                MeetingDetailPopup(meeting: item, isPresented: $showMeetingPopup)
            }

            // Inline-Details nur für Nicht-Meeting-Items
            if isExpanded && !isMeetingEvent {
                expandedDetails
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
    }

    private var hasDetails: Bool {
        item.body != nil ||
        item.metadata["attendees"] != nil ||
        meetingNotes?.isEmpty == false ||
        item.metadata["location"]?.isEmpty == false
    }

    private func loadMeetingNotes() {
        meetingNotes = notesService.getNotes(for: item) ?? item.metadata["meetingNotes"]
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Attendees
            if let attendees = item.metadata["attendees"], !attendees.isEmpty {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("👥")
                        .font(.tuiMonoTiny)
                    Text(attendees)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Location
            if let location = item.metadata["location"], !location.isEmpty {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("📍")
                        .font(.tuiMonoTiny)
                    Text(location)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Description/Body
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
                    .padding(.top, Spacing.xs)
            }

            // Meeting notes
            if let notes = meetingNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text("📝")
                            .font(.tuiMonoTiny)
                        Text("Meeting-Notizen")
                            .font(.tuiMonoTiny)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    Text(notes)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.xs)
            }

            // Meeting link button
            if let meetingLink = item.metadata["meetingLink"],
               let url = URL(string: meetingLink) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("📹")
                        Text("Meeting beitreten")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
                .padding(.top, Spacing.xs)
            }

            // Deep link to calendar
            if let deepLink = item.deepLink,
               hasMeetingOrCalendarLink {
                Button {
                    NSWorkspace.shared.open(deepLink)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("📅")
                        Text("Im Kalender öffnen")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
            }

            Button {
                _ = OpenClawChatService.shared.openThread(for: item)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("🤖")
                    Text("An OpenClaw senden")
                        .font(.tuiMonoTiny)
                }
            }
            .buttonStyle(.tui)

            Button {
                _ = TerminalSessionManager.shared.openSession(for: item)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("💻")
                    Text("Im Terminal öffnen")
                        .font(.tuiMonoTiny)
                }
            }
            .buttonStyle(.tui)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.leading, Spacing.lg + 12 + Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover.opacity(0.5))
    }

    private var priorityChar: String {
        switch item.priority {
        case .urgent: return "!"
        case .high: return "●"
        case .medium: return "○"
        case .low: return "·"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .primary.opacity(0.6)
        case .low: return .primary.opacity(0.3)
        }
    }
}

// MARK: - Keyboard Handlers Extension

struct KeyboardHandlersModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @Binding var selectedDetailLevel: Briefing.DetailLevel
    @Binding var selectedSection: Int
    @Binding var selectedTab: TUIDashboardView.DashboardTab

    func body(content: Content) -> some View {
        content
            .modifier(RefreshKeysModifier(appState: appState, selectedDetailLevel: $selectedDetailLevel))
            .modifier(AudioKeysModifier(appState: appState))
            .modifier(DetailLevelKeysModifier(selectedDetailLevel: $selectedDetailLevel))
            .modifier(SectionKeysModifier(appState: appState, selectedSection: $selectedSection, selectedTab: $selectedTab))
            .modifier(TabSwitchKeysModifier(selectedTab: $selectedTab))
    }
}

struct RefreshKeysModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @Binding var selectedDetailLevel: Briefing.DetailLevel

    func body(content: Content) -> some View {
        content
            .onKeyPress("r", modifiers: .command) {
                Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
                return .handled
            }
            .onKeyPress("n", modifiers: .command) {
                Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
                return .handled
            }
    }
}

struct PanelKeysModifier: ViewModifier {
    @Binding var showChat: Bool
    @Binding var showLeftPanel: Bool

    func body(content: Content) -> some View {
        content
            .onKeyPress("c", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    showChat.toggle()
                }
                return .handled
            }
            .onKeyPress("s", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    showLeftPanel.toggle()
                }
                return .handled
            }
    }
}

struct AudioKeysModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .onKeyPress(.space) {
                if appState.currentBriefing != nil {
                    appState.toggleAudioPlayback()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(".", modifiers: .command) {
                if appState.isPlayingAudio {
                    appState.stopAudioPlayback()
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - Bento Card & Modules

struct BentoCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tuiAccent)
                
                Text(title.uppercased())
                    .font(.tuiMonoSmall)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tuiHover.opacity(0.3))
            
            Divider()
                .background(Color.tuiBorder)
            
            // Content
            content
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.tuiPanel.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
    }
}

private struct WorkspaceLayoutStore: Codable, Equatable {
    var selectedSetupID: UUID?
    var setups: [WorkspaceTaskSetup]

    func normalized() -> WorkspaceLayoutStore {
        let safeSetups = setups.isEmpty
            ? [WorkspaceTaskSetup(name: "Aufgaben 1", modules: [])]
            : setups

        let selected = safeSetups.contains(where: { $0.id == selectedSetupID })
            ? selectedSetupID
            : safeSetups.first?.id

        return WorkspaceLayoutStore(selectedSetupID: selected, setups: safeSetups)
    }
}

private struct WorkspaceTaskSetup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var modules: [WorkspaceModuleConfig]
}

private struct WorkspaceModuleConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let panelRawValue: String
    var customTitle: String? = nil
    var terminalSessionID: String? = nil

    var panel: AppState.AppPanel {
        AppState.AppPanel(rawValue: panelRawValue) ?? .dashboard
    }

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }
        return panel.title
    }
}

struct DetailLevelKeysModifier: ViewModifier {
    @Binding var selectedDetailLevel: Briefing.DetailLevel

    func body(content: Content) -> some View {
        content
            .onKeyPress("q", modifiers: [.command, .shift]) {
                withAnimation(.tuiSnappy) {
                    selectedDetailLevel = .quick
                }
                return .handled
            }
            .onKeyPress("d", modifiers: [.command, .shift]) {
                withAnimation(.tuiSnappy) {
                    selectedDetailLevel = .detailed
                }
                return .handled
            }
    }
}

struct SectionKeysModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @Binding var selectedSection: Int
    @Binding var selectedTab: TUIDashboardView.DashboardTab

    func body(content: Content) -> some View {
        content
            .onKeyPress("[", modifiers: .command) {
                guard selectedTab == .briefing else { return .ignored }
                if selectedSection > 0 {
                    withAnimation(.tuiSnappy) {
                        selectedSection -= 1
                    }
                }
                return .handled
            }
            .onKeyPress("]", modifiers: .command) {
                guard selectedTab == .briefing else { return .ignored }
                if let briefing = appState.currentBriefing, selectedSection < briefing.sections.count - 1 {
                    withAnimation(.tuiSnappy) {
                        selectedSection += 1
                    }
                }
                return .handled
            }
    }
}

// MARK: - Detail Level Button

struct DetailLevelButton: View {
    let level: Briefing.DetailLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSelected {
                Button(action: action) {
                    Text(level == .quick ? "quick" : "detailed")
                        .font(.tuiMonoTiny)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tuiPrimary)
            } else {
                Button(action: action) {
                    Text(level == .quick ? "quick" : "detailed")
                        .font(.tuiMonoTiny)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tui)
            }
        }
    }
}

// MARK: - Chat Toggle Button

struct ChatToggleButton: View {
    @Binding var showChat: Bool

    var body: some View {
        Button {
            withAnimation(.tuiSnappy) {
                showChat.toggle()
            }
        } label: {
            HStack {
                Text(showChat ? ">" : "<")
                    .font(.tuiMonoSmall)
                    .foregroundStyle(showChat ? Color.primary : Color.secondary)

                Text("chat")
                    .font(.tuiMonoSmall)
                    .foregroundStyle(showChat ? Color.primary : Color.secondary)

                Spacer()

                KeyBadge(key: "\u{2318}C")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(showChat ? Color.primary.opacity(0.15) : Color.tuiPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(showChat ? Color.primary.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Left Panel Toggle Button

struct LeftPanelToggleButton: View {
    @Binding var showLeftPanel: Bool

    var body: some View {
        Button {
            withAnimation(.tuiSnappy) {
                showLeftPanel.toggle()
            }
        } label: {
            HStack {
                Text(showLeftPanel ? "<" : ">")
                    .font(.tuiMonoSmall)
                    .foregroundStyle(showLeftPanel ? Color.primary : Color.secondary)

                Text("panel")
                    .font(.tuiMonoSmall)
                    .foregroundStyle(showLeftPanel ? Color.primary : Color.secondary)

                Spacer()

                KeyBadge(key: "\u{2318}S")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(showLeftPanel ? Color.primary.opacity(0.15) : Color.tuiPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(showLeftPanel ? Color.primary.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy Dashboard View (for compatibility)

struct DashboardView: View {
    @State private var selectedTab: TUIDashboardView.DashboardTab = .workspace

    var body: some View {
        TUIDashboardView(selectedTab: $selectedTab)
    }
}
