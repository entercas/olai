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
    private static let createdKey = "tasks.reminderIDs"

    /// The reminders Olai made. A task block carries the identifier of its reminder, and
    /// a page arrives from other devices over CloudKit, so that identifier is not
    /// something to hand to EventKit unchecked -- it names any item in the user's
    /// Reminders. Olai only updates or deletes the ones it created itself.
    ///
    /// Per device on purpose: an EventKit identifier is not portable between them, so a
    /// reminder scheduled on another Mac was never reusable here anyway.
    private static var created: Set<String> {
        get { Set(AppEnvironment.defaults.stringArray(forKey: createdKey) ?? []) }
        set { AppEnvironment.defaults.set(Array(newValue), forKey: createdKey) }
    }

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
        if
            let existingID,
            created.contains(existingID),
            let found = store.calendarItem(withIdentifier: existingID) as? EKReminder
        {
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
        created.insert(reminder.calendarItemIdentifier)
        return reminder.calendarItemIdentifier
    }

    static func remove(id: String) async throws {
        try await requestAccess()
        guard
            created.contains(id),
            let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else {
            throw Failure.notFound
        }
        try store.remove(reminder, commit: true)
        created.remove(id)
    }

    /// How a due date reads on the task's chip in the editor.
    static func chipText(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
