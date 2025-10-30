//
//  SigningHandler-zsignapp.swift
//  zsignapp
//  FIXED: Use Zip library instead of SwiftMiniZip

import Foundation
import UIKit
import ZsignSwift
import Zip

class SigningHandler {
    private let fileManager = FileManager.default
    private let uuid = UUID().uuidString
    private let workDir: URL
    private let settings = AppSettings.shared
    private let options: SigningOptions
    
    private let sourceApp: ImportedApp
    private let certificate: CertificatePair
    private let customIcon: UIImage?
    private let disabledTweaks: [String]
    
    private var disabledTweaksHandler: DisabledTweaksHandler?
    private var appPath: URL?
    
    var stepProgressCallback: ((String) -> Void)?
    var progressCallback: ((Double) -> Void)?
    
    init(
        sourceApp: ImportedApp,
        certificate: CertificatePair,
        options: SigningOptions? = nil,
        customIcon: UIImage? = nil,
        disabledTweaks: [String] = []
    ) {
        self.sourceApp = sourceApp
        self.certificate = certificate
        self.options = options ?? SigningOptionsManager.shared.options
        self.customIcon = customIcon
        self.disabledTweaks = disabledTweaks
        self.workDir = fileManager.temporaryDirectory.appendingPathComponent("Signing_\(uuid)")
    }

    // MARK: - Main Signing Flow
    
    func performFullSigning() async throws {
        BackgroundAudioManager.shared.startBackgroundAudio()
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        do {
            await notifyProgress("Preparing...")
            try await prepare()
            
            await notifyProgress("Modifying and signing...")
            try await modify()
            
            await notifyProgress("Cleaning up...")
            await cleanup()
            
            await notifyProgress("Completed")
            
        } catch {
            disabledTweaksHandler?.cleanup()
            await cleanup()
            throw error
        }
    }
    
    @MainActor
    private func notifyProgress(_ message: String) {
        stepProgressCallback?(message)
    }
    
    // MARK: - Step 1: Prepare
    
    func prepare() async throws {
        guard let sourceUUID = sourceApp.uuid else {
            throw SigningError.invalidApp
        }
        
        let sourceDir = fileManager.appDirectory(sourceUUID)
        let appFiles = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        
        guard let appFile = appFiles.first(where: { $0.pathExtension == "app" }) else {
            throw SigningError.appNotFound
        }
        
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        
        let destPath = workDir.appendingPathComponent(appFile.lastPathComponent)
        try fileManager.copyItem(at: appFile, to: destPath)
        
        appPath = destPath
        print("Prepared app at: \(destPath.path)")
    }
    
    // MARK: - Step 2: Modify
    
    func modify() async throws {
        guard let appPath = appPath else {
            throw SigningError.appNotPrepared
        }
        
        let infoPlistPath = appPath.appendingPathComponent("Info.plist")
        
        guard let infoDictionary = NSMutableDictionary(contentsOf: infoPlistPath) else {
            throw SigningError.infoPlistNotFound
        }
        
        // 1.Modify plugin identifiers
        if let customIdentifier = options.appIdentifier,
           let oldIdentifier = infoDictionary["CFBundleIdentifier"] as? String {
            try await modifyPluginIdentifiers(old: oldIdentifier, new: customIdentifier, for: appPath)
        }
        
        // 2. Modify Info.plist
        try await modifyInfoPlist(using: infoDictionary, to: appPath)
        
        // 3.Modify icon
        if let customIcon = customIcon {
            try await modifyIcon(using: infoDictionary, image: customIcon, to: appPath)
        }
        
        // 4.Modify locales
        if let customName = options.appName {
            try await modifyLocalesForName(customName, for: appPath)
        }
        
        // 5.Remove custom files
        if !options.removeFiles.isEmpty {
            try await removeCustomFiles(options.removeFiles, at: appPath)
        }
        
        // 6.Remove preset files
        try await removePresetFiles(at: appPath)
        
        // 7. Remove watch
        try await removeWatchIfNeeded(for: appPath)
        
        // 8. SDK 26 patch (if enabled)
        if options.experiment_supportLiquidGlass {
            try await locateMachosAndChangeToSDK26(for: appPath)
        }
        
        // 9. Inject tweaks
        if options.experiment_replaceSubstrateWithEllekit || !options.injectionFiles.isEmpty {
            await notifyProgress("Injecting tweaks...")
            let tweakHandler = TweakHandler(
                app: appPath,
                options: options,
                disabledTweaks: disabledTweaks
            )
            try await tweakHandler.inject()
        }
        
        // 10.iOS 19+ ARM64e fixup SAU injection
        if #available(iOS 19, *) {
            await notifyProgress("Applying iOS 19+ patches...")
            try await locateMachosAndFixupArm64eSlice(for: appPath)
        }
        
