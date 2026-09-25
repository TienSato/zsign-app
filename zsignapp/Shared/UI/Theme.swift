//
//  Theme.swift
//  zsignapp

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Màu

    static let canvas = dynamic(light: 0xF5F3F0, dark: 0x1A1917)

    static let card = dynamic(light: 0xFFFFFF, dark: 0x262523)

    static let cardAlt = dynamic(light: 0xF2F0ED, dark: 0x312F2C)

    static let ink = dynamic(light: 0x1C1C1E, dark: 0xF2F0ED)

    static let ink2 = dynamic(light: 0x6E6E73, dark: 0xA5A19C)

    static let ink3 = dynamic(light: 0xA1A1A6, dark: 0x716D68)

    static var hairline: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.10)
            : UIColor(white: 0, alpha: 0.07) })
    }

    static var cardShadow: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.45)
            : UIColor(white: 0, alpha: 0.05) })
    }

    // MARK: - Số đo

    enum Metric {
        static let cardRadius: CGFloat = 20
        static let iconSize: CGFloat = 18
        static let screenPadding: CGFloat = 16
        static let cardSpacing: CGFloat = 14
        static let cardPadding: CGFloat = 16
        static let iconBox: CGFloat = 26
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
    func screenChrome(_ title: LocalizedStringKey, large: Bool = false) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func canvasBackground() -> some View {
        self.background(Theme.canvas.ignoresSafeArea())
    }

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
