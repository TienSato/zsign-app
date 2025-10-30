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
        print(" ========== START IMPORT ==========")
        print(" Input URL: \(url)")
        
        // Enable background audio at the start
        BackgroundAudioManager.shared.startBackgroundAudio()
        print("Background audio enabled for import")
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
                print("Background audio auto-stopped after import")
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
        print(" Work dir: \(workDir.path)")
        
        // 2. Copy file
        await updateProgress(0.1, "Copying IPA file...")
        let copiedIPA = workDir.appendingPathComponent(url.lastPathComponent)
        
        print("Copying from: \(url.path)")
        try? fileManager.removeItem(at: copiedIPA)
        try fileManager.copyItem(at: url, to: copiedIPA)
        print(" Copied successfully")
        
        guard fileManager.fileExists(atPath: copiedIPA.path) else {
            throw IPAError.unzipFailed
        }
        
        // 3. Add custom file extensions
        Zip.addCustomFileExtension("ipa")
        
        // 4. Unzip with progress
        await updateProgress(0.2, "Extracting IPA archive...")
        print(" Unzipping...")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                do {
                    try Zip.unzipFile(
                        copiedIPA,
                        destination: workDir,
                        overwrite: true,
                        password: nil,
                        progress: { progress in
                            //  Report unzip progress (20% - 70%)
                            let mappedProgress = 0.2 + (progress * 0.5)
                            Task { @MainActor in
                                self?.progressCallback?(mappedProgress)
                                
                                let percentage = Int(progress * 100)
                                if percentage % 10 == 0 {
                                    self?.stepCallback?("Extracting: \(percentage)%")
                                }
                            }
                            
                            let p = Int(progress * 100)
                            if p % 20 == 0 {
                                print(" Unzip: \(p)%")
                            }
                        }
                    )
                    
                    print("Unzipped successfully")
                    continuation.resume()
                    
                } catch {
                    print("Unzip error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // 5. Find Payload
        await updateProgress(0.75, "Locating app bundle...")
        let payloadURL = workDir.appendingPathComponent("Payload")
        
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            print("Payload not found!")
            throw IPAError.noPayload
        }
        
        print("Found Payload")
        
        // 6. Find .app bundle
        let contents = try fileManager.contentsOfDirectory(
            at: payloadURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            print("No .app bundle")
            throw IPAError.noAppBundle
        }
        
        print("App bundle: \(appBundle.lastPathComponent)")
        
        // 7. Read app info
        await updateProgress(0.8, "Reading app information...")
        let bundle = Bundle(url: appBundle)
        let appInfo = extractAppInfo(from: bundle)
        
        print(" Name: \(appInfo.name ?? "Unknown")")
        print("ID: \(appInfo.identifier ?? "Unknown")")
        print(" Version: \(appInfo.version ?? "Unknown")")
        
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
        
        print("Moving to: \(finalAppPath.path)")
        
        try? fileManager.removeItem(at: finalAppPath)
        try fileManager.moveItem(at: appBundle, to: finalAppPath)
        
        print("Moved successfully")
        
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
        
        print("Saved to database")
        
        // 11. Cleanup
        await updateProgress(0.98, "Cleaning up...")
        try? fileManager.removeItem(at: workDir)
        print(" Cleaned up")
        
        await updateProgress(1.0, "Import complete!")
        print("========== IMPORT SUCCESS ==========")
        print("\(appInfo.name ?? "Unknown")")
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
            print("No icon found")
            return nil
        }
        
        guard let iconImage = UIImage(contentsOfFile: largestIcon.path) else {
            return nil
        }
        
        let iconsDir = fileManager.iconsDirectory(for: uuid)
        let savedPath = iconsDir.appendingPathComponent("icon.png")
        
        if let pngData = iconImage.pngData() {
            try pngData.write(to: savedPath)
            print("Icon saved")
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
        
        // 5. Nếu vẫn trống → quét trong thư mục tìm file có chứa "Logo"
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
                print("Không thể đọc thư mục appBundle: \(error)")
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
                "\(iconName)@3x.jpg"
            ]
            
            for variation in variations {
                let iconPath = appBundle.appendingPathComponent(variation)
                
                if fileManager.fileExists(atPath: iconPath.path),
                   let image = UIImage(contentsOfFile: iconPath.path) {
                    foundIcons.append((iconPath, image.size))
                }
            }
        }
        
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
