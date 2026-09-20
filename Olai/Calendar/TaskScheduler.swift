import EventKit
import Foundation

/// Scheduling goes through EventKit, as the spec requires: a scheduled task is an
/// `EKReminder` with an alarm, so the reminder — and its notification — lives in the
/// system's Reminders, not in a notification scheduler of our own.
@MainActor
enum TaskScheduler {
    enum Failure: LocalizedError {
        case accessDenied
        case noRemindersList
        case notFound

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Olai needs access to Reminders to schedule a task. Grant it in System Settings › Privacy & Security › Reminders."
            case .noRemindersList:
                "There is no default Reminders list to add to. Open Reminders and create one."
            case .notFound:
                "That reminder is no longer in Reminders."
            }
        }
    }

    private static let store = EKEventStore()

    static func requestAccess() async throws {
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw Failure.accessDenied }
    }

    /// Creates or updates the reminder for a task, returning its identifier to store on
    /// the block. The alarm is what notifies at the due time.
    @discardableResult
    static func schedule(title: String, due: Date, existingID: String?) async throws -> String {
        try await requestAccess()

        let reminder: EKReminder
        if let existingID, let found = store.calendarItem(withIdentifier: existingID) as? EKReminder {
            reminder = found
            reminder.alarms?.forEach(reminder.removeAlarm)
        } else {
            reminder = EKReminder(eventStore: store)
            guard let calendar = store.defaultCalendarForNewReminders() else {
                throw Failure.noRemindersList
            }
            reminder.calendar = calendar
        }

        reminder.title = title.isEmpty ? "Olai task" : title
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: due
        )
        reminder.addAlarm(EKAlarm(absoluteDate: due))

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    static func remove(id: String) async throws {
        try await requestAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw Failure.notFound
        }
        try store.remove(reminder, commit: true)
    }

    /// How a due date reads on the task's chip in the editor.
    static func chipText(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
