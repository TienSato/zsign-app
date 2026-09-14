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

    /// Nền toàn màn hình. Thay cho systemGroupedBackground xám của Form/List.
    static let canvas = dynamic(light: 0xF5F3F0, dark: 0x0E0E10)

    /// Nền thẻ nổi trên canvas.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1A1A1C)

    /// Nền phụ bên trong thẻ (ô icon, vùng nhấn mạnh).
    static let cardAlt = dynamic(light: 0xF2F0ED, dark: 0x252528)

    /// Chữ chính — lấy đúng sắc than chì của logo.
    static let ink = dynamic(light: 0x1C1C1E, dark: 0xF2F2F4)

    /// Chữ phụ.
    static let ink2 = dynamic(light: 0x6E6E73, dark: 0x9A9AA0)

    /// Chữ mờ nhất (chú thích, mã kỹ thuật).
    static let ink3 = dynamic(light: 0xA1A1A6, dark: 0x6A6A70)

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
        /// Bo góc ô icon vuông trong hàng.
        static let iconRadius: CGFloat = 9
        /// Lề trái phải của toàn màn hình.
        static let screenPadding: CGFloat = 16
        /// Khoảng cách giữa các thẻ.
        static let cardSpacing: CGFloat = 14
        /// Padding bên trong thẻ.
        static let cardPadding: CGFloat = 16
        /// Cạnh ô icon trong hàng.
        static let iconBox: CGFloat = 32
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
