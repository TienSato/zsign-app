//
//  AppearanceManager.swift
//  zsignapp
//  Quản lý giao diện do người dùng chọn: màu chủ đạo (theo máy / preset / tùy chỉnh)
//  và chế độ sáng/tối. Lưu vào UserDefaults, áp toàn app qua .tint + .preferredColorScheme.
//

import SwiftUI
import UIKit

enum AccentMode: String, CaseIterable, Identifiable {
    case auto, preset, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto:   return L("Device")
        case .preset: return L("Preset")
        case .custom: return L("Custom")
        }
    }
}

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("System")
        case .light:  return L("Light")
        case .dark:   return L("Dark")
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()
    private let d = UserDefaults.standard

    @Published var mode: AccentMode { didSet { d.set(mode.rawValue, forKey: "appearance.mode") } }
    @Published var presetIndex: Int { didSet { d.set(presetIndex, forKey: "appearance.presetIndex") } }
    @Published var customColor: Color { didSet { d.set(customColor.toHexString(), forKey: "appearance.customHex") } }
    @Published var appScheme: AppColorScheme { didSet { d.set(appScheme.rawValue, forKey: "appearance.scheme") } }

    /// Bảng màu preset (dịu, hợp iOS).
    static let presets: [(name: String, color: Color)] = [
        ("Blue", Color(red: 0.20, green: 0.48, blue: 0.90)),
        ("Indigo",       Color(red: 0.30, green: 0.35, blue: 0.78)),
        ("Purple",        Color(red: 0.55, green: 0.35, blue: 0.90)),
        ("Pink",       Color(red: 0.94, green: 0.36, blue: 0.56)),
        ("Red",         Color(red: 0.89, green: 0.30, blue: 0.31)),
        ("Cam",        Color(red: 0.97, green: 0.55, blue: 0.20)),
        ("Yellow",       Color(red: 0.93, green: 0.76, blue: 0.24)),
        ("Green",    Color(red: 0.25, green: 0.72, blue: 0.45)),
        ("Teal",       Color(red: 0.18, green: 0.68, blue: 0.70)),
        ("Slate",     Color(red: 0.42, green: 0.45, blue: 0.52)),
    ]

    private init() {
        mode = AccentMode(rawValue: d.string(forKey: "appearance.mode") ?? "") ?? .auto
        presetIndex = d.object(forKey: "appearance.presetIndex") as? Int ?? 0
        customColor = Color(hexString: d.string(forKey: "appearance.customHex") ?? "")
            ?? Color(red: 0.20, green: 0.48, blue: 0.90)
        appScheme = AppColorScheme(rawValue: d.string(forKey: "appearance.scheme") ?? "") ?? .system
    }

    /// Màu chủ đạo cuối cùng (cần truyền màu máy hiện tại cho chế độ auto).
    func effectiveAccent(deviceAccent: Color) -> Color {
        switch mode {
        case .auto:
            return deviceAccent
        case .preset:
            return Self.presets.indices.contains(presetIndex) ? Self.presets[presetIndex].color : deviceAccent
        case .custom:
            return customColor
        }
    }
}

// MARK: - Color <-> Hex

extension Color {
    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard (s.count == 6 || s.count == 8), let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xff) / 255
            g = Double((v >> 16) & 0xff) / 255
            b = Double((v >> 8) & 0xff) / 255
            a = Double(v & 0xff) / 255
        } else {
            r = Double((v >> 16) & 0xff) / 255
            g = Double((v >> 8) & 0xff) / 255
            b = Double(v & 0xff) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
