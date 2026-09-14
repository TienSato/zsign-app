//
//  SignLogViews.swift
//  zsignapp
//  Overlay log realtime (trong màn hình ký) + trình xem log (trong Cài đặt).
//
//  Bảng nổi giữ nguyên tính chất "đè lên màn hình ký" cùng nút thu gọn / đóng;
//  chỉ đổi màu sang bảng màu chung (Theme) thay cho màu mặc định của hệ thống.
//  Nội dung nhật ký vẫn là chữ monospaced, gạch đầu dòng theo từng dòng log.
//

import SwiftUI
import UIKit

// MARK: - Overlay realtime, đè lên màn hình ký

struct SignLogOverlay: View {
    @Binding var present: Bool
    @ObservedObject private var logger = SignLogger.shared
    @State private var expanded = true

    var body: some View {
        VStack {
            Spacer()
            if expanded {
                panel
            } else {
                collapsedPill
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    private var panel: some View {
        VStack(spacing: 0) {

            // Thanh tiêu đề: tên bảng, số dòng, và các nút thao tác.
            HStack(spacing: 12) {
                Text("Signing Log")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)

                Text("\(logger.lines.count)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)

                Spacer()

                Button("Copy") { UIPasteboard.general.string = logger.fullText }
                    .font(.caption)

                Button("Clear") { logger.clear() }
                    .font(.caption)

                Button { expanded = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                }

                Button { present = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .tint(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logger.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: logger.lines.count) { _ in
                    guard !logger.lines.isEmpty else { return }
                    withAnimation { proxy.scrollTo(logger.lines.count - 1, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: 340)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: Theme.cardShadow, radius: 12, y: 4)
        .padding(12)
    }

    private var collapsedPill: some View {
        HStack {
            Spacer()
            Button { expanded = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.plaintext")
                    Text(L("Log") + " (\(logger.lines.count))")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                .shadow(color: Theme.cardShadow, radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

// MARK: - Trình xem log (Cài đặt → Nâng cao → Nhật ký)

struct SignLogViewerView: View {
    @ObservedObject private var logger = SignLogger.shared

    var body: some View {
        Group {
            if logger.lines.isEmpty {
                EmptyStateView(
                    title: "No log yet",
                    systemImage: "doc.plaintext",
                    message: "Turn on the log and sign an app; the log will appear here.",
                    style: .compact
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logger.lines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                        .cardStyle(padding: 14)
                        .padding(.horizontal, Theme.Metric.screenPadding)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        if !logger.lines.isEmpty {
                            proxy.scrollTo(logger.lines.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .screenChrome("Log")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    UIPasteboard.general.string = logger.fullText
                } label: { Image(systemName: "doc.on.doc") }
                .disabled(logger.lines.isEmpty)

                Button(role: .destructive) {
                    logger.clear()
                } label: { Image(systemName: "trash") }
                .disabled(logger.lines.isEmpty)
            }
        }
    }
}
