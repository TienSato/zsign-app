//
//  LiquidGlass.swift
//  zsignapp
//
//  Thích ứng giao diện theo phiên bản iOS:
//  - iOS 26+ (build bằng Xcode 26): dùng Liquid Glass thật (.glassEffect).
//  - iOS cũ HOẶC build bằng Xcode < 26: fallback nền vật liệu mờ (.ultraThinMaterial).
//
//  Ghi chú: phần LỚN Liquid Glass là TỰ ĐỘNG khi build bằng Xcode 26 SDK
//  (NavigationBar/TabBar/Form/List/Sheet/Button... tự có glass trên iOS 26,
//   giữ nguyên trên iOS < 26). Helper này chỉ dành cho các bề mặt NỔI tự vẽ.
//

import SwiftUI

extension View {
    /// Áp Liquid Glass nếu chạy iOS 26 (và được build bằng Xcode 26); nếu không -> vật liệu mờ.
    @ViewBuilder
    func adaptiveGlass(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint = tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
        #else
        self.background(shape.fill(.ultraThinMaterial))
        #endif
    }

    /// true nếu thiết bị đang chạy iOS 26 trở lên (dùng để bật/tắt UI phụ thuộc phiên bản).
    var isLiquidGlassOS: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
