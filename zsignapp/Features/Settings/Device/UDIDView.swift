//
//  UDIDView.swift
//  zsignapp

import SwiftUI
import UIKit

struct UDIDRow: View {
    @State private var udid: String? = nil
    @State private var copied = false

    var body: some View {
        Button(action: copyUDID) {
            CardRow(
                icon: "iphone.gen3",
                title: L("This Device's UDID"),
                subtitle: udid ?? L("Could not read the UDID (the app must be signed per device)")
            ) {
                if udid != nil {
                    if copied {
                        Text("Copied!")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.footnote)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(udid == nil)
        .onAppear { udid = UDIDReader.deviceUDID() }
    }

    private func copyUDID() {
        guard let udid else { return }
        UIPasteboard.general.string = udid
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}

struct DeviceInfoRow: View {
    @ObservedObject private var theme = DeviceThemeManager.shared

    var body: some View {
        CardRow(
            icon: "circle.fill",
            title: L("Device"),
            subtitle: deviceLine,
            iconTint: theme.accent
        )
    }

    private var deviceLine: String {
        var parts: [String] = []
        if !theme.deviceName.isEmpty { parts.append(theme.deviceName) }
        if let finish = theme.finish, !finish.isEmpty { parts.append(finish) }
        return parts.isEmpty ? DeviceInfo.modelIdentifier : parts.joined(separator: " · ")
    }
}
