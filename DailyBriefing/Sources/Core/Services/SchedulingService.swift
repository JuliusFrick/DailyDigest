import Foundation
import Combine
import AppKit

/// Service responsible for scheduling automatic briefing generation
/// Handles daily scheduled briefings and notifications
@MainActor
final class SchedulingService: ObservableObject {

    // MARK: - Singleton

    static let shared = SchedulingService()

    // MARK: - Published Properties

    @Published private(set) var isScheduled = false
    @Published private(set) var nextScheduledTime: Date?
    @Published var scheduledTime: Date = defaultScheduledTime {
        didSet {
            if isScheduled {
                reschedule()
            }
        }
    }

    // MARK: - Private Properties

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let briefingService = BriefingGenerationService.shared
    private let notificationService = NotificationService.shared

    // MARK: - Constants

    private static var defaultScheduledTime: Date {
        var components = DateComponents()
        components.hour = 7
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Callbacks

    var onBriefingGenerated: ((Briefing) -> Void)?
    var onBriefingFailed: ((Error) -> Void)?

    // MARK: - Initialization

    private init() {
        loadScheduledTime()
        observeSystemWake()
    }

    // MARK: - Public API

    /// Enable automatic daily scheduling
    func enableScheduling() {
        guard !isScheduled else { return }

        isScheduled = true
        scheduleNextBriefing()
        saveSchedulingState()
    }

    /// Disable automatic daily scheduling
    func disableScheduling() {
        isScheduled = false
        timer?.invalidate()
        timer = nil
        nextScheduledTime = nil
        cancelPendingNotifications()
        saveSchedulingState()
    }

    /// Update the scheduled time
    func updateScheduledTime(_ time: Date) {
        scheduledTime = time
        saveScheduledTime()
        if isScheduled {
            reschedule()
        }
    }

    /// Manually trigger a briefing generation
    func triggerBriefingNow() async {
        await generateBriefing()
    }

    /// Request notification permissions
    func requestNotificationPermission() async -> Bool {
        await notificationService.requestPermission()
    }

    // MARK: - Private Methods

    private func loadScheduledTime() {
        if let savedTime = UserDefaults.standard.object(forKey: "scheduledBriefingTime") as? Date {
            scheduledTime = savedTime
        }

        isScheduled = UserDefaults.standard.bool(forKey: "schedulingEnabled")

        if isScheduled {
            scheduleNextBriefing()
        }
    }

    private func saveScheduledTime() {
        UserDefaults.standard.set(scheduledTime, forKey: "scheduledBriefingTime")
    }

    private func saveSchedulingState() {
        UserDefaults.standard.set(isScheduled, forKey: "schedulingEnabled")
    }

    private func observeSystemWake() {
        // Observe when Mac wakes from sleep
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleSystemWake()
                }
            }
            .store(in: &cancellables)
    }

    private func handleSystemWake() {
        guard isScheduled else { return }

        // Check if we missed the scheduled time while asleep
        if let nextTime = nextScheduledTime, Date() > nextTime {
            // We missed the scheduled time, generate now
            Task {
                await generateBriefing()
            }
        } else {
            // Reschedule to ensure timer is accurate
            reschedule()
        }
    }

    private func reschedule() {
        timer?.invalidate()
        scheduleNextBriefing()
    }

    private func scheduleNextBriefing() {
        // Calculate the next occurrence of the scheduled time
        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
        components.second = 0

        var nextDate = calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        ) ?? now

        // If the calculated time is in the past (shouldn't happen, but safety check)
        if nextDate <= now {
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
        }

        nextScheduledTime = nextDate

        // Schedule the timer
        let timeInterval = nextDate.timeIntervalSince(now)
        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.generateBriefing()
                // Schedule the next day's briefing
                self.scheduleNextBriefing()
            }
        }

        // Also schedule a notification
        scheduleNotification(for: nextDate)
    }

    private func scheduleNotification(for date: Date) {
        // Delegate to NotificationService for morning reminder scheduling
        notificationService.scheduleMorningReminder(at: date)
    }

    private func cancelPendingNotifications() {
        notificationService.cancelMorningReminder()
    }

    private func generateBriefing() async {
        do {
            let briefing = try await briefingService.generateBriefing()
            onBriefingGenerated?(briefing)

            // Show notification that briefing is ready
            await sendBriefingReadyNotification()
        } catch {
            onBriefingFailed?(error)
        }
    }

    private func sendBriefingReadyNotification() async {
        // Delegate to NotificationService for briefing ready notification
        await notificationService.sendBriefingReadyNotification()
    }
}

// MARK: - Date Formatting Helpers

extension SchedulingService {
    /// Format the next scheduled time for display
    var formattedNextTime: String? {
        guard let nextTime = nextScheduledTime else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")

        if Calendar.current.isDateInToday(nextTime) {
            formatter.dateFormat = "'Heute um' HH:mm"
        } else if Calendar.current.isDateInTomorrow(nextTime) {
            formatter.dateFormat = "'Morgen um' HH:mm"
        } else {
            formatter.dateFormat = "EEEE 'um' HH:mm"
        }

        return formatter.string(from: nextTime)
    }

    /// Format the scheduled time for display
    var formattedScheduledTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: scheduledTime)
    }
}
