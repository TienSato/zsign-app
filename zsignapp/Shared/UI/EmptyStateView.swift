//
//  EmptyStateView.swift
//  zsignapp
//  View "không có dữ liệu" dùng chung cho toàn app.
//  iOS 17+ dùng ContentUnavailableView của hệ thống, iOS 16 dùng fallback thủ công.
//

import SwiftUI

struct EmptyStateView<Actions: View>: View {
    /// standard: icon xám, tiêu đề .headline, chiếm hết khung.
    /// compact: icon .secondary, tiêu đề .title2 semibold, chỉ padding.
    enum Style {
        case standard
        case compact
    }

    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    var style: Style = .standard
    /// Nút hành động đặt ngay dưới phần mô tả. Bỏ trống thì không có gì.
    @ViewBuilder var actions: Actions

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                actions
            }
        } else {
            VStack(spacing: 16) {
                fallback
                actions
            }
        }
    }

    @ViewBuilder
    private var fallback: some View {
        switch style {
        case .standard:
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 60))
                    .foregroundColor(.gray)

                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .compact:
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

// Cách gọi rút gọn khi không có nút hành động — giữ nguyên mọi nơi gọi cũ.
extension EmptyStateView where Actions == EmptyView {
    init(title: LocalizedStringKey,
         systemImage: String,
         message: LocalizedStringKey,
         style: Style = .standard) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.style = style
        self.actions = EmptyView()
    }
}
