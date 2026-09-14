//
//  SigningAppAlternativeIconView.swift
//  zsignapp
//
//  Alternative icon picker for signing
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
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading icons...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if alternateIcons.isEmpty {
                EmptyStateView(
                    title: "No Alternative Icons",
                    systemImage: "app.dashed",
                    message: "This app doesn't have alternative icons"
                )
            } else {
                List {
                    ForEach(alternateIcons, id: \.name) { icon in
                        Button {
                            selectIcon(icon)
                        } label: {
                            AlternativeIconRow(
                                icon: icon,
                                app: app
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Alternative Icons")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAlternateIcons()
        }
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
                    .appIconStyle(size: 60)
            } else {
                RoundedRectangle(cornerRadius: 13.4, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "app.dashed")
                            .foregroundColor(.gray)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(icon.name)
                    .font(.headline)
                
                Text(icon.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
