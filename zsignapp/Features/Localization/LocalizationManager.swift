//
//  LocalizationManager.swift
//  zsignapp
import Foundation
import SwiftUI
import ObjectiveC

// MARK: - Danh sách ngôn ngữ

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case vi
    case en

    var id: String { rawValue }

    var code: String? {
        switch self {
        case .system: return nil
        case .vi:     return "vi"
        case .en:     return "en"
        }
    }

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

    @Published var hasChosen: Bool {
        didSet { d.set(hasChosen, forKey: kChosen) }
    }

    private init() {
        let raw = d.string(forKey: kLanguage) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
        hasChosen = d.bool(forKey: kChosen)
        Bundle.setAppLanguage(language.code)
    }

    var locale: Locale {
        if let c = language.code { return Locale(identifier: c) }
        return Locale.current
    }

    var resolvedCode: String {
        if let c = language.code { return c }
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("vi") ? "vi" : "en"
    }
}

// MARK: - Rút gọn

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
