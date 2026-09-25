//
//  IslandBadge.swift
//  zsignapp

import SwiftUI
import UIKit

struct IslandBadgeView: View {
    var tint: Color
    var background: Color = .black
    var foreground: Color = .white
    var title: String = "zSign"
    var iconAsset: String = "IconPreviewDefault"

    private let diWidth: CGFloat = 126
    private let diHeight: CGFloat = 37.33
    private let diTop: CGFloat = 11.33

  
    private let diScale: CGFloat = 0.86

    var body: some View {
        // Chỉ dựng cho máy CÓ Dynamic Island — controller đã chặn từ ngoài,
        // nên ở đây luôn dùng số đo của DI, không còn nhánh tai thỏ.
        let w = diWidth * diScale
        let h = diHeight * diScale
        let top = diTop + (diHeight - h) / 2   // giữ badge đúng tâm vùng DI

        let iconSize = h * 0.60
        let fontSize = h * 0.34

        VStack(spacing: 0) {
            HStack(spacing: h * 0.15) {
                Image(iconAsset)
                    .resizable().scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.28, style: .continuous))
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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


final class IslandBadgeWindow: UIWindow {
    private let host = UIHostingController(rootView: AnyView(EmptyView()))

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .statusBar - 1
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

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}


@MainActor
final class IslandBadgeController {
    static let shared = IslandBadgeController()
    private var window: IslandBadgeWindow?
    private let title = "zSign"

    func apply(enabled: Bool) {
        // Máy không có Dynamic Island thì badge sẽ lộ hẳn ra màn hình chứ
        // không nấp được sau đâu cả -> không dựng cửa sổ nào.
        guard enabled, DeviceInfo.hasDynamicIsland else {
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
