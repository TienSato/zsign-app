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

    /// Định danh dùng để nhận dạng máy.
    /// Trên máy giả lập, uname trả về "arm64"/"x86_64" — định danh máy đang
    /// giả lập nằm trong biến môi trường của Simulator.
    static var deviceIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return simulated
        }
        return modelIdentifier
    }

    /// Số đời trong "iPhone<đời>,<biến thể>". nil nếu không phải iPhone.
    static var iPhoneGeneration: Int? {
        let id = deviceIdentifier
        guard id.hasPrefix("iPhone") else { return nil }
        let rest = id.dropFirst("iPhone".count)
        guard let comma = rest.firstIndex(of: ",") else { return nil }
        return Int(rest[rest.startIndex..<comma])
    }

    /// Máy có Dynamic Island THẬT hay không.
    ///
    /// Xác định theo ĐỊNH DANH PHẦN CỨNG, không đoán theo chiều cao safe area
    /// (safe area chỉ nói máy có phần khuyết ở đỉnh, không phân biệt được tai
    /// thỏ với Dynamic Island).
    ///
    /// Apple đánh số theo "iPhone<đời>,<biến thể>", mốc chia rất gọn:
    ///   iPhone14,7 / 14,8   = iPhone 14 / 14 Plus       -> tai thỏ
    ///   iPhone15,2 / 15,3   = iPhone 14 Pro / Pro Max   -> Dynamic Island
    ///   iPhone15,4 / 15,5   = iPhone 15 / 15 Plus       -> Dynamic Island
    ///   iPhone16,x trở lên  = 15 Pro và mọi đời sau     -> Dynamic Island
    ///
    /// Nên điều kiện đúng gọn lại thành: là iPhone VÀ số đời >= 15.
    /// Viết theo số đời nên đời máy mới ra sau này tự động đúng, không phải
    /// bổ sung danh sách.
    static var hasDynamicIsland: Bool {
        guard let generation = iPhoneGeneration else { return false }
        return generation >= 15
    }
}