        // 11.Disinject
        if !disabledTweaks.isEmpty {
            await notifyProgress("Cleaning load commands...")
            disabledTweaksHandler = DisabledTweaksHandler(
                appURL: appPath,
                disabledTweaks: disabledTweaks
            )
            try disabledTweaksHandler?.removeDisabledTweaks()
        }
        
        // 12. Sign
        await notifyProgress("Signing...")
        try await sign()
        
        disabledTweaksHandler?.cleanup()
        
        // 13. Move to Signed
        await notifyProgress("Finalizing...")
        try await move()
        
        // 14. Add to database
        await notifyProgress("Saving...")
        try await saveToDatabase()
        
        // 15. Create IPA
        await notifyProgress("Creating IPA...")
        try await createIPA()
    }
    
    // MARK: - Modify Functions
    
    private func modifyInfoPlist(using dict: NSMutableDictionary, to app: URL) async throws {
        // Basic features
        if options.fileSharing {
            dict.setObject(true, forKey: "UISupportsDocumentBrowser" as NSCopying)
        }
        if options.itunesFileSharing {
            dict.setObject(true, forKey: "UIFileSharingEnabled" as NSCopying)
        }
        if options.proMotion {
            dict.setObject(true, forKey: "CADisableMinimumFrameDurationOnPhone" as NSCopying)
        }
        if options.gameMode {
            dict.setObject(true, forKey: "GCSupportsGameMode" as NSCopying)
        }
        if options.ipadFullscreen {
            dict.setObject(true, forKey: "UIRequiresFullScreen" as NSCopying)
        }
        if options.removeURLScheme {
            dict.removeObject(forKey: "CFBundleURLTypes")
        }
        
        // Appearance
        if options.appAppearance != SigningOptions.appAppearanceValues[0] {
            let value: Int = {
                switch options.appAppearance {
                case "Light": return 1
                case "Dark": return 2
                default: return 0
                }
            }()
            dict.setObject(value, forKey: "UIUserInterfaceStyle" as NSCopying)
        }
        
        // Minimum requirement
        if options.minimumAppRequirement != SigningOptions.appMinimumAppRequirementValues[0] {
            dict.setObject(options.minimumAppRequirement, forKey: "MinimumOSVersion" as NSCopying)
        }
        
        // Remove useless crap
        if dict["UISupportedDevices"] != nil {
            dict.removeObject(forKey: "UISupportedDevices")
        }
        
        // PROMINENT VALUES
        if let customIdentifier = options.appIdentifier {
            dict.setObject(customIdentifier, forKey: "CFBundleIdentifier" as NSCopying)
        }
        if let customName = options.appName {
            dict.setObject(customName, forKey: "CFBundleDisplayName" as NSCopying)
            dict.setObject(customName, forKey: "CFBundleName" as NSCopying)
        }
        if let customVersion = options.appVersion {
            dict.setObject(customVersion, forKey: "CFBundleShortVersionString" as NSCopying)
            dict.setObject(customVersion, forKey: "CFBundleVersion" as NSCopying)
        }
        
        // Custom Info.plist entries
        for (key, value) in options.customInfoPlistEntries {
            dict.setObject(value, forKey: key as NSCopying)
        }
        
        // WRITE
        try dict.write(to: app.appendingPathComponent("Info.plist"))
    }
    
    private func modifyIcon(using dict: NSMutableDictionary, image: UIImage, to app: URL) async throws {
        let imageSizes = [
            (width: 120, height: 120, name: "FRIcon60x60@2x.png"),
            (width: 152, height: 152, name: "FRIcon76x76@2x~ipad.png")
        ]
        
        for imageSize in imageSizes {
            if let resizedImage = resizeIconImage(image, to: CGSize(width: imageSize.width, height: imageSize.height)),
               let imageData = resizedImage.pngData() {
                let fileURL = app.appendingPathComponent(imageSize.name)
                try imageData.write(to: fileURL)
            }
        }
        
        let cfBundleIcons: [String: Any] = [
            "CFBundlePrimaryIcon": [
                "CFBundleIconFiles": ["FRIcon60x60"],
                "CFBundleIconName": "FRIcon"
            ]
        ]
        
        let cfBundleIconsIpad: [String: Any] = [
            "CFBundlePrimaryIcon": [
                "CFBundleIconFiles": ["FRIcon60x60", "FRIcon76x76"],
                "CFBundleIconName": "FRIcon"
            ]
        ]
        
        dict["CFBundleIcons"] = cfBundleIcons
        dict["CFBundleIcons~ipad"] = cfBundleIconsIpad
        
        //  WRITE
        try dict.write(to: app.appendingPathComponent("Info.plist"))
        
        // Save icon for database
        try await saveCustomIconForDatabase(image)
    }
    
    private func modifyLocalesForName(_ name: String, for app: URL) async throws {
        let localizationBundles = try fileManager
            .contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        
        for bundleURL in localizationBundles {
            let plistURL = bundleURL.appendingPathComponent("InfoPlist.strings")
            
            guard fileManager.fileExists(atPath: plistURL.path),
                  let dictionary = NSMutableDictionary(contentsOf: plistURL) else {
                continue
            }
            
            dictionary["CFBundleDisplayName"] = name
            dictionary.write(toFile: plistURL.path, atomically: true)
        }
    }
    
    private func modifyPluginIdentifiers(
        old oldIdentifier: String,
        new newIdentifier: String,
        for app: URL
    ) async throws {
        let pluginBundles = enumerateFiles(at: app) {
            $0.hasSuffix(".app") || $0.hasSuffix(".appex")
        }
        
        for bundleURL in pluginBundles {
            let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
            
            guard let infoDict = NSDictionary(contentsOf: infoPlistURL)?.mutableCopy() as? NSMutableDictionary else {
                continue
            }
            
            var didChange = false
            
            // CFBundleIdentifier
            if let oldValue = infoDict["CFBundleIdentifier"] as? String {
                let newValue = oldValue.replacingOccurrences(of: oldIdentifier, with: newIdentifier)
                if oldValue != newValue {
                    infoDict["CFBundleIdentifier"] = newValue
                    didChange = true
                }
            }
            
            // WKCompanionAppBundleIdentifier
            if let oldValue = infoDict["WKCompanionAppBundleIdentifier"] as? String {
                let newValue = oldValue.replacingOccurrences(of: oldIdentifier, with: newIdentifier)
                if oldValue != newValue {
                    infoDict["WKCompanionAppBundleIdentifier"] = newValue
                    didChange = true
                }
            }
            
            // NSExtension → NSExtensionAttributes → WKAppBundleIdentifier
            if let extensionDict = infoDict["NSExtension"] as? NSMutableDictionary,
               let attributes = extensionDict["NSExtensionAttributes"] as? NSMutableDictionary,
               let oldValue = attributes["WKAppBundleIdentifier"] as? String {
                let newValue = oldValue.replacingOccurrences(of: oldIdentifier, with: newIdentifier)
                if oldValue != newValue {
                    attributes["WKAppBundleIdentifier"] = newValue
                    didChange = true
                }
            }
            
            if didChange {
                infoDict.write(to: infoPlistURL, atomically: true)
            }
        }
    }
    
    private func removePresetFiles(at app: URL) async throws {
        var files = [
            "embedded.mobileprovision",
            "com.apple.WatchPlaceholder",
            "SignedByEsign",
            "SC_Info"
        ].map {
            app.appendingPathComponent($0)
        }
        
        // Add _CodeSignature directories
        let codeSignDirs = enumerateFiles(at: app) { $0.hasSuffix("_CodeSignature") }
        files.append(contentsOf: codeSignDirs)
        
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }
    
    private func removeWatchIfNeeded(for app: URL) async throws {
        let watchDir = app.appendingPathComponent("Watch")
        guard fileManager.fileExists(atPath: watchDir.path) else { return }
        
        let contents = try fileManager.contentsOfDirectory(
            at: watchDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for watchApp in contents where watchApp.pathExtension == "app" {
            let infoPlist = watchApp.appendingPathComponent("Info.plist")
            if !fileManager.fileExists(atPath: infoPlist.path) {
                try? fileManager.removeItem(at: watchApp)
            }
        }
    }
    
    private func removeCustomFiles(_ files: [String], at app: URL) async throws {
        for file in files {
            let fileURL = app.appendingPathComponent(file)
            try? fileManager.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Icon Helpers
    
    private func saveCustomIconForDatabase(_ icon: UIImage) async throws {
        guard let pngData = icon.pngData() else {
            throw SigningError.invalidIcon
        }
        
        let iconsDir = fileManager.signedAppIconsDirectory(for: uuid)
        try fileManager.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        
        let iconPath = iconsDir.appendingPathComponent("custom_icon.png")
        try pngData.write(to: iconPath)
    }
    
    private func resizeIconImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - iOS Patches
    
    private func locateMachosAndChangeToSDK26(for app: URL) async throws {
        if let url = Bundle(url: app)?.executableURL {
            LCPatchMachOForSDK26(app.appendingPathComponent(url.relativePath).path)
        }
    }
    
    @available(iOS 19, *)
    private func locateMachosAndFixupArm64eSlice(for app: URL) async throws {
        let machoFiles = enumerateFiles(at: app) {
            $0.hasSuffix(".dylib") || $0.hasSuffix(".framework")
        }
        
        for fileURL in machoFiles {
            switch fileURL.pathExtension {
            case "dylib":
                LCPatchMachOFixupARM64eSlice(fileURL.path)
            case "framework":
                if let bundle = Bundle(url: fileURL),
                   let execURL = bundle.executableURL {
                    LCPatchMachOFixupARM64eSlice(execURL.path)
                }
            default:
                continue
            }
        }
    }
    
    // MARK: - Sign
    
    func sign() async throws {
        guard let appPath = appPath else {
            throw SigningError.appNotPrepared
        }
        
        guard let certFile = Storage.shared.getCertificateFile(.p12, from: certificate),
              let provisionFile = Storage.shared.getCertificateFile(.mobileprovision, from: certificate) else {
            throw SigningError.certificateFilesNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let success = Zsign.sign(
                appPath: appPath.path,
                provisionPath: provisionFile.path,
                p12Path: certFile.path,
                p12Password: certificate.password ?? "",
                entitlementsPath: "",
                customIdentifier: "",
                customName: "",
                customVersion: "",
                removeProvision: !options.removeProvisioning
            ) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    print("Signing complete")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SigningError.signingFailed)
                }
            }
            
            if !success {
                continuation.resume(throwing: SigningError.signingFailed)
            }
        }
    }
    
    // MARK: - Move to Signed/
    
    func move() async throws {
        guard let signedAppPath = appPath else {
            throw SigningError.appNotPrepared
        }
        
        // Move .app to Documents/Signed/{UUID}/
        let destDir = fileManager.signedAppDirectory(uuid)
        let destPath = destDir.appendingPathComponent(signedAppPath.lastPathComponent)
        
        try fileManager.moveItem(at: signedAppPath, to: destPath)
        appPath = destPath
        
        print(" Moved signed app to: \(destPath.path)")
    }
    
    // MARK: - Save to Database
    
    func saveToDatabase() async throws {
        await MainActor.run {
            let finalName = options.appName ?? sourceApp.name
            let finalIdentifier = options.appIdentifier ?? sourceApp.identifier
            let finalVersion = options.appVersion ?? sourceApp.version
            let finalIconFileName = customIcon != nil ? "custom_icon.png" : sourceApp.iconFileName
            
            Storage.shared.addSignedApp(
                uuid: uuid,
                sourceUUID: sourceApp.uuid,
                certificateUUID: certificate.uuid,
                name: finalName,
                identifier: finalIdentifier,
                version: finalVersion,
                iconFileName: finalIconFileName
            )
            
            print("Saved to database")
        }
    }
    
    // MARK: - Create IPA (DÙNG ZIP LIBRARY)
    
    func createIPA() async throws {
        guard let signedAppPath = appPath else {
            throw SigningError.appNotPrepared
        }
        
        return try await Task.detached(priority: .userInitiated) { [self] in
            // Create temp IPA work dir
            let ipaWorkDir = self.fileManager.temporaryDirectory
                .appendingPathComponent("IPACreation_\(UUID().uuidString)")
            
            try self.fileManager.createDirectory(at: ipaWorkDir, withIntermediateDirectories: true)
            
            // Create Payload/
            let payloadDir = ipaWorkDir.appendingPathComponent("Payload")
            try self.fileManager.createDirectory(at: payloadDir, withIntermediateDirectories: true)
            
            // Copy .app to Payload/
            let appInPayload = payloadDir.appendingPathComponent(signedAppPath.lastPathComponent)
            try self.fileManager.copyItem(at: signedAppPath, to: appInPayload)
            
            // Create IPA
            let ipaName = (self.sourceApp.name ?? "SignedApp")
                .replacingOccurrences(of: " ", with: "_") + ".ipa"
            
            let ipaPath = ipaWorkDir.appendingPathComponent(ipaName)
            
            //  COMPRESS WITH ZIP LIBRARY
            try await self.createIPAWithZipLibrary(
                payloadDir: payloadDir,
                outputPath: ipaPath,
                compressionLevel: self.settings.compressionType
            )
            
            // Move IPA to Signed/
            let ipaDestDir = self.fileManager.signedAppDirectory(self.uuid)
            let ipaDestPath = ipaDestDir.appendingPathComponent(ipaName)
            
            try? self.fileManager.removeItem(at: ipaDestPath)
            try self.fileManager.moveItem(at: ipaPath, to: ipaDestPath)
            
            // Cleanup
            try? self.fileManager.removeItem(at: ipaWorkDir)
            
            print("IPA saved to: \(ipaDestPath.path)")
            
        }.value
    }
    
    //  DÙNG ZIP LIBRARY
    private func createIPAWithZipLibrary(
        payloadDir: URL,
        outputPath: URL,
        compressionLevel: CompressionLevel
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                do {
                    //  ZIP WITH PROGRESS
                    try Zip.zipFiles(
                        paths: [payloadDir],
                        zipFilePath: outputPath,
                        password: nil,
                        compression: compressionLevel,
                        progress: { progress in
                            Task { @MainActor in
                                self?.progressCallback?(progress)
                            }
                        }
                    )
                    
                    print(" IPA created successfully")
                    
                    Task { @MainActor in
                        self?.progressCallback?(1.0)
                    }
                    
                    continuation.resume()
                    
                } catch {
                    print(" Failed to create IPA: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() async {
        try? fileManager.removeItem(at: workDir)
        print(" Cleaned up temp directory")
    }
    
    // MARK: - Helpers
    
    private func enumerateFiles(at base: URL, where predicate: (String) -> Bool) -> [URL] {
        guard let fileEnum = fileManager.enumerator(atPath: base.path) else {
            return []
        }
        
        var results: [URL] = []
        
        while let file = fileEnum.nextObject() as? String {
            if predicate(file) {
                results.append(base.appendingPathComponent(file))
            }
        }
        
        return results
    }
}

// MARK: - Errors

enum SigningError: LocalizedError {
    case invalidApp
    case appNotFound
    case appNotPrepared
    case infoPlistNotFound
    case certificateFilesNotFound
    case signingFailed
    case executableNotFound
    case invalidIcon
    
    var errorDescription: String? {
        switch self {
        case .invalidApp:
            return "Invalid app"
        case .appNotFound:
            return "App file not found"
        case .appNotPrepared:
            return "App not prepared for signing"
        case .infoPlistNotFound:
            return "Info.plist not found"
        case .certificateFilesNotFound:
            return "Certificate files not found"
        case .signingFailed:
            return "Signing failed"
        case .executableNotFound:
            return "App executable not found"
        case .invalidIcon:
            return "Invalid icon image"
        }
    }
}
