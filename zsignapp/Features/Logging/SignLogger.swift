//
//  SignLogger.swift

import Foundation
import Combine

final class SignLogger: ObservableObject {
    static let shared = SignLogger()
    private init() {}

    @Published private(set) var lines: [String] = []

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "zsign.loggingEnabled") }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func start(_ title: String) {
        guard isEnabled else { return }
        set([])
        log(title)
    }

    func log(_ message: String) {
        guard isEnabled else { return }
        let clean = SignLogger.sanitize(message)
        let line = "- \(SignLogger.timeFormatter.string(from: Date())) \(clean)"
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 3000 { self.lines.removeFirst(self.lines.count - 3000) }
        }
    }

    func clear() { set([]) }

    var fullText: String { lines.joined(separator: "\n") }

    private func set(_ v: [String]) {
        DispatchQueue.main.async { self.lines = v }
    }

    private static func sanitize(_ s: String) -> String {
        let filtered = s.unicodeScalars.filter { scalar in
            if scalar.properties.isEmoji && scalar.value > 0x238C { return false }
            switch scalar.value {
            case 0x1F000...0x1FAFF, 0x2600...0x27BF, 0xFE00...0xFE0F, 0x1F1E6...0x1F1FF:
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: .whitespaces)
    }
}
