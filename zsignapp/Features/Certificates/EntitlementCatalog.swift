//
//  EntitlementCatalog.swift
//  zsignapp
//
//  Danh mục quyền (entitlement) để màn hình Chi tiết chứng chỉ hiển thị tên dễ
//  hiểu + mô tả ngắn thay vì chỉ có chuỗi com.apple.developer... khô khan.
//
//  Khoá nào không có trong danh mục vẫn được hiện, xếp vào nhóm "Khác" và lấy
//  đoạn cuối của khoá làm tên — không bao giờ giấu quyền của người dùng.
//

import SwiftUI

enum EntitlementCategory: Int, CaseIterable {
    case appGroups
    case icloud
    case push
    case payment
    case network
    case media
    case hardware
    case security
    case dev
    case other

    var title: String {
        switch self {
        case .appGroups: return L("App Groups & Storage")
        case .icloud: return L("iCloud")
        case .push: return L("Notifications")
        case .payment: return L("Payments & Purchases")
        case .network: return L("Network & VPN")
        case .media: return L("Media & Playback")
        case .hardware: return L("Device & Hardware")
        case .security: return L("Security & Sandbox")
        case .dev: return L("Development & Debugging")
        case .other: return L("Other")
        }
    }

    var icon: String {
        switch self {
        case .appGroups: return "square.stack.3d.up"
        case .icloud: return "icloud"
        case .push: return "bell.badge"
        case .payment: return "creditcard"
        case .network: return "globe"
        case .media: return "play.rectangle"
        case .hardware: return "cpu"
        case .security: return "lock.shield"
        case .dev: return "hammer"
        case .other: return "ellipsis.circle"
        }
    }
}

struct EntitlementInfo {
    let key: String
    let title: String
    let detail: String
    let category: EntitlementCategory
}

enum EntitlementCatalog {
    /// Tra cứu một khoá entitlement. Không có trong danh mục thì tự dựng mục "Khác".
    static func info(for key: String) -> EntitlementInfo {
        if let entry = table[key] {
            return EntitlementInfo(key: key, title: L(entry.0), detail: L(entry.1), category: entry.2)
        }
        // Lấy đoạn cuối làm tên tạm, ví dụ com.apple.developer.foo -> foo
        let fallback = key.split(separator: ".").last.map(String.init) ?? key
        return EntitlementInfo(key: key, title: fallback, detail: "", category: .other)
    }

    /// Khoá đã có trong danh mục?
    static func isKnown(_ key: String) -> Bool { table[key] != nil }

    /// Mọi khoá thuộc một nhóm, theo đúng thứ tự khai báo trong bảng.
    static func keys(in category: EntitlementCategory) -> [String] {
        order.filter { table[$0]?.2 == category }
    }

