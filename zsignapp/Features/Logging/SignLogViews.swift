//
//  SignLogViews.swift
//  zsignapp
//  Overlay log realtime (trong màn hình ký) + trình xem log (trong Cài đặt).
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
            HStack(spacing: 12) {
                Text("Signing Log")
                    .font(.caption).bold()
                Text("\(logger.lines.count)")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button("Copy") { UIPasteboard.general.string = logger.fullText }
                    .font(.caption)
                Button("Clear") { logger.clear() }
                    .font(.caption)
                Button { expanded = false } label: {
                    Image(systemName: "chevron.down")
                }
                Button { present = false } label: {
                    Image(systemName: "xmark")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logger.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: logger.lines.count) { _ in
                    guard !logger.lines.isEmpty else { return }
                    withAnimation { proxy.scrollTo(logger.lines.count - 1, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25)))
        .padding(12)
        .shadow(radius: 8)
    }

    private var collapsedPill: some View {
        HStack {
            Spacer()
            Button { expanded = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.plaintext")
                    Text(L("Log") + " (\(logger.lines.count))")
                }
                .font(.caption).bold()
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
                .shadow(radius: 4)
            }
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
                ContentUnavailableCompat(
                    title: L("No log yet"),
                    message: L("Turn on the log and sign an app; the log will appear here.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logger.lines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                        .padding(12)
                    }
                    .onAppear {
                        if !logger.lines.isEmpty {
                            proxy.scrollTo(logger.lines.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
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

// Fallback cho ContentUnavailableView (chỉ có từ iOS 17).
private struct ContentUnavailableCompat: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.plaintext")
                .font(.largeTitle).foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
