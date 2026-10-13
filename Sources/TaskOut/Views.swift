import SwiftUI

private let rounded = Font.Design.rounded

// MARK: - Raíz

struct RootView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            ComposerView()
            TaskListView()
            FooterView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cabecera

struct HeaderView: View {
    @EnvironmentObject var store: Store
    @State private var showCategories = false

    var body: some View {
        let p = store.progress
        HStack(alignment: .center, spacing: 12) {
            ProgressRing(done: p.done, total: p.total)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hoy")
                    .font(.system(size: 24, weight: .bold, design: rounded))
                Text(Date().formatted(.dateTime.locale(es).weekday(.wide).day().month(.wide)).prefix(1).uppercased() + Date().formatted(.dateTime.locale(es).weekday(.wide).day().month(.wide)).dropFirst())
                    .font(.system(size: 12, weight: .medium, design: rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HeaderButton(symbol: calendarSymbol, tint: store.calendarOn ? .green : .secondary,
                         help: calendarHelp) { store.toggleCalendar() }
            HeaderButton(symbol: store.showDone ? "checkmark.circle.fill" : "checkmark.circle",
                         tint: store.showDone ? .accentColor : .secondary, help: "Ver lo hecho hoy") {
                withAnimation(.spring(duration: 0.35)) { store.showDone.toggle() }
            }
            HeaderButton(symbol: "tag", tint: .secondary, help: "Categorías") { showCategories.toggle() }
                .popover(isPresented: $showCategories, arrowEdge: .bottom) {
                    CategoryEditor().environmentObject(store)
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var calendarSymbol: String {
        store.calendarDenied ? "calendar.badge.exclamationmark" : (store.calendarOn ? "calendar.badge.checkmark" : "calendar")
    }
    private var calendarHelp: String {
        if store.calendarDenied { return "Permite el acceso en Ajustes del Sistema › Privacidad › Calendarios" }
        return store.calendarOn ? "Sincronizando con Calendario (clic para pausar)" : "Sincronizar con Calendario"
    }
}

struct HeaderButton: View {
    let symbol: String
    let tint: Color
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0.0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct ProgressRing: View {
    let done: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [.mint, .green], center: .center), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.7, bounce: 0.2), value: fraction)
            Text(total == 0 ? "·" : "\(done)/\(total)")
                .font(.system(size: 10, weight: .bold, design: rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Crear / editar

struct ComposerView: View {
    @EnvironmentObject var store: Store
    @FocusState private var titleFocus: Bool
    @FocusState private var notesFocus: Bool

    private let durations: [(String, Int)] = [("15 min", 15), ("30 min", 30), ("1 h", 60), ("2 h", 120), ("1 día", 1440)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: store.draft.editingID == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(currentColor)
                TextField(store.draft.editingID == nil ? "Anotar algo…" : "Editando…", text: $store.draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: rounded))
                    .focused($titleFocus)
                    .onSubmit { store.submit() }
                if !store.draft.title.isEmpty {
                    Button { store.submit() } label: {
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(currentColor))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))

            if store.draft.isActive {
                VStack(alignment: .leading, spacing: 9) {
                    categoryRow
                    whenRow
                    durationRow
                    TextField("Nota (opcional)", text: $store.draft.notes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: rounded))
                        .focused($notesFocus)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                        .onSubmit { store.submit() }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: store.draft.isActive)
        .onChange(of: store.focusTick) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { titleFocus = true }
        }
        .onChange(of: notesFocus) { _, v in store.notesFocused = v }
        .onAppear { titleFocus = true }
    }

    private var currentColor: Color { store.category(store.draft.categoryID)?.color ?? .accentColor }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.categories) { c in
                    Chip(label: c.name, dot: c.color, selected: store.draft.categoryID == c.id, tint: c.color) {
                        store.draft.categoryID = c.id
                    }
                }
            }
        }
    }

    private var whenRow: some View {
        HStack(spacing: 6) {
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            Chip(label: "Hoy", selected: store.draft.day == today) { store.draft.day = today }
            Chip(label: "Mañana", selected: store.draft.day == tomorrow) { store.draft.day = tomorrow }
            DatePicker("", selection: $store.draft.day, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact).scaleEffect(0.9)
            Spacer(minLength: 0)
            DatePicker("", selection: $store.draft.time, displayedComponents: .hourAndMinute)
                .labelsHidden().datePickerStyle(.compact).scaleEffect(0.9)
        }
    }

    private var durationRow: some View {
        HStack(spacing: 6) {
            ForEach(durations, id: \.1) { d in
                Chip(label: d.0, selected: store.draft.minutes == d.1) { store.draft.minutes = d.1 }
            }
            Spacer(minLength: 0)
            Text("→ " + store.draft.end.formatted(.dateTime.locale(es).hour().minute()))
                .font(.system(size: 11, weight: .medium, design: rounded))
                .foregroundStyle(.secondary)
        }
    }
}

