import SwiftUI
import AppKit

struct TaskCategory: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String
    var color: Color { Color(hex: colorHex) }
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var notes = ""
    var categoryID: UUID?
    var start: Date
    var end: Date
    var done = false
    var doneAt: Date?
    var eventID: String?
}

enum SectionKind: String {
    case overdue, today, tomorrow, later, done
    var title: String {
        switch self {
        case .overdue: return "De antes"
        case .today: return "Hoy"
        case .tomorrow: return "Mañana"
        case .later: return "Más adelante"
        case .done: return "Hechas hoy"
        }
    }
}

struct TaskSection: Identifiable {
    let kind: SectionKind
    let tasks: [TaskItem]
    var id: String { kind.rawValue }
}

enum Palette {
    static let hexes = ["E5675C", "F0A04B", "E8C547", "6DBE8C", "4FB3BF", "5B8DEF", "9A7BE0", "E37FB5", "8E8E93"]
    static let defaults: [TaskCategory] = [
        TaskCategory(name: "Hogar", colorHex: "F0A04B"),
        TaskCategory(name: "Ejercicio", colorHex: "6DBE8C"),
        TaskCategory(name: "Trabajo", colorHex: "5B8DEF"),
        TaskCategory(name: "Freelance", colorHex: "9A7BE0"),
        TaskCategory(name: "Colegio hija", colorHex: "E37FB5"),
        TaskCategory(name: "Personal", colorHex: "4FB3BF"),
    ]
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

/// Borrador de la tarea que se está escribiendo (o editando).
struct Draft {
    var title = ""
    var notes = ""
    var day = Calendar.current.startOfDay(for: Date())
    var time = Draft.roundedNow()
    var minutes = 60
    var categoryID: UUID?
    var editingID: UUID?

    var start: Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }
    var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
    var isActive: Bool { !title.isEmpty || !notes.isEmpty || editingID != nil }

    /// Ahora, redondeado hacia arriba a los 5 minutos.
    static func roundedNow() -> Date {
        let now = Date()
        let step = 300.0
        return Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
    }
}

let es = Locale(identifier: "es_ES")
