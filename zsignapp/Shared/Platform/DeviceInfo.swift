//
//  DeviceInfo.swift
//  zsignapp
//
//  Đọc định danh phần cứng máy (vd "iPhone14,2") + model number (nếu có).
//

import Foundation

enum DeviceInfo {
    static let modelIdentifier: String = {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        var id = ""
        for child in mirror.children {
            if let v = child.value as? Int8, v != 0 {
                id.append(Character(UnicodeScalar(UInt8(v))))
            }
        }
        return id.isEmpty ? "unknown" : id
    }()

    static var deviceIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return simulated
        }
        return modelIdentifier
    }

    static var iPhoneGeneration: Int? {
        let id = deviceIdentifier
        guard id.hasPrefix("iPhone") else { return nil }
        let rest = id.dropFirst("iPhone".count)
        guard let comma = rest.firstIndex(of: ",") else { return nil }
        return Int(rest[rest.startIndex..<comma])
    }

    static var hasDynamicIsland: Bool {
        guard let generation = iPhoneGeneration else { return false }
        return generation >= 15
    }
}