struct Chip: View {
    let label: String
    var dot: Color? = nil
    let selected: Bool
    var tint: Color = .accentColor
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .background(Capsule().fill(selected ? tint.opacity(0.28) : Color.primary.opacity(hover ? 0.1 : 0.06)))
            .overlay(Capsule().strokeBorder(selected ? tint.opacity(0.7) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Lista

struct TaskListView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    let sections = store.sections
                    if sections.isEmpty { EmptyState().padding(.top, 50) }
                    ForEach(sections) { sec in
                        SectionHeader(kind: sec.kind, count: sec.tasks.count)
                        ForEach(sec.tasks) { t in
                            TaskRow(task: t, kind: sec.kind)
                                .id(t.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .move(edge: .trailing))))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.selectedID) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } }
            }
        }
    }
}

struct SectionHeader: View {
    let kind: SectionKind
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(kind.title.uppercased())
                .font(.system(size: kind == .today ? 12 : 10.5, weight: .heavy, design: rounded))
                .tracking(0.8)
                .foregroundStyle(kind == .today ? Color.primary : Color.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, kind == .today ? 6 : 12)
        .padding(.bottom, 2)
    }
}

struct EmptyState: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let finished = store.doneToday.count > 0
        VStack(spacing: 10) {
            Image(systemName: finished ? "sparkles" : "leaf")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(finished ? Color.yellow : Color.mint)
            Text(finished ? "Todo hecho por hoy" : "Todo en calma")
                .font(.system(size: 16, weight: .semibold, design: rounded))
            Text(finished ? "Respira. Lo lograste." : "Nada pendiente. Escribe arriba para anotar algo.")
                .font(.system(size: 12, design: rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
    }
}

// MARK: - Tarea

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let task: TaskItem
    let kind: SectionKind

    private var cat: TaskCategory? { store.category(task.categoryID) }
    private var color: Color { cat?.color ?? .gray }
    private var isToday: Bool { kind == .today || kind == .overdue }
    private var selected: Bool { store.selectedID == task.id }
    private var peeking: Bool { store.peekID == task.id }
    private var completing: Bool { store.completingID == task.id }
    private var isDone: Bool { task.done || completing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 11) {
                CheckButton(color: color, done: isDone, big: isToday) { store.requestToggle(task.id) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: isToday ? 14.5 : 13, weight: isToday ? .semibold : .medium, design: rounded))
                        .strikethrough(isDone, color: .secondary)
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(timeLabel)
                        if let cat { Text("·"); Text(cat.name) }
                    }
                    .font(.system(size: 11, weight: .medium, design: rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !task.notes.isEmpty && !peeking {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            if peeking {
                Text(task.notes.isEmpty ? "Sin notas" : task.notes)
                    .font(.system(size: 12.5, design: rounded))
                    .foregroundStyle(task.notes.isEmpty ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8).padding(.leading, 33)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isToday ? 10 : 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isToday ? color.opacity(selected ? 0.2 : 0.11) : Color.primary.opacity(selected ? 0.08 : 0))
        )
        .overlay(alignment: .leading) {
            if isToday {
                Capsule().fill(color).frame(width: 3).padding(.vertical, 9).padding(.leading, 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? color.opacity(0.55) : .clear, lineWidth: 1)
        )
        .opacity(kind == .later ? 0.78 : (kind == .tomorrow ? 0.9 : 1))
        .scaleEffect(completing ? 0.97 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: completing)
        .contentShape(Rectangle())
        .onHover { if $0 { store.selectedID = task.id } }
        .contextMenu {
            Button("Editar") { store.edit(task.id) }
            Button("Posponer a mañana") { store.postponeOneDay(task.id) }
            Divider()
            Button("Eliminar", role: .destructive) { store.delete(task.id) }
        }
    }

    private var timeLabel: String {
        let t = Date.FormatStyle(locale: es).hour().minute()
        let dur = task.end.timeIntervalSince(task.start)
        let range = dur >= 86_400 ? "\(task.start.formatted(t)) · 1 día" : "\(task.start.formatted(t)) – \(task.end.formatted(t))"
        if kind == .later || kind == .overdue {
            return task.start.formatted(.dateTime.locale(es).weekday(.abbreviated).day().month(.abbreviated)) + ", " + task.start.formatted(t)
        }
        return range
    }
}

struct CheckButton: View {
    let color: Color
    let done: Bool
    let big: Bool
    let action: () -> Void
    @State private var burst = false

    var body: some View {
        let size: CGFloat = big ? 24 : 20
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(color.opacity(0.85), lineWidth: 2)
                Circle().fill(color).scaleEffect(done ? 1 : 0.01)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .heavy))
                    .foregroundStyle(.white)
                    .scaleEffect(done ? 1 : 0.01)
                    .opacity(done ? 1 : 0)
                if burst { Burst(color: color, radius: size * 1.1) }
            }
            .frame(width: size, height: size)
            .animation(.spring(duration: 0.35, bounce: 0.45), value: done)
        }
        .buttonStyle(.plain)
        .onChange(of: done) { _, v in
            guard v else { return }
            burst = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { burst = false }
        }
    }
}

