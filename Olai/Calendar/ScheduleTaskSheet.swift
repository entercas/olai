import SwiftUI

/// Picks a due date for the task holding the caret, and writes the resulting reminder's
/// identifier back onto the block.
struct ScheduleTaskSheet: View {
    let taskText: String
    let existingID: String?
    let onScheduled: (String, String) -> Void
    let onCleared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var due: Date = .now.addingTimeInterval(3600)
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingID == nil ? "Schedule Task" : "Change Reminder")
                .font(.headline)

            Text(taskText.isEmpty ? "Untitled task" : taskText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            DatePicker("Due", selection: $due)
                .datePickerStyle(.compact)
                .labelsHidden()

            Text("Added to Reminders with an alarm, which is what notifies you.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if existingID != nil {
                    Button("Remove", role: .destructive) { clear() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(existingID == nil ? "Schedule" : "Update") { schedule() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(isWorking)
        }
        .padding(20)
        .frame(minWidth: 340)
    }

    private func schedule() {
        isWorking = true
        error = nil
        Task {
            do {
                let id = try await TaskScheduler.schedule(
                    title: taskText,
                    due: due,
                    existingID: existingID
                )
                onScheduled(id, TaskScheduler.chipText(for: due))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func clear() {
        isWorking = true
        error = nil
        Task {
            if let existingID {
                // A reminder the user already deleted by hand should not block clearing
                // the block's own schedule.
                try? await TaskScheduler.remove(id: existingID)
            }
            onCleared()
            dismiss()
            isWorking = false
        }
    }
}