    private static let table: [String: (String, String, EntitlementCategory)] = [
        "application-identifier": ("App ID", "Định danh đầy đủ của ứng dụng (Team ID + bundle).", .appGroups),
        "com.apple.developer.team-identifier": ("Team ID", "Mã đội ngũ phát triển cấp chứng chỉ.", .appGroups),
        "keychain-access-groups": ("Keychain sharing", "Dùng chung mục Keychain giữa các app cùng đội.", .appGroups),
        "com.apple.security.application-groups": ("App Groups", "Chia sẻ tệp và UserDefaults giữa app và extension.", .appGroups),
        "com.apple.developer.default-data-protection": ("Data protection", "Mức mã hoá tệp khi thiết bị khoá.", .appGroups),
        "com.apple.developer.group-session": ("Group activities", "SharePlay qua FaceTime.", .appGroups),
        "com.apple.developer.icloud-container-identifiers": ("iCloud containers", "Kho iCloud riêng của ứng dụng.", .icloud),
        "com.apple.developer.icloud-services": ("iCloud services", "CloudKit / CloudDocuments.", .icloud),
        "com.apple.developer.ubiquity-kvstore-identifier": ("iCloud key-value store", "Đồng bộ thiết lập nhỏ qua iCloud.", .icloud),
        "com.apple.developer.ubiquity-container-identifiers": ("iCloud documents", "Thư mục tài liệu đồng bộ iCloud.", .icloud),
        "aps-environment": ("Push notifications", "Môi trường APNs: development hoặc production.", .push),
        "com.apple.developer.usernotifications.filtering": ("Notification filtering", "Sửa nội dung thông báo trước khi hiện.", .push),
        "com.apple.developer.usernotifications.time-sensitive": ("Time sensitive alerts", "Vượt qua chế độ Không làm phiền.", .push),
        "com.apple.developer.usernotifications.communication": ("Communication notifications", "Thông báo kiểu tin nhắn có ảnh người gửi.", .push),
        "com.apple.developer.in-app-payments": ("Apple Pay", "Nhận thanh toán qua Apple Pay.", .payment),
        "com.apple.developer.payment-pass-provisioning": ("Payment pass", "Thêm thẻ vào Wallet.", .payment),
        "com.apple.developer.pass-type-identifiers": ("Wallet passes", "Quản lý vé / thẻ trong Wallet.", .payment),
        "com.apple.developer.storekit.external-purchase": ("External purchase", "Thanh toán ngoài hệ thống Apple.", .payment),
        "com.apple.developer.storekit.external-purchase-link": ("External purchase link", "Hiện liên kết thanh toán bên ngoài.", .payment),
        "com.apple.developer.networking.networkextension": ("Network extension", "VPN, lọc nội dung, DNS proxy, Hotspot Helper.", .network),
        "com.apple.developer.networking.vpn.api": ("Personal VPN", "Tạo và điều khiển cấu hình VPN cá nhân.", .network),
        "com.apple.developer.networking.HotspotConfiguration": ("Hotspot configuration", "Thêm hoặc gỡ cấu hình WiFi.", .network),
        "com.apple.developer.networking.wifi-info": ("WiFi information", "Đọc SSID / BSSID của kết nối hiện tại.", .network),
        "com.apple.developer.networking.multipath": ("Multipath TCP", "Dùng đồng thời di động và WiFi.", .network),
        "com.apple.developer.networking.custom-protocol": ("Custom network protocol", "Giao thức mạng riêng qua DriverKit.", .network),
        "com.apple.developer.networking.slicing.appcategory": ("Network slicing", "Xếp loại lưu lượng cho 5G Network Slicing.", .network),
        "com.apple.developer.associated-domains": ("Associated domains", "Universal Links và tự điền mật khẩu theo tên miền.", .network),
        "com.apple.external-accessory.wireless-configuration": ("Wireless accessory setup", "Đưa phụ kiện MFi vào mạng WiFi.", .network),
        "com.apple.developer.avfoundation.multitasking-camera-access": ("Multitasking camera", "Dùng camera khi đang chia đôi màn hình.", .media),
        "com.apple.developer.coremedia.hls.low-latency": ("Low latency HLS", "Phát trực tiếp HLS độ trễ thấp.", .media),
        "com.apple.developer.avfoundation.video-conferencing": ("Video conferencing", "Ưu tiên camera và micro cho cuộc gọi.", .media),
        "com.apple.developer.airplay.receiver": ("AirPlay receiver", "Nhận luồng phát từ thiết bị khác.", .media),
        "com.apple.developer.nfc.readersession.formats": ("NFC reading", "Đọc thẻ NFC và NDEF.", .hardware),
        "com.apple.developer.healthkit": ("HealthKit", "Đọc và ghi dữ liệu sức khoẻ.", .hardware),
        "com.apple.developer.homekit": ("HomeKit", "Điều khiển thiết bị nhà thông minh.", .hardware),
        "com.apple.developer.siri": ("Siri", "Nhận lệnh thoại qua SiriKit.", .hardware),
        "com.apple.developer.carplay-audio": ("CarPlay audio", "Ứng dụng âm thanh trên CarPlay.", .hardware),
        "com.apple.developer.devicecheck.appattest-environment": ("App Attest", "Xác thực tính toàn vẹn của ứng dụng.", .hardware),
        "com.apple.developer.driverkit": ("DriverKit", "Driver chạy ở user-space.", .hardware),
        "com.apple.developer.driverkit.transport.usb": ("DriverKit USB", "Driver thiết bị USB.", .hardware),
        "com.apple.developer.driverkit.transport.hid": ("DriverKit HID", "Driver thiết bị nhập HID.", .hardware),
        "com.apple.external-accessory.protocols": ("External accessory", "Giao tiếp với phụ kiện MFi.", .hardware),
        "com.apple.developer.endpoint-security.client": ("Endpoint security", "Giám sát sự kiện hệ thống (macOS).", .security),
        "com.apple.security.app-sandbox": ("App Sandbox", "Chạy trong hộp cát (macOS).", .security),
        "com.apple.security.network.client": ("Sandbox network client", "Cho phép kết nối ra ngoài trong hộp cát.", .security),
        "com.apple.security.network.server": ("Sandbox network server", "Cho phép mở cổng lắng nghe trong hộp cát.", .security),
        "com.apple.developer.system-extension.install": ("System extension", "Cài extension hệ thống ở user-space (macOS).", .security),
        "com.apple.developer.kernel.increased-memory-limit": ("Increased memory limit", "Dùng RAM vượt mức mặc định.", .security),
        "com.apple.developer.kernel.extended-virtual-addressing": ("Extended addressing", "Không gian địa chỉ ảo lớn hơn.", .security),
        "com.apple.developer.web-browser": ("Default browser", "Đăng ký làm trình duyệt mặc định.", .security),
        "com.apple.developer.applesignin": ("Sign in with Apple", "Dùng tài khoản Apple để đăng nhập.", .security),
        "get-task-allow": ("Debuggable", "Chỉ có ở profile Development: cho phép lldb / Xcode gắn vào.", .dev),
        "com.apple.private.security.no-container": ("No container", "Thoát khỏi thư mục sandbox riêng.", .dev),
        "com.apple.developer.on-demand-install-capable": ("App Clip", "Ứng dụng cài theo yêu cầu.", .dev),
        "beta-reports-active": ("TestFlight", "Gửi báo cáo bản beta.", .dev),
    ]

