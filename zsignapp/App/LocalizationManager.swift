//
//  LocalizationManager.swift
//  zsignapp
//  Quản lý ngôn ngữ: mặc định theo máy, cho phép chọn thủ công và đổi
//  NGAY LẬP TỨC không cần khởi động lại (đổi bundle localization của Bundle.main).
//  Thêm ngôn ngữ mới = thêm 1 case vào AppLanguage + 1 thư mục <mã>.lproj.
//

import Foundation
import SwiftUI
import ObjectiveC

// MARK: - Danh sách ngôn ngữ

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case vi
    case en

    var id: String { rawValue }

    /// Mã thư mục .lproj. nil = theo hệ thống.
    var code: String? {
        switch self {
        case .system: return nil
        case .vi:     return "vi"
        case .en:     return "en"
        }
    }

    /// Tên hiển thị — viết bằng chính ngôn ngữ đó, KHÔNG dịch.
    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("Follow System", comment: "")
        case .vi:     return "Tiếng Việt"
        case .en:     return "English"
        }
    }

    var flag: String {
        switch self {
        case .system: return "🌐"
        case .vi:     return "🇻🇳"
        case .en:     return "🇬🇧"
        }
    }
}

// MARK: - Bundle có thể đổi ngôn ngữ lúc chạy

private var kLocalizedBundle: UInt8 = 0

private final class LocalizedBundle: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let inner = objc_getAssociatedObject(self, &kLocalizedBundle) as? Bundle {
            return inner.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Ép Bundle.main tra cứu chuỗi từ <code>.lproj. nil = trả về mặc định hệ thống.
    static func setAppLanguage(_ code: String?) {
        _ = swizzleOnce
        var inner: Bundle?
        if let code,
           let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            inner = Bundle(path: path)
        }
        objc_setAssociatedObject(Bundle.main, &kLocalizedBundle, inner, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static let swizzleOnce: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()
}

// MARK: - Manager

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    private let d = UserDefaults.standard

    private let kLanguage = "app.language"
    private let kChosen   = "app.languageChosen"

    @Published var language: AppLanguage {
        didSet {
            d.set(language.rawValue, forKey: kLanguage)
            Bundle.setAppLanguage(language.code)
        }
    }

    /// Đã từng chọn ngôn ngữ chưa (để hiện màn chọn lần đầu mở app).
    @Published var hasChosen: Bool {
        didSet { d.set(hasChosen, forKey: kChosen) }
    }

    private init() {
        let raw = d.string(forKey: kLanguage) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
        hasChosen = d.bool(forKey: kChosen)
        Bundle.setAppLanguage(language.code)
    }

    /// Locale dùng cho .environment(\.locale) — ảnh hưởng định dạng ngày/số.
    var locale: Locale {
        if let c = language.code { return Locale(identifier: c) }
        return Locale.current
    }

    /// Ngôn ngữ đang thực sự áp dụng (giải quyết .system).
    var resolvedCode: String {
        if let c = language.code { return c }
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("vi") ? "vi" : "en"
    }
}

// MARK: - Rút gọn

/// Dùng ở nơi cần String (Text(bienString) KHÔNG tự dịch, khác Text("literal")).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
