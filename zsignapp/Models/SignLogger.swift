//
//  SignLogger.swift
//  zsignapp
//  Nhật ký quá trình ký (bật/tắt ở Cài đặt → Nâng cao).
//  Quy ước: KHÔNG emoji/icon trong nội dung log; mỗi dòng bắt đầu bằng "- ".
//

import Foundation
import Combine

final class SignLogger: ObservableObject {
    static let shared = SignLogger()
    private init() {}

    @Published private(set) var lines: [String] = []

    /// Bật/tắt qua UserDefaults (khớp @AppStorage("zsign.loggingEnabled")).
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "zsign.loggingEnabled") }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Bắt đầu một phiên log mới (xoá log cũ rồi ghi tiêu đề).
    func start(_ title: String) {
        guard isEnabled else { return }
        set([])
        log(title)
    }

    /// Ghi 1 dòng. Gọi được từ bất kỳ thread nào.
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

    /// Loại bỏ emoji/ký tự biểu tượng để giữ log thuần văn bản.
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
