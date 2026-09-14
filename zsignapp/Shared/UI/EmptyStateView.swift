//
//  EmptyStateView.swift
//  zsignapp
//  View "không có dữ liệu" dùng chung cho toàn app.
//  iOS 17+ dùng ContentUnavailableView của hệ thống, iOS 16 dùng fallback thủ công.
//

import SwiftUI

struct EmptyStateView: View {
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

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(message)
            )
        } else {
            fallback
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
