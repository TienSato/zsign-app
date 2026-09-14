//
//  AppearanceSettingsView.swift
//  zsignapp
//  Cài đặt → Giao diện: màu chủ đạo, sáng/tối, ngôn ngữ và biểu tượng ứng dụng.
//  Dựng bằng bộ thẻ dùng chung (Theme + CardComponents) thay cho Form.
//

import SwiftUI
import UIKit

struct AppearanceSettingsView: View {
    @StateObject private var appearance = AppearanceManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @EnvironmentObject private var deviceTheme: DeviceThemeManager

    private var effective: Color {
        appearance.effectiveAccent(deviceAccent: deviceTheme.accent)
    }

    var body: some View {
        CardScreen {
            previewCard
            languageGroup
            accentGroup
            schemeGroup
            iconGroup
        }
        .screenChrome("Appearance")
    }

    // MARK: - Xem trước

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(effective)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "signature")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("zsignapp")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("Accent color preview")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 8)
            }

            FilledButton(title: L("Sample Button"), tint: effective) { }
                .allowsHitTesting(false)
        }
        .cardStyle()
    }

    // MARK: - Ngôn ngữ

    private var languageGroup: some View {
        CardGroup {
            NavigationLink {
                LanguageSettingsView()
            } label: {
                CardRow(icon: "globe", title: L("Language")) {
                    HStack(spacing: 6) {
                        Text(loc.language.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                        CardChevron()
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Màu chủ đạo

    private var accentGroup: some View {
        CardGroup(L("Accent Color"),
                  footnote: L("Applies to buttons, tabs and highlights across the app.")) {
            Picker(L("Color source"), selection: $appearance.mode) {
                ForEach(AccentMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)

            CardDivider(inset: Theme.Metric.cardPadding)

            switch appearance.mode {
            case .auto:
                CardRow(icon: "iphone",
                        title: L("Follow device color"),
                        subtitle: deviceTheme.deviceName.isEmpty
                            ? L("Detecting device...")
                            : deviceTheme.deviceName) {
                    Circle()
                        .fill(deviceTheme.accent)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                }
            case .preset:
                swatchGrid
            case .custom:
                CardRow(icon: "eyedropper", title: L("Pick any color")) {
                    ColorPicker("", selection: $appearance.customColor, supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }

    private var swatchGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 16) {
            ForEach(AppearanceManager.presets.indices, id: \.self) { i in
                let c = AppearanceManager.presets[i].color
                Circle()
                    .fill(c)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(appearance.presetIndex == i ? 0.9 : 0), lineWidth: 2)
                            .padding(-4)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(appearance.presetIndex == i ? 1 : 0)
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) { appearance.presetIndex = i }
                    }
            }
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 16)
    }

    // MARK: - Sáng / Tối

    private var schemeGroup: some View {
        CardGroup(L("Light & Dark")) {
            Picker(L("Mode"), selection: $appearance.appScheme) {
                ForEach(AppColorScheme.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Biểu tượng ứng dụng

    private var iconGroup: some View {
        CardGroup(L("App Icon"),
                  footnote: L("Changes the icon on the Home Screen. iOS shows a confirmation when it changes.")) {
            AppIconPicker()
        }
    }
}

// MARK: - Chọn icon app (alternate app icons)

private struct IconOption: Identifiable {
    let id: String          // tên alternate icon; "" = mặc định
    let display: String
    let preview: String     // tên imageset preview
    var altName: String? { id.isEmpty ? nil : id }
}

struct AppIconPicker: View {
    private static let options: [IconOption] = [
        IconOption(id: "",            display: L("Default"),  preview: "IconPreviewDefault"),
        IconOption(id: "IconWhite",   display: L("White Background"), preview: "IconPreviewMono"),
    ]

    @State private var current: String = UIApplication.shared.alternateIconName ?? ""
    @State private var errorText: String?
    @State private var isChanging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Self.options) { opt in
                        Button {
                            setIcon(opt)
                        } label: {
                            VStack(spacing: 7) {
                                Image(opt.preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 62, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(current == opt.id ? Color.accentColor : Theme.hairline,
                                                          lineWidth: current == opt.id ? 3 : 1)
                                    )
                                Text(opt.display)
                                    .font(.caption2)
                                    .foregroundStyle(current == opt.id ? Theme.ink : Theme.ink2)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isChanging)
                        .opacity(isChanging && current != opt.id ? 0.45 : 1)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, Theme.Metric.cardPadding)
            }

            VStack(alignment: .leading, spacing: 6) {
                if isChanging {
                    Text("Changing icon...")
                        .font(.caption).foregroundStyle(Theme.ink2)
                }
                if let e = errorText {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
                if !UIApplication.shared.supportsAlternateIcons {
                    Text("This device does not support alternate icons.")
                        .font(.caption).foregroundStyle(Theme.ink2)
                }
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
        }
        .padding(.vertical, 10)
        .onAppear { syncCurrent() }
    }

    /// Đồng bộ lại trạng thái hiển thị theo icon thật của hệ thống.
    private func syncCurrent() {
        current = UIApplication.shared.alternateIconName ?? ""
    }

    private func setIcon(_ opt: IconOption) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard !isChanging else { return }          // chặn gọi chồng
        syncCurrent()
        guard current != opt.id else { return }    // đã là icon này rồi

        isChanging = true
        errorText = nil

        // QUAN TRỌNG: phải async trên main queue. Gọi thẳng trong action của SwiftUI
        // thì iOS hay bỏ qua im lặng từ lần đổi thứ hai trở đi.
        DispatchQueue.main.async {
            UIApplication.shared.setAlternateIconName(opt.altName) { err in
                DispatchQueue.main.async {
                    if let err = err {
                        errorText = err.localizedDescription
                    }
                    syncCurrent()
                    isChanging = false
                }
            }
        }

        // Lưới an toàn: nếu completion không bao giờ bắn, vẫn nhả khoá + đồng bộ lại.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            syncCurrent()
            isChanging = false
        }
    }
}