    /// Thứ tự hiển thị trong mỗi nhóm.
    private static let order: [String] = [
        "application-identifier",
        "com.apple.developer.team-identifier",
        "keychain-access-groups",
        "com.apple.security.application-groups",
        "com.apple.developer.default-data-protection",
        "com.apple.developer.group-session",
        "com.apple.developer.icloud-container-identifiers",
        "com.apple.developer.icloud-services",
        "com.apple.developer.ubiquity-kvstore-identifier",
        "com.apple.developer.ubiquity-container-identifiers",
        "aps-environment",
        "com.apple.developer.usernotifications.filtering",
        "com.apple.developer.usernotifications.time-sensitive",
        "com.apple.developer.usernotifications.communication",
        "com.apple.developer.in-app-payments",
        "com.apple.developer.payment-pass-provisioning",
        "com.apple.developer.pass-type-identifiers",
        "com.apple.developer.storekit.external-purchase",
        "com.apple.developer.storekit.external-purchase-link",
        "com.apple.developer.networking.networkextension",
        "com.apple.developer.networking.vpn.api",
        "com.apple.developer.networking.HotspotConfiguration",
        "com.apple.developer.networking.wifi-info",
        "com.apple.developer.networking.multipath",
        "com.apple.developer.networking.custom-protocol",
        "com.apple.developer.networking.slicing.appcategory",
        "com.apple.developer.associated-domains",
        "com.apple.external-accessory.wireless-configuration",
        "com.apple.developer.avfoundation.multitasking-camera-access",
        "com.apple.developer.coremedia.hls.low-latency",
        "com.apple.developer.avfoundation.video-conferencing",
        "com.apple.developer.airplay.receiver",
        "com.apple.developer.nfc.readersession.formats",
        "com.apple.developer.healthkit",
        "com.apple.developer.homekit",
        "com.apple.developer.siri",
        "com.apple.developer.carplay-audio",
        "com.apple.developer.devicecheck.appattest-environment",
        "com.apple.developer.driverkit",
        "com.apple.developer.driverkit.transport.usb",
        "com.apple.developer.driverkit.transport.hid",
        "com.apple.external-accessory.protocols",
        "com.apple.developer.endpoint-security.client",
        "com.apple.security.app-sandbox",
        "com.apple.security.network.client",
        "com.apple.security.network.server",
        "com.apple.developer.system-extension.install",
        "com.apple.developer.kernel.increased-memory-limit",
        "com.apple.developer.kernel.extended-virtual-addressing",
        "com.apple.developer.web-browser",
        "com.apple.developer.applesignin",
        "get-task-allow",
        "com.apple.private.security.no-container",
        "com.apple.developer.on-demand-install-capable",
        "beta-reports-active",
    ]
}
