//
//  ProgressOverlay.swift
//  zsignapp

import SwiftUI

struct ProgressOverlay: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var step: String? = nil
    var progress: Double? = nil
    var trailingLabel: String? = nil

    @State private var beat = false

    private let iconSize: CGFloat = 78
    private let barWidth: CGFloat = 220

    var body: some View {
        ZStack {
            // Phủ ĐÚNG màu nền của app và chặn mọi thao tác chạm.
            //
            // Trước đây dùng .ultraThinMaterial: vật liệu mờ đặt trên nền
            // Theme.canvas cho ra một sắc NHẠT HƠN canvas, trong khi thanh
            // điều hướng phía trên vẫn là canvas nguyên bản -> lộ một đường
            // ranh ngang ngay dưới thanh tiêu đề, nhìn như hai mảnh rời.
            // Dùng thẳng Theme.canvas thì khớp tuyệt đối ở mọi màn, cả sáng
            // lẫn tối.
            Theme.canvas
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            VStack(spacing: 26) {
                icon
                labels
                if let progress {
                    progressBar(progress)
                }
            }
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    // MARK: - Icon đập theo nhịp

    private var icon: some View {
        Image("IconPreviewDefault")
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .scaleEffect(beat ? 1.08 : 0.94)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    beat = true
                }
            }
    }

    // MARK: - Chữ

    private var labels: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let step, !step.isEmpty {
                Text(step)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Thanh tiến trình

    private func progressBar(_ value: Double) -> some View {
        let clamped = min(max(value, 0), 1)

        return VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 5)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: barWidth * clamped, height: 5)
                    .animation(.linear(duration: 0.3), value: clamped)
            }
            .frame(width: barWidth)

            HStack {
                if let trailingLabel, !trailingLabel.isEmpty {
                    Text(trailingLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(Int(clamped * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: barWidth)
        }
    }
}