/// Pequeña explosión de puntitos al completar: el "premio".
struct Burst: View {
    let color: Color
    let radius: CGFloat
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * 2 * .pi
                Circle()
                    .fill(i.isMultiple(of: 2) ? color : color.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .offset(x: go ? cos(a) * radius : 0, y: go ? sin(a) * radius : 0)
                    .scaleEffect(go ? 0.3 : 1)
                    .opacity(go ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { go = true } }
    }
}

// MARK: - Pie

struct FooterView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ZStack {
            if store.lastDoneID != nil {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Hecha").font(.system(size: 12, weight: .semibold, design: rounded))
                    Spacer()
                    Button("Deshacer") { store.undoLast() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: rounded))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(0.1)))
                .padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    Hint(keys: "⇥", text: "mantén: nota")
                    Hint(keys: "↑↓", text: "elegir")
                    Hint(keys: "↩", text: "hecha")
                    Hint(keys: "⌥T", text: store.hotkeyOK ? "cerrar" : "⚠︎ ocupado")
                }
                .transition(.opacity)
            }
        }
        .frame(height: 38)
        .animation(.spring(duration: 0.35), value: store.lastDoneID)
    }
}

struct Hint: View {
    let keys: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
            Text(text).font(.system(size: 10, design: .rounded))
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Categorías

struct CategoryEditor: View {
    @EnvironmentObject var store: Store
    @State private var colorPickerFor: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categorías").font(.system(size: 13, weight: .bold, design: rounded))
            ForEach($store.categories) { $c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button { colorPickerFor = colorPickerFor == c.id ? nil : c.id } label: {
                            Circle().fill(c.color).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                        }.buttonStyle(.plain)
                        TextField("Nombre", text: $c.name).textFieldStyle(.plain)
                        Button { store.deleteCategory(c.id) } label: {
                            Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    if colorPickerFor == c.id {
                        HStack(spacing: 6) {
                            ForEach(Palette.hexes, id: \.self) { hex in
                                Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.primary.opacity(c.colorHex == hex ? 0.8 : 0), lineWidth: 2))
                                    .onTapGesture { c.colorHex = hex; colorPickerFor = nil }
                            }
                        }
                    }
                }
            }
            Button { store.addCategory() } label: {
                Label("Nueva categoría", systemImage: "plus").font(.system(size: 12, weight: .semibold, design: rounded))
            }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .frame(width: 230)
        .onDisappear { store.syncAll() }
    }
}
