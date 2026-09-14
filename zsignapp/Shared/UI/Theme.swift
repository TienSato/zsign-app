//
//  Theme.swift
//  zsignapp
//
//  Bảng màu và số đo dùng chung cho toàn bộ giao diện dạng thẻ.
//
//  Gốc của bảng màu là chính icon zsign: than chì + chữ trắng, nên nền là
//  giấy ấm trung tính (không ngả hồng, không ngả xanh) để hợp với BẤT KỲ màu
//  nhấn nào người dùng chọn trong phần Giao diện.
//
//  Đổi cả tông màu app = sửa đúng file này.
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Màu

    /// Nền toàn màn hình.
    /// Sáng: giấy ấm. Tối: than chì ẤM, KHÔNG phải đen hệ thống (#000).
    /// Giữ chút hơi ấm để ăn nhập với chế độ sáng và bớt gắt mắt ban đêm.
    static let canvas = dynamic(light: 0xF5F3F0, dark: 0x1A1917)

    /// Nền thẻ nổi trên canvas — sáng hơn canvas để tự tách lớp,
    /// vì trong chế độ tối bóng đổ gần như vô hình.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x262523)

    /// Nền phụ bên trong thẻ (vùng nhấn mạnh, ô nhập liệu).
    static let cardAlt = dynamic(light: 0xF2F0ED, dark: 0x312F2C)

    /// Chữ chính — lấy đúng sắc than chì của logo.
    static let ink = dynamic(light: 0x1C1C1E, dark: 0xF2F0ED)

    /// Chữ phụ.
    static let ink2 = dynamic(light: 0x6E6E73, dark: 0xA5A19C)

    /// Chữ mờ nhất (chú thích, mã kỹ thuật).
    static let ink3 = dynamic(light: 0xA1A1A6, dark: 0x716D68)

    /// Đường kẻ mảnh giữa các hàng trong cùng một thẻ.
    static var hairline: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.10)
            : UIColor(white: 0, alpha: 0.07) })
    }

    /// Bóng đổ của thẻ — rất nhẹ, chỉ đủ tách khỏi nền.
    static var cardShadow: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.45)
            : UIColor(white: 0, alpha: 0.05) })
    }

    // MARK: - Số đo

    enum Metric {
        /// Bo góc thẻ. 20 là chỗ ngọt: mềm nhưng không thành viên thuốc.
        static let cardRadius: CGFloat = 20
        /// Cỡ glyph icon trong hàng.
        static let iconSize: CGFloat = 18
        /// Lề trái phải của toàn màn hình.
        static let screenPadding: CGFloat = 16
        /// Khoảng cách giữa các thẻ.
        static let cardSpacing: CGFloat = 14
        /// Padding bên trong thẻ.
        static let cardPadding: CGFloat = 16
        /// Bề rộng cột icon — giữ cho chữ các hàng thẳng nhau.
        static let iconBox: CGFloat = 26
        /// Chiều cao tối thiểu một hàng.
        static let rowHeight: CGFloat = 44
    }

    // MARK: - Dựng màu thích ứng sáng/tối

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(hex: dark)
            : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue:  CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Tiện ích dùng ở mọi màn hình

extension View {
    /// Khung chuẩn cho MỘT màn hình: tiêu đề gọn + thanh điều hướng cùng tông nền.
    /// Mỗi màn hình chỉ cần đúng một dòng này, không lặp lại cấu hình ở đâu khác.
    ///
    ///     CardScreen { ... }
    ///         .screenChrome("Settings")
    ///
    func screenChrome(_ title: LocalizedStringKey, large: Bool = false) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Phủ nền canvas lên toàn màn hình, thay cho nền mặc định của List/Form.
    func canvasBackground() -> some View {
        self.background(Theme.canvas.ignoresSafeArea())
    }

    /// Bọc nội dung thành một thẻ trắng bo góc.
    func cardStyle(padding: CGFloat = Theme.Metric.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .shadow(color: Theme.cardShadow, radius: 10, y: 3)
    }
}
