//
//  SigningAppAlternativeIconView.swift
//  zsignapp
//
//  Alternative icon picker for signing
//
//  Giao diện dạng thẻ (Theme + CardComponents). Phần đọc icon trong IPA
//  (getIconImage / loadAlternateIcons / resizeToSquare) giữ nguyên 100%.
//

import SwiftUI

// MARK: - View
struct SigningAppAlternativeIconView: View {
    @Environment(\.dismiss) var dismiss

    let app: ImportedApp
    @Binding var appIcon: UIImage?

    @State private var alternateIcons: [(name: String, path: String)] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if alternateIcons.isEmpty {
                EmptyStateView(
                    title: "No Alternative Icons",
                    systemImage: "app.dashed",
                    message: "This app doesn't have alternative icons"
                )
            } else {
                CardScreen {
                    CardGroup(L("Alternative Icons"),
                              footnote: L("Tap an icon to use it for this signing session")) {
                        ForEach(alternateIcons, id: \.name) { icon in
                            if alternateIcons.first?.name != icon.name {
                                CardDivider()
                            }
                            Button {
                                selectIcon(icon)
                            } label: {
                                AlternativeIconRow(
                                    icon: icon,
                                    app: app
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .screenChrome("Alternative Icons")
        .onAppear {
            loadAlternateIcons()
        }
    }

    // MARK: - Đang tải

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading icons...")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectIcon(_ icon: (name: String, path: String)) {
        if let image = getIconImage(icon.path) {
            appIcon = image
            dismiss()
        }
    }

    private func getIconImage(_ path: String) -> UIImage? {
        guard let appDirectory = Storage.shared.getAppDirectory(for: app) else {
            return nil
        }

        // Find the .app bundle
        guard let appBundle = try? FileManager.default
            .contentsOfDirectory(at: appDirectory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else {
            return nil
        }

        let iconPath = appBundle.appendingPathComponent(path)

        // Try with extensions
        let variations = [
            iconPath,
            iconPath.appendingPathExtension("png"),
            URL(fileURLWithPath: iconPath.path + "@2x"),
            URL(fileURLWithPath: iconPath.path + "@2x.png"),
            URL(fileURLWithPath: iconPath.path + "@3x"),
            URL(fileURLWithPath: iconPath.path + "@3x.png")
        ]

        for variation in variations {
            if let image = UIImage(contentsOfFile: variation.path) {
                return image.resizeToSquare()
            }
        }

        return nil
    }

    private func loadAlternateIcons() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            guard let appDirectory = Storage.shared.getAppDirectory(for: app) else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }

            // Find the .app bundle
            guard let appBundle = try? FileManager.default
                .contentsOfDirectory(at: appDirectory, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
            else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }

            // Read Info.plist
            let infoPlistPath = appBundle.appendingPathComponent("Info.plist")

            guard let infoPlist = NSDictionary(contentsOf: infoPlistPath) else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }

            // Parse CFBundleIcons
            var icons: [(name: String, path: String)] = []

            if let iconDict = infoPlist["CFBundleIcons"] as? [String: Any],
               let alternateIconsDict = iconDict["CFBundleAlternateIcons"] as? [String: [String: Any]] {

                icons = alternateIconsDict.compactMap { (name, details) in
                    if let files = details["CFBundleIconFiles"] as? [String],
                       let path = files.first {
                        return (name, path)
                    }
                    return nil
                }
            }

            DispatchQueue.main.async {
                self.alternateIcons = icons.sorted { $0.name < $1.name }
                self.isLoading = false
            }
        }
    }
}

// MARK: - Alternative Icon Row
struct AlternativeIconRow: View {
    let icon: (name: String, path: String)
    let app: ImportedApp

    private var iconImage: UIImage? {
        guard let appDirectory = Storage.shared.getAppDirectory(for: app) else {
            return nil
        }

        guard let appBundle = try? FileManager.default
            .contentsOfDirectory(at: appDirectory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else {
            return nil
        }

        let iconPath = appBundle.appendingPathComponent(icon.path)

        let variations = [
            iconPath,
            iconPath.appendingPathExtension("png"),
            URL(fileURLWithPath: iconPath.path + "@2x"),
            URL(fileURLWithPath: iconPath.path + "@2x.png"),
            URL(fileURLWithPath: iconPath.path + "@3x"),
            URL(fileURLWithPath: iconPath.path + "@3x.png")
        ]

        for variation in variations {
            if let image = UIImage(contentsOfFile: variation.path) {
                return image.resizeToSquare()
            }
        }

        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let image = iconImage {
                Image(uiImage: image)
                    .appIconStyle(size: 56)
            } else {
                RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                    .fill(Theme.cardAlt)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "app.dashed")
                            .foregroundStyle(Theme.ink3)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(icon.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(icon.path)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            CardChevron()
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - UIImage Extension
extension UIImage {
    func resizeToSquare() -> UIImage? {
        let dimension = min(size.width, size.height)
        let newSize = CGSize(width: dimension, height: dimension)

        UIGraphicsBeginImageContextWithOptions(newSize, false, scale)
        defer { UIGraphicsEndImageContext() }

        let xOffset = (size.width - dimension) / 2
        let yOffset = (size.height - dimension) / 2
        let rect = CGRect(x: -xOffset, y: -yOffset, width: size.width, height: size.height)

        draw(in: rect)

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
