//
//  ProgressOverlay.swift
//  zsignapp
//
//  Hộp thoại tiến trình dùng chung cho TOÀN BỘ app: nhập IPA, ký, ký hàng loạt,
//  tự động ký & cài, kiểm tra chứng chỉ, xuất chứng chỉ...
//
//  Muốn đổi giao diện hộp thoại tiến trình ở bất kỳ đâu trong app thì SỬA
//  DUY NHẤT FILE NÀY. Các màn hình chỉ truyền nội dung vào, không tự vẽ hộp.
//
//  Cách dùng:
//      if isImporting {
//          ProgressOverlay(title: "Importing", step: L(importStep), progress: importProgress)
//      }
//
//  - progress = nil  -> chỉ xoay icon, không có thanh (việc không đo được tiến độ)
//  - progress != nil -> có thanh + phần trăm bên dưới
//

import SwiftUI

struct ProgressOverlay: View {
    /// Tiêu đề. Dùng chuỗi hằng để tự động dịch theo ngôn ngữ đang chọn.
    let title: LocalizedStringKey
    /// Dòng phụ: thường là tên app đang xử lý. Truyền chuỗi đã sẵn sàng hiển thị.
    var subtitle: String? = nil
    /// Bước hiện tại. Nếu chuỗi đến từ biến, hãy bọc L(...) trước khi truyền vào.
    var step: String? = nil
    /// 0...1. nil nghĩa là không đo được tiến độ.
    var progress: Double? = nil
    /// Nhãn phụ bên trái thanh, ví dụ "3/10".
    var trailingLabel: String? = nil

    @State private var isSpinning = false

    private let iconSize: CGFloat = 64
    private let barWidth: CGFloat = 220

    var body: some View {
        ZStack {
            backdrop
            card
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Nền

    /// Làm mờ toàn bộ màn hình phía sau và chặn mọi thao tác chạm.
    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.20))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { }   // nuốt cú chạm, không cho bấm xuyên xuống dưới
    }

    // MARK: - Thẻ nội dung

    private var card: some View {
        VStack(spacing: 18) {
            spinningIcon

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

            if let progress {
                progressBar(progress)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 320)
        .adaptiveGlass(cornerRadius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 10)
        .padding(.horizontal, 24)
    }

    // MARK: - Icon xoay

    private var spinningIcon: some View {
        ZStack {
            // quầng sáng theo màu chủ đạo người dùng chọn
            Circle()
                .fill(Color.accentColor.opacity(0.22))
                .frame(width: iconSize * 1.5, height: iconSize * 1.5)
                .blur(radius: 18)

            Image("IconPreviewDefault")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .rotation3DEffect(
                    .degrees(isSpinning ? 360 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.35
                )
        }
        .frame(height: iconSize * 1.5)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
    }

    // MARK: - Thanh tiến trình

    private func progressBar(_ value: Double) -> some View {
        let clamped = min(max(value, 0), 1)

        return VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 6)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: barWidth * clamped, height: 6)
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
