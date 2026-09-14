//
//  IPAHandler.swift
//  zsignapp
//

import Foundation
import Zip
import UIKit

class IPAHandler {
    private let fileManager = FileManager.default
    
    // Progress callbacks
    var progressCallback: ((Double) -> Void)?
    var stepCallback: ((String) -> Void)?
    
    func importIPA(from url: URL) async throws {
        await updateProgress(0.0, "Starting import...")
        
        BackgroundAudioManager.shared.startBackgroundAudio(force: true)
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        // Access security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let uuid = UUID().uuidString
        let workDir = fileManager.temporaryDirectory.appendingPathComponent("ZsignImport_\(uuid)")
        
        // 1. Create work directory
        await updateProgress(0.05, "Creating workspace...")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        
        // 2. Copy file
        await updateProgress(0.1, "Copying IPA file...")
        let copiedIPA = workDir.appendingPathComponent(url.lastPathComponent)
        
        try? fileManager.removeItem(at: copiedIPA)
        try fileManager.copyItem(at: url, to: copiedIPA)
        
        guard fileManager.fileExists(atPath: copiedIPA.path) else {
            throw IPAError.unzipFailed
        }
        
        // 3. Add custom file extensions
        Zip.addCustomFileExtension("ipa")
        
        // 4. Unzip with progress
        await updateProgress(0.2, "Extracting IPA archive...")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                do {
                    try Zip.unzipFile(
                        copiedIPA,
                        destination: workDir,
                        overwrite: true,
                        password: nil,
                        progress: { progress in
                            // Chỉ đẩy tiến độ cho thanh. KHÔNG ghi thêm phần trăm vào
                            // dòng mô tả: thanh chạy theo thang 20-70% còn con số kia
                            // theo thang 0-100% -> hộp thoại hiện 2 số khác nhau.
                            let mappedProgress = 0.2 + (progress * 0.5)
                            Task { @MainActor in
                                self?.progressCallback?(mappedProgress)
                            }
                        }
                    )
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // 5. Find Payload
        await updateProgress(0.75, "Locating app bundle...")
        let payloadURL = workDir.appendingPathComponent("Payload")
        
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw IPAError.noPayload
        }
        
        // 6. Find .app bundle
        let contents = try fileManager.contentsOfDirectory(
            at: payloadURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw IPAError.noAppBundle
        }
        
        // 7. Read app info
        await updateProgress(0.8, "Reading app information...")
        let bundle = Bundle(url: appBundle)
        let appInfo = extractAppInfo(from: bundle)
        
        // 8. Extract icon
        await updateProgress(0.85, "Extracting app icon...")
        let savedIconFileName = try await extractAndSaveIcon(
            from: appBundle,
            bundle: bundle,
            uuid: uuid
        )
        
        // 9. Move app to Documents
        await updateProgress(0.9, "Finalizing import...")
        let finalDestination = fileManager.appDirectory(uuid)
        let finalAppPath = finalDestination.appendingPathComponent(appBundle.lastPathComponent)
        
        try? fileManager.removeItem(at: finalAppPath)
        try fileManager.moveItem(at: appBundle, to: finalAppPath)
        
        // 10. Save to database
        await updateProgress(0.95, "Saving to database...")
        await MainActor.run {
            Storage.shared.addApp(
                uuid: uuid,
                name: appInfo.name,
                identifier: appInfo.identifier,
                version: appInfo.version,
                iconFileName: savedIconFileName
            )
        }
        
        // 11. Cleanup
        await updateProgress(0.98, "Cleaning up...")
        try? fileManager.removeItem(at: workDir)
        
        await updateProgress(1.0, "Import complete!")
    }
    
    // Progress helper
    @MainActor
    private func updateProgress(_ progress: Double, _ step: String) {
        progressCallback?(progress)
        stepCallback?(step)
    }
    
    // MARK: - Private Helpers
    
    private func extractAppInfo(from bundle: Bundle?) -> AppInfo {
        AppInfo(
            name: bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleName"] as? String,
            identifier: bundle?.bundleIdentifier,
            version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
        )
    }
    
    private func extractAndSaveIcon(
        from appBundle: URL,
        bundle: Bundle?,
        uuid: String
    ) async throws -> String? {
        let iconFiles = findIconFiles(in: appBundle, bundle: bundle)
        
        guard let largestIcon = findLargestIcon(from: iconFiles, in: appBundle) else {
            return nil
        }
        
        guard let iconImage = UIImage(contentsOfFile: largestIcon.path) else {
            return nil
        }
        
        let iconsDir = fileManager.iconsDirectory(for: uuid)
        let savedPath = iconsDir.appendingPathComponent("icon.png")
        
        if let pngData = iconImage.pngData() {
            try pngData.write(to: savedPath)
            return "icon.png"
        }
        
        return nil
    }
    
