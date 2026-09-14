//
//  LanguagePickerView.swift
//  zsignapp
//  Màn chọn ngôn ngữ: dùng cho cả lần đầu mở app và trong Cài đặt → Giao diện.
//

import SwiftUI

// MARK: - Hàng chọn ngôn ngữ (dùng chung)

private struct LanguageRow: View {
    let language: AppLanguage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(language.flag)
                .font(.system(size: 22))
                .frame(width: 28)
            Text(language.displayName)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Trong Cài đặt

struct LanguageSettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Form {
            Section {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        loc.language = lang
                    } label: {
                        HStack(spacing: 12) {
                            Text(lang.flag).font(.system(size: 20)).frame(width: 26)
                            Text(lang.displayName).foregroundStyle(.primary)
                            Spacer()
                            if loc.language == lang {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("The app switches language immediately. Choosing Follow System uses your device language.")
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Lần đầu mở app

struct FirstLaunchLanguageView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selection: AppLanguage = LocalizationManager.shared.language
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            Image("IconPreviewDefault")
                .resizable().scaledToFit()
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            Text("Choose Language")
                .font(.title2).bold()
                .padding(.top, 18)

            Text("You can change this later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 5)
                .padding(.horizontal, 34)

            VStack(spacing: 0) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { idx, lang in
                    Button {
                        selection = lang
                    } label: {
                        LanguageRow(language: lang, isSelected: selection == lang)
                    }
                    .buttonStyle(.plain)

                    if idx < AppLanguage.allCases.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 26)

            Spacer()

            Button {
                loc.language = selection
                loc.hasChosen = true
                onDone()
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }
}
