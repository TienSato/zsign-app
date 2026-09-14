//
//  UDIDReader.swift
//  zsignapp
//
//  Đọc UDID thiết bị từ `embedded.mobileprovision` trong bundle (ProvisionedDevices).
//  Chạy trên BẢN KÝ THƯỜNG (ký theo từng máy) — không dùng MobileGestalt hay
//  entitlement private (những thứ đó bản ký thường không có quyền).
//

import Foundation

enum UDIDReader {

    /// UDID thiết bị hiện tại (từ provisioning profile). nil nếu không xác định được.
    static func deviceUDID() -> String? {
        let devices = provisionedDevices()
        if devices.count == 1 { return devices[0] }   // ký per-device -> chính là máy này
        return devices.first                           // nhiều máy -> lấy đầu (best-effort)
    }

    static var isAvailable: Bool {
        if let u = deviceUDID(), !u.isEmpty { return true }
        return false
    }

    /// Mảng ProvisionedDevices trong embedded.mobileprovision.
    static func provisionedDevices() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let plistData = extractPlist(from: data) else {
            return []
        }
        let obj = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        guard let dict = obj as? [String: Any],
              let devices = dict["ProvisionedDevices"] as? [String] else {
            return []
        }
        return devices
    }

    /// embedded.mobileprovision là khối CMS đã ký — trích phần plist XML bên trong.
    private static func extractPlist(from data: Data) -> Data? {
        let head = Data("<?xml".utf8)
        let tail = Data("</plist>".utf8)
        guard let start = data.range(of: head)?.lowerBound,
              let end = data.range(of: tail, options: .backwards)?.upperBound,
              start < end else {
            return nil
        }
        return data.subdata(in: start..<end)
    }
}
