//
//  InstalledRegistry.swift
//  zsignapp
//

import Foundation

enum InstallStateKind {
    case notInstalled
    case installed
    case updateAvailable
}

enum InstalledRegistry {
    private static let key = "zsign.installedApps"

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
