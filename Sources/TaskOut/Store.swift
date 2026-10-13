import SwiftUI
import AppKit

@MainActor
final class Store: ObservableObject {
    @Published var tasks: [TaskItem] = [] { didSet { save() } }
    @Published var categories: [TaskCategory] = Palette.defaults { didSet { save() } }
    @Published var draft = Draft()
    @Published var selectedID: UUID?
    @Published var peekID: UUID?
    @Published var completingID: UUID?
    @Published var lastDoneID: UUID?
    @Published var showDone = false
    @Published var notesFocused = false
    @Published var focusTick = 0
    @Published var calendarOn: Bool { didSet { UserDefaults.standard.set(calendarOn, forKey: "calendarOn") } }
    @Published var calendarDenied = false
    @Published var hotkeyOK = true

    let calendar = CalendarSync()
    private var peeking = false
    private var undoWork: DispatchWorkItem?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TaskOut")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }
    private struct Persisted: Codable { var tasks: [TaskItem]; var categories: [TaskCategory] }

    init() {
        calendarOn = UserDefaults.standard.object(forKey: "calendarOn") as? Bool ?? true
        if let data = try? Data(contentsOf: Self.fileURL), let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            tasks = p.tasks
            categories = p.categories
        }
        draft.categoryID = categories.first?.id
        calendar.refreshStatus()
        if calendarOn && !calendar.authorized {
            Task { await enableCalendar() }
        }
    }

    private func save() {
        let p = Persisted(tasks: tasks, categories: categories)
        if let data = try? JSONEncoder().encode(p) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    // MARK: - Consultas

    func category(_ id: UUID?) -> TaskCategory? { categories.first { $0.id == id } }
    func task(_ id: UUID?) -> TaskItem? { tasks.first { $0.id == id } }

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }

    var sections: [TaskSection] {
        let cal = Calendar.current
        let today = startOfToday
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: today)!
        let open = tasks.filter { !$0.done || $0.id == completingID }.sorted { $0.start < $1.start }
        var overdue: [TaskItem] = [], now: [TaskItem] = [], next: [TaskItem] = [], later: [TaskItem] = []
        for t in open {
            if t.start < today { if t.end > today { now.append(t) } else { overdue.append(t) } }
            else if t.start < tomorrow { now.append(t) }
            else if t.start < dayAfter { next.append(t) }
            else { later.append(t) }
        }
        var result = [TaskSection(kind: .overdue, tasks: overdue), TaskSection(kind: .today, tasks: now),
                      TaskSection(kind: .tomorrow, tasks: next), TaskSection(kind: .later, tasks: later)]
        if showDone { result.append(TaskSection(kind: .done, tasks: doneToday)) }
        return result.filter { !$0.tasks.isEmpty }
    }

    var doneToday: [TaskItem] {
        tasks.filter { $0.done && $0.id != completingID && ($0.doneAt ?? .distantPast) >= startOfToday }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    var flatIDs: [UUID] { sections.flatMap { $0.tasks.map(\.id) } }

    /// (hechas, total) de lo que toca hoy, para el anillo de progreso.
    var progress: (done: Int, total: Int) {
        let d = doneToday.count + (completingID != nil ? 1 : 0)
        let openToday = sections.first { $0.kind == .today }?.tasks.filter { $0.id != completingID }.count ?? 0
        let overdue = sections.first { $0.kind == .overdue }?.tasks.count ?? 0
        return (d, d + openToday + overdue)
    }

    // MARK: - Borrador

    func resetDraft() {
        let cat = draft.categoryID
        draft = Draft()
        draft.categoryID = cat ?? categories.first?.id
    }

    /// Al mostrar el panel: si no hay nada a medias, la hora vuelve a ser "ahora".
    func panelDidShow() {
        if !draft.isActive { resetDraft() }
        calendar.refreshStatus()
        calendarDenied = calendar.isDenied
        ensureSelection()
        focusTick += 1
    }

    func submit() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var id: UUID
        if let eid = draft.editingID, let i = tasks.firstIndex(where: { $0.id == eid }) {
            tasks[i].title = title
            tasks[i].notes = notes
            tasks[i].categoryID = draft.categoryID
            tasks[i].start = draft.start
            tasks[i].end = draft.end
            id = eid
            sync(i)
        } else {
            let t = TaskItem(title: title, notes: notes, categoryID: draft.categoryID, start: draft.start, end: draft.end)
            tasks.append(t)
            id = t.id
            sync(tasks.count - 1)
        }
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { resetDraft() }
        selectedID = id
        Feedback.soft()
    }

    func cancelDraft() {
        withAnimation(.easeOut(duration: 0.2)) { resetDraft() }
    }

    func edit(_ id: UUID) {
        guard let t = task(id) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            draft = Draft(title: t.title, notes: t.notes,
                          day: Calendar.current.startOfDay(for: t.start), time: t.start,
                          minutes: max(5, Int(t.end.timeIntervalSince(t.start) / 60)),
                          categoryID: t.categoryID, editingID: t.id)
        }
        focusTick += 1
    }

    // MARK: - Acciones

    func requestToggle(_ id: UUID) {
        guard let t = task(id) else { return }
        if t.done { reopen(id); return }
        guard completingID == nil else { return }
        completingID = id
        Feedback.complete()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finishComplete(id) }
    }

    private func finishComplete(_ id: UUID) {
        let ids = flatIDs
        let idx = ids.firstIndex(of: id) ?? 0
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { completingID = nil; return }
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
            tasks[i].done = true
            tasks[i].doneAt = Date()
            completingID = nil
        }
        calendar.remove(eventID: tasks[i].eventID)
        tasks[i].eventID = nil
        let remaining = flatIDs
        selectedID = remaining.isEmpty ? nil : remaining[min(idx, remaining.count - 1)]
        lastDoneID = id
        undoWork?.cancel()
        let w = DispatchWorkItem { [weak self] in withAnimation { self?.lastDoneID = nil } }
        undoWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
    }

    func reopen(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(duration: 0.4)) {
            tasks[i].done = false
            tasks[i].doneAt = nil
            if lastDoneID == id { lastDoneID = nil }
        }
        sync(i)
        selectedID = id
    }

    func undoLast() {
        if let id = lastDoneID { reopen(id) }
    }

    func delete(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let ids = flatIDs
        let idx = ids.firstIndex(of: id) ?? 0
        calendar.remove(eventID: tasks[i].eventID)
        withAnimation(.spring(duration: 0.4)) { _ = tasks.remove(at: i) }
        let remaining = flatIDs
        selectedID = remaining.isEmpty ? nil : remaining[min(idx, remaining.count - 1)]
    }

    func postponeOneDay(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let cal = Calendar.current
        withAnimation(.spring(duration: 0.4)) {
            tasks[i].start = cal.date(byAdding: .day, value: 1, to: tasks[i].start)!
            tasks[i].end = cal.date(byAdding: .day, value: 1, to: tasks[i].end)!
        }
        sync(i)
        Feedback.soft()
    }

    // MARK: - Selección y teclado

    func ensureSelection() {
        let ids = flatIDs
        if selectedID == nil || !ids.contains(selectedID!) { selectedID = ids.first }
    }

    private func move(_ delta: Int) {
        let ids = flatIDs
        guard !ids.isEmpty else { return }
        ensureSelection()
        let i = ids.firstIndex(of: selectedID!) ?? 0
        selectedID = ids[max(0, min(ids.count - 1, i + delta))]
    }

    /// Devuelve true si el evento fue consumido.
    func handle(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        let composing = draft.isActive
        if e.type == .keyUp {
            if e.keyCode == 48, peeking {
                peeking = false
                withAnimation(.spring(duration: 0.3)) { peekID = nil }
                return true
            }
            return false
        }
        switch e.keyCode {
        case 48: // Tab: mantener = ver la nota sin salir de la lista
            if composing || notesFocused { return false }
            if !peeking {
                ensureSelection()
                peeking = true
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { peekID = selectedID }
            }
            return true
        case 126 where !notesFocused: move(-1); return true
        case 125 where !notesFocused: move(1); return true
        case 36, 76: // Return sin texto = completar la seleccionada
            if composing || notesFocused { return false }
            if let id = selectedID { requestToggle(id) }
            return true
        case 53: // Esc: limpiar el borrador
            if composing { cancelDraft(); return true }
            return false
        case 51 where cmd: // ⌘⌫ eliminar
            if let id = selectedID, !composing { delete(id); return true }
            return false
        case 124 where cmd: // ⌘→ posponer a mañana
            if let id = selectedID, !composing { postponeOneDay(id); return true }
            return false
        case 14 where cmd: // ⌘E editar
            if let id = selectedID { edit(id); return true }
            return false
        case 6 where cmd: // ⌘Z deshacer
            if !composing, lastDoneID != nil { undoLast(); return true }
            return false
        default: return false
        }
    }

    // MARK: - Calendario

    private func sync(_ i: Int) {
        guard calendarOn else { return }
        tasks[i].eventID = calendar.upsert(tasks[i], category: category(tasks[i].categoryID))
    }

    func syncAll() {
        guard calendarOn, calendar.authorized else { return }
        for i in tasks.indices where !tasks[i].done { sync(i) }
    }

    func enableCalendar() async {
        let ok = await calendar.requestAccess()
        calendarDenied = !ok && calendar.isDenied
        calendarOn = ok
        if ok { syncAll() }
    }

    func toggleCalendar() {
        if calendarOn {
            calendarOn = false
        } else {
            Task { await enableCalendar() }
        }
    }

    func addCategory() {
        let used = Set(categories.map(\.colorHex))
        let hex = Palette.hexes.first { !used.contains($0) } ?? Palette.hexes[0]
        categories.append(TaskCategory(name: "Nueva", colorHex: hex))
    }

    func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for i in tasks.indices where tasks[i].categoryID == id { tasks[i].categoryID = nil }
        if draft.categoryID == id { draft.categoryID = categories.first?.id }
    }
}

enum Feedback {
    static func complete() {
        NSSound(named: "Tink")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    static func soft() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
