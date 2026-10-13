import EventKit
import AppKit

/// Cada categoría vive como un calendario propio ("TaskOut · Hogar") con su color,
/// así en el iPhone las tareas se ven con el mismo color sin hacer nada.
@MainActor
final class CalendarSync {
    private let store = EKEventStore()
    private(set) var authorized = false

    var isDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    func requestAccess() async -> Bool {
        do { authorized = try await store.requestFullAccessToEvents() } catch { authorized = false }
        return authorized
    }

    func refreshStatus() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private func calendar(for category: TaskCategory?) -> EKCalendar? {
        let title = "TaskOut · " + (category?.name ?? "Sin categoría")
        let color = NSColor(hex: category?.colorHex ?? "8E8E93")
        if let c = store.calendars(for: .event).first(where: { $0.title == title && $0.allowsContentModifications }) {
            if c.cgColor != color.cgColor { c.cgColor = color.cgColor; try? store.saveCalendar(c, commit: true) }
            return c
        }
        let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
        guard let source else { return nil }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = title
        c.source = source
        c.cgColor = color.cgColor
        do { try store.saveCalendar(c, commit: true) } catch { return nil }
        return c
    }

    /// Crea o actualiza el evento de la tarea. Devuelve el identificador del evento.
    func upsert(_ task: TaskItem, category: TaskCategory?) -> String? {
        guard authorized, let cal = calendar(for: category) else { return task.eventID }
        let ev = task.eventID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        ev.title = task.title
        ev.notes = task.notes.isEmpty ? nil : task.notes
        ev.startDate = task.start
        ev.endDate = max(task.end, task.start.addingTimeInterval(300))
        ev.calendar = cal
        do { try store.save(ev, span: .thisEvent, commit: true) } catch { return task.eventID }
        return ev.eventIdentifier
    }

    func remove(eventID: String?) {
        guard authorized, let eventID, let ev = store.event(withIdentifier: eventID) else { return }
        try? store.remove(ev, span: .thisEvent, commit: true)
    }
}
