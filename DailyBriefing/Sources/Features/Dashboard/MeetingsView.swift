import SwiftUI

// MARK: - Meetings View

struct MeetingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var connectionManager = ServiceConnectionManager.shared
    
    // State for calendar navigation and data
    @State private var selectedDate: Date = Date()
    @State private var fetchedMeetings: [BriefingItem] = []
    @State private var isLoading: Bool = false
    
    private var hasCalendarConnected: Bool {
        connectionManager.isConnected(.googleCalendar) ||
        connectionManager.googleCalendarSource?.isAuthenticated == true
    }
    
    var showHeader: Bool = true
    
    @State private var showConnectPopup: Bool = true
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                if showHeader {
                    HStack {
                        Text("KALENDER")
                            .font(.tuiMonoTiny)
                            .fontWeight(.bold)
                            .foregroundStyle(.tertiary)
                        
                        Spacer()
                        
                        if hasCalendarConnected {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Text("\(fetchedMeetings.count) events this week")
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                            }
                        } else {
                            Text("nicht verbunden")
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color.tuiBackground)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }
                }
                
                // Always show calendar grid
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Week Calendar Grid
                        WeekCalendarView(
                            meetings: fetchedMeetings,
                            selectedDate: $selectedDate
                        )
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                        
                        // Detailed List for the week
                        if !fetchedMeetings.isEmpty {
                            calendarMeetingsHeader
                            
                            ForEach(fetchedMeetings) { item in
                                MeetingRow(item: item)
                                
                                Rectangle()
                                    .fill(Color.tuiBorder)
                                    .frame(height: 1)
                            }
                        } else if !isLoading {
                            VStack(spacing: Spacing.sm) {
                                Text(hasCalendarConnected ? "Keine Termine diese Woche" : "Keine Termine")
                                    .font(.tuiMonoSmall)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(Spacing.xl)
                        }
                    }
                }
            }
            .background(Color.tuiBackground)
            
            // Floating popup when not connected
            if !hasCalendarConnected && showConnectPopup {
                CalendarConnectPopup(showPopup: $showConnectPopup, onOpenSettings: {
                    appState.selectedPanel = .settings
                })
            }
        }
        .task(id: hasCalendarConnected) {
            if hasCalendarConnected {
                await loadMeetings()
                showConnectPopup = false
            }
        }
        .task(id: selectedDate) {
            if hasCalendarConnected {
                await loadMeetings()
            }
        }
    }
    
    private var calendarMeetingsHeader: some View {
        HStack {
            Text("TERMINE")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.quaternary)
            
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiHover.opacity(0.3))
    }
    
    private func loadMeetings() async {
        guard let calendarSource = connectionManager.googleCalendarSource,
              calendarSource.isAuthenticated else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Calculate week range for selectedDate
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        
        do {
            fetchedMeetings = try await calendarSource.fetchEvents(from: startOfWeek, to: endOfWeek)
        } catch {
            print("Failed to load meetings: \(error)")
        }
    }
}

// MARK: - Calendar Config Banner

struct CalendarConfigBanner: View {
    @ObservedObject private var connectionManager = ServiceConnectionManager.shared
    @State private var isConnecting = false
    @State private var connectionError: String?
    
    private var isConfigured: Bool {
        if !Secrets.googleClientId.isEmpty { return true }
        let clientId = UserDefaults.standard.string(forKey: "google_client_id") ?? ""
        return !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("────────────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(.quaternary)
            
            Text("KALENDER NICHT KONFIGURIERT")
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            Text("Verbinde deinen Kalender, um deine\nTermine hier zu sehen.")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            
            if let error = connectionError {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.orange)
                }
            }
            
