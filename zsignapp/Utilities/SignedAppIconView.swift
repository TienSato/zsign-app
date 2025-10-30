//
//  SignedAppIconView.swift
//  zsignapp
// satofix

import SwiftUI

struct SignedAppIconView: View {
    let app: SignedApp
    let size: CGFloat
    
    private var iconImage: UIImage? {
        guard let iconFileName = app.iconFileName,
              let uuid = app.uuid else {
            return nil
        }
        
        let customIconURL = FileManager.default.signedAppIconsDirectory(for: uuid)
            .appendingPathComponent(iconFileName)
        
        if FileManager.default.fileExists(atPath: customIconURL.path),
           let image = UIImage(contentsOfFile: customIconURL.path) {
            return image
        }
        guard let sourceUUID = app.sourceUUID else {
            return nil
        }
        let sourceIconURL = FileManager.default.iconsDirectory(for: sourceUUID)
            .appendingPathComponent(iconFileName)
        
        if FileManager.default.fileExists(atPath: sourceIconURL.path),
           let image = UIImage(contentsOfFile: sourceIconURL.path) {
            return image
        }
        
        return nil
    }
    
    var body: some View {
        Group {
            if let image = iconImage {
                Image(uiImage: image)
                    .appIconStyle(size: size)
            } else {
                // Placeholder icon
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: size * 0.5))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }
}
