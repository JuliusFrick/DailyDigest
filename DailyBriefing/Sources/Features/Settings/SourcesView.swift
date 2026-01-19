import SwiftUI

// MARK: - TUI Sources View

struct TUISourcesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @State private var selectedService: ServiceType?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Connected sources
                TUISourceSection(title: "CONNECTED", count: connectionManager.connectedSources.count) {
                    if connectionManager.connectedSources.isEmpty {
                        TUIEmptyRow(text: "no sources connected")
                    } else {
                        ForEach(connectionManager.connectedSources, id: \.id) { source in
                            TUIConnectedSourceRow(
                                source: source,
                                connectionManager: connectionManager,
                                onConfigure: openService
                            )
                        }
                    }
                }

                // Available sources
                TUISourceSection(title: "AVAILABLE", count: ServiceType.allCases.filter { !connectionManager.isConnected($0) }.count) {
                    ForEach(ServiceType.allCases.filter { !connectionManager.isConnected($0) }) { serviceType in
                        TUIAvailableSourceRow(
                            serviceType: serviceType,
                            connectionManager: connectionManager,
                            onConfigure: { openService(serviceType) }
                        )
                    }
                }
            }
        }
        .sheet(item: $selectedService) { serviceType in
            NavigationStack {
                ServiceDetailView(serviceType: serviceType)
                    .navigationTitle(serviceType.displayName)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fertig") {
                                selectedService = nil
                            }
                        }
                    }
            }
            .frame(minWidth: 450, minHeight: 400)
        }
    }

    private func openService(_ serviceType: ServiceType) {
        connectionManager.ensureSource(serviceType)
        selectedService = serviceType
    }
}

struct TUISourceSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                Text("[\(count)]")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)

                Spacer()
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)

            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)

            // Content
            content()

            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }
}

struct TUIEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.tuiMonoSmall)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
    }
}

struct TUIConnectedSourceRow: View {
    let source: any BriefingSource
    @ObservedObject var connectionManager: ServiceConnectionManager
    let onConfigure: (ServiceType) -> Void
    @State private var isHovered = false

    private var serviceType: ServiceType? {
        ServiceType(rawValue: type(of: source).sourceId)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(source.isAuthenticated ? "●" : "○")
                .font(.tuiMonoTiny)
                .foregroundStyle(source.isAuthenticated ? .green : .orange)

            Text(type(of: source).displayName.lowercased())
                .font(.tuiMonoSmall)

            Spacer()

            if let serviceType = serviceType {
                Button {
                    Task {
                        await connectionManager.disconnect(serviceType)
                    }
                } label: {
                    Text("disconnect")
                        .font(.tuiMonoTiny)
                }
                .buttonStyle(.tuiGhost)
                .opacity(isHovered ? 1 : 0.5)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(isHovered ? Color.tuiHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if let serviceType = serviceType {
                onConfigure(serviceType)
            }
        }
        .animation(.tuiFast, value: isHovered)
    }
}

struct TUIAvailableSourceRow: View {
    let serviceType: ServiceType
    @ObservedObject var connectionManager: ServiceConnectionManager
    let onConfigure: () -> Void
    @State private var isConnecting = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text("○")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(serviceType.displayName.lowercased())
                    .font(.tuiMonoSmall)

                Text(serviceType.description.lowercased())
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                if serviceType.requiresOAuth {
                    onConfigure()
                } else {
                    connect()
                }
            } label: {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 50)
                } else {
                    Text("connect")
                        .font(.tuiMonoTiny)
                }
            }
            .buttonStyle(.tui)
            .disabled(isConnecting)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(isHovered ? Color.tuiHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onConfigure()
        }
        .animation(.tuiFast, value: isHovered)
    }

    private func connect() {
        isConnecting = true
        Task {
            do {
                try await connectionManager.connect(serviceType)
            } catch {
                print("Connection error: \(error)")
            }
            isConnecting = false
        }
    }
}

// MARK: - Legacy Sources View (for Settings navigation)

struct SourcesView: View {
    var body: some View {
        TUISourcesView()
    }
}

// MARK: - Connected Source Row

struct ConnectedSourceRow: View {
    let source: any BriefingSource
    @ObservedObject var connectionManager: ServiceConnectionManager
    @State private var showingConfig = false

    private var serviceType: ServiceType? {
        ServiceType(rawValue: type(of: source).sourceId)
    }

    var body: some View {
        Button {
            showingConfig = true
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type(of: source).displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Text(source.isAuthenticated ? "Verbunden" : "Nicht verbunden")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                RoundedRectangle(cornerRadius: 1)
                    .fill(source.isAuthenticated ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .sheet(isPresented: $showingConfig) {
            if let serviceType = serviceType {
                NavigationStack {
                    ServiceDetailView(serviceType: serviceType)
                        .navigationTitle(serviceType.displayName)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fertig") {
                                    showingConfig = false
                                }
                            }
                            ToolbarItem(placement: .destructiveAction) {
                                Button("Trennen", role: .destructive) {
                                    Task {
                                        await connectionManager.disconnect(serviceType)
                                        showingConfig = false
                                    }
                                }
                            }
                        }
                }
                .frame(minWidth: 400, minHeight: 350)
            }
        }
    }
}

// MARK: - Available Source Row

struct AvailableSourceRowNew: View {
    let serviceType: ServiceType
    @ObservedObject var connectionManager: ServiceConnectionManager
    @State private var isConnecting = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(serviceType.displayName)
                    .font(.subheadline)
                Text(serviceType.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                connect()
            } label: {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Text("+")
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.subtle)
            .disabled(isConnecting)
        }
    }

    private func connect() {
        isConnecting = true
        Task {
            do {
                try await connectionManager.connect(serviceType)
            } catch {
                print("Connection error: \(error)")
            }
            isConnecting = false
        }
    }
}

// MARK: - Add Source Sheet

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var connectionManager: ServiceConnectionManager

    var body: some View {
        NavigationStack {
            List {
                Section("Cloud") {
                    ForEach([ServiceType.googleCalendar, .gmail, .slack, .jira]) { serviceType in
                        if !connectionManager.isConnected(serviceType) {
                            AvailableSourceRowNew(
                                serviceType: serviceType,
                                connectionManager: connectionManager
                            )
                        }
                    }
                }

                Section("Apple") {
                    ForEach([ServiceType.appleMail, .appleReminders]) { serviceType in
                        if !connectionManager.isConnected(serviceType) {
                            AvailableSourceRowNew(
                                serviceType: serviceType,
                                connectionManager: connectionManager
                            )
                        }
                    }
                }

                Section("Soon") {
                    ComingSoonRow(name: "WhatsApp", icon: "message.fill", color: .green)
                    ComingSoonRow(name: "iMessage", icon: "bubble.left.fill", color: .blue)
                    ComingSoonRow(name: "Notion", icon: "doc.text", color: .primary)
                    ComingSoonRow(name: "Linear", icon: "line.3.horizontal", color: .purple)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Quelle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 350, minHeight: 400)
    }
}

struct ComingSoonRow: View {
    let name: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Spacer()

            Text("Soon")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
    }
}
