//
//  DeviceInfo.swift
//  zsignapp
//
//  Đọc định danh phần cứng máy (vd "iPhone14,2") + model number (nếu có).
//

import Foundation

enum DeviceInfo {
    /// Định danh phần cứng, vd "iPhone14,2" (đọc từ uname, không cần quyền gì).
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

}
