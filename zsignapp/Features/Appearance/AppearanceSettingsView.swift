//
//  AppearanceSettingsView.swift
//  zsignapp
//  Cài đặt → Giao diện: màu chủ đạo + chế độ sáng/tối. (Icon app thêm ở bước sau.)
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
        Form {
            // Xem trước
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(effective)
                            .frame(width: 46, height: 46)
                            .overlay(Image(systemName: "signature").foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("zsignapp").font(.headline)
                            Text("Accent color preview").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button { } label: {
                        Text("Sample Button").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(effective)
                    .allowsHitTesting(false)
                }
                .padding(.vertical, 4)
            }

            // Ngôn ngữ
            Section {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text(loc.language.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Màu chủ đạo
            Section {
                Picker("Color source", selection: $appearance.mode) {
                    ForEach(AccentMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch appearance.mode {
                case .auto:
                    HStack(spacing: 12) {
                        Circle().fill(deviceTheme.accent).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Follow device color")
                            Text(deviceTheme.deviceName.isEmpty ? L("Detecting device...") : deviceTheme.deviceName)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case .preset:
                    swatchGrid
                case .custom:
                    ColorPicker("Pick any color", selection: $appearance.customColor, supportsOpacity: false)
                }
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Applies to buttons, tabs and highlights across the app.")
            }

            // Sáng / Tối
            Section {
                Picker("Mode", selection: $appearance.appScheme) {
                    ForEach(AppColorScheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }


            // Biểu tượng ứng dụng
            Section {
                AppIconPicker()
            } header: {
                Text("App Icon")
            } footer: {
                Text("Changes the icon on the Home Screen. iOS shows a confirmation when it changes.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
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
        .padding(.vertical, 8)
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
                                            .strokeBorder(current == opt.id ? Color.accentColor : Color.primary.opacity(0.12),
                                                          lineWidth: current == opt.id ? 3 : 1)
                                    )
                                Text(opt.display)
                                    .font(.caption2)
                                    .foregroundStyle(current == opt.id ? Color.primary : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isChanging)
                        .opacity(isChanging && current != opt.id ? 0.45 : 1)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }

            if isChanging {
                Text("Changing icon...")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let e = errorText {
                Text(e).font(.caption).foregroundStyle(.red)
            }
            if !UIApplication.shared.supportsAlternateIcons {
                Text("This device does not support alternate icons.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
