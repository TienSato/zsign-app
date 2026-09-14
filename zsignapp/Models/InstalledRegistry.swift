//
//  InstalledRegistry.swift
//  zsignapp
//
//  Ghi nhớ app đã ký/cài (bundle id -> version) để phân biệt Cài đặt vs Cập nhật.
//  Dùng RECORD của chính zsign — không dùng LSApplicationWorkspace/API hạn chế.
//

import Foundation

enum InstallStateKind {
    case notInstalled     // chưa từng ký/cài qua zsign
    case installed        // đã cài, đúng version
    case updateAvailable  // đã cài, có bản mới hơn
}

enum InstalledRegistry {
    private static let key = "zsign.installedApps"   // UserDefaults: [bundleId: version]

    /// Gọi khi cài xong: nhớ version đã cài cho bundle id.
    static func record(bundleId: String?, version: String?) {
        guard let bid = bundleId, !bid.isEmpty else { return }
        var map = load()
        map[bid] = version ?? ""
        UserDefaults.standard.set(map, forKey: key)
    }

    static func installedVersion(bundleId: String?) -> String? {
        guard let bid = bundleId, !bid.isEmpty else { return nil }
        return load()[bid]
    }

    /// So version có sẵn với version đã cài -> trạng thái.
    static func status(bundleId: String?, availableVersion: String?) -> InstallStateKind {
        guard let installed = installedVersion(bundleId: bundleId) else { return .notInstalled }
        guard let avail = availableVersion, !avail.isEmpty else { return .installed }
        if installed.isEmpty { return .installed }
        return avail.compare(installed, options: .numeric) == .orderedDescending
            ? .updateAvailable : .installed
    }

    private static func load() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }
}
