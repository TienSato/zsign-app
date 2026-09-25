//
//  LanguagePickerView.swift
//  zsignapp

import SwiftUI

// MARK: - Hàng chọn ngôn ngữ (dùng chung)

private struct LanguageRow: View {
    let language: AppLanguage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(language.flag)
                .font(.system(size: 22))
                .frame(width: Theme.Metric.iconBox, alignment: .center)
            Text(language.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.Metric.rowHeight)
        // Hai dòng dưới BẮT BUỘC giữ: thiếu là hàng không bấm được.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Trong Cài đặt

struct LanguageSettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        CardScreen {
            CardGroup(footnote: L("The app switches language immediately. Choosing Follow System uses your device language.")) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { idx, lang in
                    Button {
                        loc.language = lang
                    } label: {
                        LanguageRow(language: lang, isSelected: loc.language == lang)
                    }
                    .buttonStyle(.plain)

                    if idx < AppLanguage.allCases.count - 1 {
                        CardDivider()
                    }
                }
            }
        }
        .screenChrome("Language")
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
                .foregroundStyle(Theme.ink)
                .padding(.top, 18)

            Text("You can change this later in Settings.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
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
                        CardDivider()
                    }
                }
            }
            .cardStyle(padding: 0)
            .padding(.horizontal, 20)
            .padding(.top, 26)

            Spacer()

            FilledButton(title: L("Continue")) {
                loc.language = selection
                loc.hasChosen = true
                onDone()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }
}