            if !isConfigured {
                Text("Bitte zuerst Google-Konfiguration in Einstellungen > Quellen einrichten.")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                guard isConfigured else { return }
                connectionError = nil
                isConnecting = true
                Task {
                    do {
                        try await connectionManager.connect(.googleCalendar)
                    } catch {
                        connectionError = error.localizedDescription
                    }
                    isConnecting = false
                }
            } label: {
                Group {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        HStack(spacing: Spacing.xs) {
                            Text("+")
                            Text("Kalender verbinden")
                                .font(.tuiMonoSmall)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isConnecting || !isConfigured)
            
            Text("────────────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Calendar Connect Popup

struct CalendarConnectPopup: View {
    @ObservedObject private var connectionManager = ServiceConnectionManager.shared
    @Binding var showPopup: Bool
    var onOpenSettings: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var isConnecting = false
    @State private var connectionError: String?
    
    private var isConfigured: Bool {
        if !Secrets.googleClientId.isEmpty { return true }
        let clientId = UserDefaults.standard.string(forKey: "google_client_id") ?? ""
        return !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: Spacing.md) {
                // Header with close button
                HStack {
                    Text("KALENDER VERBINDEN")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            showPopup = false
                        }
                    } label: {
                        Text("✕")
                            .font(.tuiMonoSmall)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("Verbinde deinen Kalender, um Termine zu sehen und Meeting-Zusammenfassungen zu erstellen.")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                
                if let error = connectionError {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if !isConfigured {
                    VStack(spacing: Spacing.xs) {
                        Text("Bitte richte zuerst die Google-Konfiguration ein.")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.orange)
                        if let onOpenSettings {
                            Button("Zu Einstellungen > Quellen") {
                                showPopup = false
                                onOpenSettings()
                            }
                            .font(.tuiMonoTiny)
                            .buttonStyle(.link)
                        }
                    }
                }
                
                HStack(spacing: Spacing.sm) {
                    Button {
                        guard isConfigured else { return }
                        connectionError = nil
                        isConnecting = true
                        Task {
                            do {
                                try await connectionManager.connect(.googleCalendar)
                                showPopup = false
                            } catch {
                                connectionError = error.localizedDescription
                            }
                            isConnecting = false
                        }
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            HStack(spacing: Spacing.xs) {
                                Text("+")
                                Text("Verbinden")
                                    .font(.tuiMonoSmall)
                            }
                        }
                    }
                    .buttonStyle(.tuiPrimary)
                    .disabled(isConnecting || !isConfigured)
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            showPopup = false
                        }
                    } label: {
                        Text("Später")
                            .font(.tuiMonoSmall)
                    }
                    .buttonStyle(.tui)
                }
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            .padding(Spacing.lg)
        }
        .frame(maxWidth: 320)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.95))
        ))
    }
}

// MARK: - Week Calendar View

struct WeekCalendarView: View {
    let meetings: [BriefingItem]
    @Binding var selectedDate: Date
    
    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 40
    private let startHour = 7  // 07:00
    private let endHour = 20   // 20:00
    
    private var weekDays: [Date] {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }
    
    private var weekRange: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with navigation
            HStack {
                Text("ÜBERSICHT")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.quaternary)
                
                Spacer()
                
                HStack(spacing: Spacing.sm) {
                    Button {
                        withAnimation(.tuiSnappy) {
                            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
                        }
                    } label: {
                        Text("◀")
                            .font(.tuiMonoTiny)
                    }
                    .buttonStyle(.plain)
                    
                    Text(weekRange)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 120)
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
                        }
                    } label: {
                        Text("▶")
                            .font(.tuiMonoTiny)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            selectedDate = Date()
                        }
                    } label: {
                        Text("Heute")
                            .font(.tuiMonoTiny)
                    }
                    .buttonStyle(.tui)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tuiHover.opacity(0.3))
            
            // Day headers
            HStack(spacing: 0) {
                // Time column spacer
                Text("")
                    .frame(width: 40)
                
                ForEach(weekDays, id: \.self) { day in
                    DayHeaderCell(date: day, isToday: calendar.isDateInToday(day))
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.tuiBackground)
            
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
            
            // Calendar grid
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hour lines and labels
                    VStack(spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            HStack(spacing: 0) {
                                Text(String(format: "%02d", hour))
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                                    .frame(width: 40)
                                
                                Rectangle()
                                    .fill(Color.tuiBorder.opacity(0.5))
                                    .frame(height: 1)
                            }
                            .frame(height: hourHeight)
                        }
                    }
                    
                    // Events overlay
                    HStack(spacing: 0) {
                        // Time column spacer
                        Color.clear
                            .frame(width: 40)
                        
                        ForEach(weekDays, id: \.self) { day in
                            DayEventsColumn(
                                date: day,
                                meetings: meetingsForDay(day),
                                hourHeight: hourHeight,
                                startHour: startHour,
                                endHour: endHour
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                }
            }
            .frame(height: CGFloat(endHour - startHour) * hourHeight + 20)
        }
    }
    
    private func meetingsForDay(_ day: Date) -> [BriefingItem] {
        meetings.filter { item in
            guard let timestamp = item.timestamp else { return false }
            return calendar.isDate(timestamp, inSameDayAs: day)
        }
    }
}

// MARK: - Day Header Cell

struct DayHeaderCell: View {
    let date: Date
    let isToday: Bool
    
    private let calendar = Calendar.current
    
    private var dayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(dayName)
                .font(.tuiMonoTiny)
                .foregroundStyle(isToday ? .primary : .quaternary)
            
