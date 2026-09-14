//
//  DynamicIslandHeader.swift
//  zsignapp
//  Badge thương hiệu kiểu LCSign: đặt trong 1 UIWindow riêng ở NGAY DƯỚI lớp
//  Dynamic Island (windowLevel = .statusBar - 1). Lúc dùng thật bị DI che khuất
//  (gần như không thấy); khi CHỤP MÀN HÌNH badge lộ ra như branding trên DI.
//  Badge canh giữa + đúng số đo DI (126 x 37.33, đỉnh 11.33) nên tự khớp mọi máy.
//

import SwiftUI
import UIKit

enum DeviceScreen {
    static var topSafeInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.safeAreaInsets.top ?? 0
    }
    static var hasDynamicIsland: Bool { topSafeInset >= 55 }
    static var hasNotch: Bool { topSafeInset >= 30 }
}

// MARK: - Badge view (nhỏ, nấp đúng vị trí DI)

struct IslandBadgeView: View {
    var tint: Color
    var background: Color = .black
    var foreground: Color = .white
    var title: String = "zSign"
    var iconAsset: String = "IconPreviewDefault"

    private let diWidth: CGFloat = 126
    private let diHeight: CGFloat = 37.33
    private let diTop: CGFloat = 11.33

    var body: some View {
        let hasDI = DeviceScreen.hasDynamicIsland
        let w: CGFloat = hasDI ? diWidth : 120
        let h: CGFloat = hasDI ? diHeight : 34
        let top: CGFloat = hasDI ? diTop : max(DeviceScreen.topSafeInset - h - 4, 6)

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(iconAsset)
                    .resizable().scaledToFit()
                    .frame(width: h - 17, height: h - 17)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            }
            .frame(width: w, height: h)
            .background(Capsule(style: .continuous).fill(background))
            .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.65), lineWidth: 1))
            .frame(maxWidth: .infinity)   // căn giữa == căn theo DI
            .padding(.top, top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Window đặt badge dưới lớp DI

final class IslandBadgeWindow: UIWindow {
    private let host = UIHostingController(rootView: AnyView(EmptyView()))

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .statusBar - 1          // dưới DI/status bar
        backgroundColor = .clear
        isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        rootViewController = host
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func render(tint: UIColor, background: UIColor, foreground: UIColor, title: String) {
        host.rootView = AnyView(IslandBadgeView(tint: Color(tint), background: Color(background), foreground: Color(foreground), title: title))
        isHidden = false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil } // xuyên chạm
}

// MARK: - Controller bật/tắt + cập nhật màu

@MainActor
final class IslandBadgeController {
    static let shared = IslandBadgeController()
    private var window: IslandBadgeWindow?
    private let title = "zSign"

    func apply(enabled: Bool) {
        guard enabled else {
            window?.isHidden = true
            window = nil
            return
        }
        let tint = UIColor(AppearanceManager.shared.effectiveAccent(deviceAccent: DeviceThemeManager.shared.accent))
        let bg = UIColor.systemBackground
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        bg.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        let fg: UIColor = lum > 0.6 ? .black : .white
        if window == nil {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
            window = IslandBadgeWindow(windowScene: scene)
        }
        window?.render(tint: tint, background: bg, foreground: fg, title: title)
    }
}