    private func findIconFiles(in appBundle: URL, bundle: Bundle?) -> [String] {
        var iconFiles: [String] = []
        
        // 1. Lấy từ CFBundleIcons → CFBundlePrimaryIcon → CFBundleIconFiles
        if let icons = bundle?.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primaryIcon["CFBundleIconFiles"] as? [String] {
            iconFiles.append(contentsOf: files)
        }
        
        // 2. Lấy từ CFBundleIconFiles
        if let files = bundle?.infoDictionary?["CFBundleIconFiles"] as? [String] {
            iconFiles.append(contentsOf: files)
        }
        
        // 3. Lấy từ CFBundleIconFile (cũ)
        if let file = bundle?.infoDictionary?["CFBundleIconFile"] as? String {
            iconFiles.append(file)
        }
        
        // 4. Nếu vẫn trống → fallback mặc định
        if iconFiles.isEmpty {
            iconFiles = ["AppIcon60x60", "AppIcon76x76", "Icon", "icon"]
        }
        
        // 5. Quét thư mục tìm file có chứa "Logo"
        if iconFiles.isEmpty {
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: appBundle.path)
                let logoFiles = contents.filter {
                    $0.localizedCaseInsensitiveContains("Logo") && ($0.hasSuffix(".png") || $0.hasSuffix(".jpg"))
                }.map { $0.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: ".jpg", with: "") }
                
                if !logoFiles.isEmpty {
                    iconFiles.append(contentsOf: logoFiles)
                }
            } catch {
                // Ignore error
            }
        }
        
        // 6. Nếu vẫn không có → quét tất cả file ảnh
        if iconFiles.isEmpty {
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: appBundle.path)
                let allImageFiles = contents.filter { filename in
                    let lowercased = filename.lowercased()
                    return lowercased.hasSuffix(".png") ||
                    lowercased.hasSuffix(".jpg") ||
                    lowercased.hasSuffix(".jpeg")
                }.map {
                    $0.replacingOccurrences(of: ".png", with: "")
                        .replacingOccurrences(of: ".jpg", with: "")
                        .replacingOccurrences(of: ".jpeg", with: "")
                }
                
                if !allImageFiles.isEmpty {
                    iconFiles.append(contentsOf: allImageFiles)
                }
            } catch {
                // Ignore error
            }
        }
        
        return iconFiles
    }
    
    private func findLargestIcon(from iconFiles: [String], in appBundle: URL) -> URL? {
        var foundIcons: [(url: URL, size: CGSize)] = []
        let fileManager = FileManager.default
        
        for iconName in iconFiles {
            let variations = [
                iconName,
                "\(iconName)@2x",
                "\(iconName)@3x",
                "\(iconName).png",
                "\(iconName)@2x.png",
                "\(iconName)@3x.png",
                "\(iconName).jpg",
                "\(iconName)@2x.jpg",
                "\(iconName)@3x.jpg",
                "\(iconName).jpeg",
                "\(iconName)@2x.jpeg",
                "\(iconName)@3x.jpeg"
            ]
            
            for variation in variations {
                let iconPath = appBundle.appendingPathComponent(variation)
                
                if fileManager.fileExists(atPath: iconPath.path),
                   let image = UIImage(contentsOfFile: iconPath.path) {
                    let size = image.size
                    
                    // Filter: Phải hình vuông (tỷ lệ gần 1:1)
                    let ratio = size.width / size.height
                    let isSquare = ratio >= 0.9 && ratio <= 1.1
                    
                    // Filter: Kích thước hợp lý (29-1024px)
                    let isValidSize = size.width >= 29 && size.width <= 1024
                    
                    if isSquare && isValidSize {
                        foundIcons.append((iconPath, size))
                    }
                }
            }
        }
        
        guard !foundIcons.isEmpty else {
            return nil
        }
        
        // Ưu tiên icon 60-180px (kích thước chuẩn iOS)
        let preferredIcons = foundIcons.filter {
            $0.size.width >= 60 && $0.size.width <= 180
        }
        
        if !preferredIcons.isEmpty {
            return preferredIcons.max(by: { $0.size.width < $1.size.width })?.url
        }
        
        // Fallback: Icon lớn nhất
        return foundIcons.max(by: { $0.size.width < $1.size.width })?.url
    }
}

// MARK: - Models

struct AppInfo {
    let name: String?
    let identifier: String?
    let version: String?
}

enum IPAError: LocalizedError {
    case unzipFailed
    case noPayload
    case noAppBundle
    
    var errorDescription: String? {
        switch self {
        case .unzipFailed:
            return "Failed to unzip IPA file"
        case .noPayload:
            return "Payload folder not found in IPA"
        case .noAppBundle:
            return "App bundle (.app) not found"
        }
    }
}