            Text(dayNumber)
                .font(.tuiMonoSmall)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? .primary : .secondary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(isToday ? Color.tuiAccent.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Day Events Column

struct DayEventsColumn: View {
    let date: Date
    let meetings: [BriefingItem]
    let hourHeight: CGFloat
    let startHour: Int
    let endHour: Int
    
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background for today
            if calendar.isDateInToday(date) {
                Rectangle()
                    .fill(Color.tuiAccent.opacity(0.05))
            }
            
            // Current time indicator
            if calendar.isDateInToday(date) {
                CurrentTimeIndicator(hourHeight: hourHeight, startHour: startHour)
            }
            
            // Events
            ForEach(meetings) { meeting in
                if let timestamp = meeting.timestamp {
                    EventBlock(
                        meeting: meeting,
                        hourHeight: hourHeight,
                        startHour: startHour,
                        topOffset: offsetForTime(timestamp)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(endHour - startHour) * hourHeight)
    }
    
    private func offsetForTime(_ date: Date) -> CGFloat {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let hoursFromStart = CGFloat(hour - startHour) + CGFloat(minute) / 60.0
        return max(0, hoursFromStart * hourHeight)
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    let hourHeight: CGFloat
    let startHour: Int
    
    private let calendar = Calendar.current
    
    private var offset: CGFloat {
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let hoursFromStart = CGFloat(hour - startHour) + CGFloat(minute) / 60.0
        return max(0, hoursFromStart * hourHeight)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .offset(y: offset - 3)
    }
}

// MARK: - Event Block

struct EventBlock: View {
    let meeting: BriefingItem
    let hourHeight: CGFloat
    let startHour: Int
    let topOffset: CGFloat
    
    @State private var isHovered = false
    @State private var showEventPopup = false

    private var duration: CGFloat {
        // Try to parse duration from metadata, default to 1 hour
        if let durationStr = meeting.metadata["duration"] {
            // Parse "1h 30m" or "30m" format
            var totalMinutes: CGFloat = 0
            let components = durationStr.lowercased().components(separatedBy: " ")
            for component in components {
                if component.contains("h") {
                    if let hours = Double(component.replacingOccurrences(of: "h", with: "")) {
                        totalMinutes += CGFloat(hours) * 60
                    }
                } else if component.contains("m") {
                    if let minutes = Double(component.replacingOccurrences(of: "m", with: "")) {
                        totalMinutes += CGFloat(minutes)
                    }
                }
            }
            return max(30, totalMinutes) // Minimum 30 minutes for visibility
        }
        return 60 // Default 1 hour
    }
    
    private var height: CGFloat {
        (duration / 60.0) * hourHeight
    }
    
    private var eventColor: Color {
        if meeting.metadata["meetingLink"] != nil {
            return Color.blue.opacity(0.6)
        }
        return Color.tuiAccent.opacity(0.6)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(meeting.title)
                .font(.tuiMonoTiny)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(height > 30 ? 2 : 1)
            
            if height > 40, let subtitle = meeting.subtitle {
                Text(subtitle)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(eventColor)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isHovered ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .offset(y: topOffset)
        .padding(.horizontal, 1)
        .onHover { isHovered = $0 }
        .help(meeting.title + (meeting.subtitle.map { " - \($0)" } ?? ""))
        .onTapGesture {
            showEventPopup = true
        }
        .sheet(isPresented: $showEventPopup) {
            MeetingDetailPopup(meeting: meeting, isPresented: $showEventPopup)
        }
    }
}

// MARK: - Meeting Row

struct MeetingRow: View {
    let item: BriefingItem
    @State private var isHovered = false
    @State private var showMeetingPopup = false
    
    private var minutesUntilStart: Int {
        guard let timestamp = item.timestamp else { return 999 }
        return Int(timestamp.timeIntervalSinceNow / 60)
    }

    var body: some View {
        Button {
            showMeetingPopup = true
        } label: {
            HStack(spacing: Spacing.sm) {
                // Urgency indicator
                MeetingUrgencyIndicator(minutesUntilStart: minutesUntilStart)
                    .frame(width: 40, alignment: .leading)
                
                // Time
                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle = item.subtitle {
                        Text(subtitle.components(separatedBy: " - ").first ?? subtitle)
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 60, alignment: .leading)

                // Title
                Text(item.title)
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Duration
                if let duration = item.metadata["duration"] {
                    Text("[\(duration)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                }

                // Link indicator
                if item.metadata["meetingLink"] != nil {
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
            .urgencyBorder(minutesUntilStart: minutesUntilStart)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showMeetingPopup) {
            MeetingDetailPopup(meeting: item, isPresented: $showMeetingPopup)
        }
    }
}


