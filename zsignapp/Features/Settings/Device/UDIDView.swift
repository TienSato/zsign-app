//
//  UDIDView.swift
//  zsignapp
//
//  Hàng UDID gọn cho Form — CHẠM để copy, hiện "Copied!" 1.5s (kèm haptic).
//

import SwiftUI
import UIKit

struct UDIDRow: View {
    @State private var udid: String? = nil
    @State private var copied = false

    var body: some View {
        Button(action: copyUDID) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("This Device's UDID")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.primary)
                    if let udid = udid {
                        Text(udid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Could not read the UDID (the app must be signed per device)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if udid != nil {
                    if copied {
                        Text("Copied!")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.green)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(udid == nil)
        .onAppear { udid = UDIDReader.deviceUDID() }
    }

    private func copyUDID() {
        guard let udid = udid else { return }
        UIPasteboard.general.string = udid
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}


// Hàng thông tin máy (tên máy + màu) — màu chấm theo màu chủ đạo.
struct DeviceInfoRow: View {
    @ObservedObject private var theme = DeviceThemeManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.title3)
                .foregroundColor(theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Device")
                    .font(.subheadline).fontWeight(.medium)
                Text(deviceLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var deviceLine: String {
        var parts: [String] = []
        if !theme.deviceName.isEmpty { parts.append(theme.deviceName) }
        if let f = theme.finish, !f.isEmpty { parts.append(f) }
        if parts.isEmpty { return DeviceInfo.modelIdentifier }
        return parts.joined(separator: " · ")
    }
}
