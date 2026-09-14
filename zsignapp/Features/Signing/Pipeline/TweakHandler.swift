//
//  TweakHandler.swift
//  Zsign
//

import Foundation
import ZsignSwift

class TweakHandler {
    private let fileManager = FileManager.default
    private var urlsToInject: [URL] = []
    private var directoriesToCheck: [URL] = []
    
    private let app: URL
    private var options: SigningOptions
    private var urls: [URL]
    private let disabledTweaks: [String]
    
    init(app: URL, options: SigningOptions, disabledTweaks: [String] = []) {
        self.app = app
        self.options = options
        self.urls = options.injectionFiles
        self.disabledTweaks = disabledTweaks
    }
    
    // MARK: - Main Entry Point
    
    func inject() async throws {
        // ✅ GỌI checkEllekit() TRƯỚC - giống Feather
        try await checkEllekit()
        
        // ✅ SAU ĐÓ mới kiểm tra rỗng
        guard !urls.isEmpty else {
            print("⚠️ No files to inject after ElleKit check")
            return
        }
        
        let baseTmpDir = fileManager.temporaryDirectory
            .appendingPathComponent("ZsignTweak_\(UUID().uuidString)")
        try fileManager.createDirectory(at: baseTmpDir, withIntermediateDirectories: true)
        
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "dylib":
                try await handleDylib(at: url)
            case "deb":
                try await handleDeb(at: url, baseTmpDir: baseTmpDir)
            case "bundle":
                try await handleBundle(at: url)
            case "framework":
                try await handleFramework(at: url)
            default:
                print("Unsupported file type: \(url.lastPathComponent)")
            }
        }
        
        if !directoriesToCheck.isEmpty {
            try await handleDirectories(at: directoriesToCheck)
            
            if !urlsToInject.isEmpty {
                try await handleExtractedContents(at: urlsToInject)
            }
        }
        
        try? fileManager.removeItem(at: baseTmpDir)
    }
    
    // MARK: - ElleKit Support
    
    private func checkEllekit() async throws {
        let frameworksDir = app.appendingPathComponent("Frameworks")
        let substrateFramework = frameworksDir.appendingPathComponent("CydiaSubstrate.framework")
        
        func addEllekit() async throws {
            try fileManager.createDirectory(
                at: frameworksDir,
                withIntermediateDirectories: true
            )
            guard let ellekitURL = Bundle.main.url(forResource: "ellekit", withExtension: "deb") else {
                throw TweakError.ellekitNotFound
            }
            // ✅ Insert vào đầu danh sách để xử lý đầu tiên
            urls.insert(ellekitURL, at: 0)
            print("✅ Added ellekit.deb to injection queue")
        }
        
        // ✅ Logic giống Feather
        if fileManager.fileExists(atPath: substrateFramework.path) {
            if options.experiment_replaceSubstrateWithEllekit {
                print("🔄 Replacing CydiaSubstrate with ElleKit")
                try fileManager.removeItem(at: substrateFramework)
                try await addEllekit()
            } else {
                print("ℹ️ CydiaSubstrate exists, skipping ElleKit injection")
                return
            }
        } else {
            // ✅ Không kiểm tra urls.isEmpty ở đây
            // Vì có thể user chỉ muốn inject ElleKit mà không có tweak khác
            if options.experiment_replaceSubstrateWithEllekit {
                print("📦 No CydiaSubstrate found, adding ElleKit")
                try await addEllekit()
            } else if !urls.isEmpty {
                // ✅ Chỉ add ElleKit nếu có tweaks khác cần inject
                print("📦 Adding ElleKit for existing tweaks")
                try await addEllekit()
            }
        }
    }
    
    // MARK: - Dylib Injection
    
    private func handleDylib(at url: URL) async throws {
        let fileName = url.lastPathComponent
        
        if isDisabled(fileName: fileName) {
            print("⏭️ Skipping disabled tweak: \(fileName)")
            return
        }
        
        var destinationURL = app
        var injectFolder = options.injectFolder
        
        if options.injectFolder.contains(SigningOptions.injectFolderValues[1]) {
            destinationURL = destinationURL.appendingPathComponent("Frameworks")
            try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }
        
        if options.injectPath.contains(SigningOptions.injectPathValues[1]) &&
           options.injectFolder.contains(SigningOptions.injectFolderValues[1]) {
            injectFolder = SigningOptions.injectFolderValues[0]
        }
        
        destinationURL = destinationURL.appendingPathComponent(url.lastPathComponent)
        
        try fileManager.moveFileIfNeeded(from: url, to: destinationURL)
        
        guard let appExec = Bundle(url: app)?.executableURL else {
            throw TweakError.executableNotFound
        }
        
        // ✅ Change CydiaSubstrate path (ignore result like Feather)
        _ = Zsign.changeDylibPath(
            appExecutable: destinationURL.path,
            for: "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            with: "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
        )
        
        // ✅ Inject dylib (ignore result like Feather)
        let injectPath = "\(options.injectPath)\(injectFolder)\(destinationURL.lastPathComponent)"
        _ = Zsign.injectDyLib(
            appExecutable: appExec.path,
            with: injectPath
        )
        
        print("✅ Processed: \(fileName)")
    }
    
    // MARK: - Framework Injection
    
    private func handleFramework(at url: URL) async throws {
        let fileName = url.lastPathComponent
        
        if isDisabled(fileName: fileName) {
            print("⏭️ Skipping disabled framework: \(fileName)")
            return
        }
        
        let frameworksDir = app.appendingPathComponent("Frameworks")
        let destinationURL = frameworksDir.appendingPathComponent(url.lastPathComponent)
        
        try fileManager.createDirectory(
            at: frameworksDir,
            withIntermediateDirectories: true
        )
        
        try fileManager.moveFileIfNeeded(from: url, to: destinationURL)
        
        guard let fExec = Bundle(url: destinationURL)?.executableURL,
              let appExec = Bundle(url: app)?.executableURL else {
            return
        }
        
        // ✅ Change CydiaSubstrate path IN FRAMEWORK (ignore result like Feather)
        _ = Zsign.changeDylibPath(
            appExecutable: fExec.path,
            for: "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            with: "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
        )
        
        // ✅ Inject framework (ignore result like Feather)
        let injectPath = "@executable_path/Frameworks/\(url.lastPathComponent)/\(fExec.lastPathComponent)"
        _ = Zsign.injectDyLib(
            appExecutable: appExec.path,
            with: injectPath
        )
        
        print("✅ Processed framework: \(fileName)")
    }
    
    // MARK: - Bundle Support
    
    private func handleBundle(at url: URL) async throws {
        let fileName = url.lastPathComponent
        
        if isDisabled(fileName: fileName) {
            print("⏭️ Skipping disabled bundle: \(fileName)")
            return
        }
        
        let destinationURL = app.appendingPathComponent(url.lastPathComponent)
        
        try fileManager.moveFileIfNeeded(from: url, to: destinationURL)
        
        print("✅ Copied bundle: \(fileName)")
    }
    
    // MARK: - Deb Handling
    
    private func handleDeb(at url: URL, baseTmpDir: URL) async throws {
        let uniqueSubDir = baseTmpDir.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: uniqueSubDir, withIntermediateDirectories: true)
        
        let ar = AR(with: url)
        let arFiles = try await ar.extract()
        
        for arFile in arFiles {
            let outputPath = uniqueSubDir.appendingPathComponent(arFile.name)
            try arFile.content.write(to: outputPath)
            
            if ["data.tar.lzma", "data.tar.gz", "data.tar.xz", "data.tar.bz2", "data.tar"].contains(arFile.name) {
                var fileToProcess = outputPath
                if arFile.name != "data.tar" {
                    try extractFile(at: &fileToProcess)
                }
                try extractFile(at: &fileToProcess)
                directoriesToCheck.append(fileToProcess)
            }
        }
    }
    
    // MARK: - Directory Handling
    
    private func handleDirectories(at urls: [URL]) async throws {
        let searchPaths: [(path: String, type: String)] = [
            ("Library/Frameworks/", "framework"),
            ("var/jb/Library/Frameworks/", "framework"),
            ("Library/MobileSubstrate/DynamicLibraries/", "dylib"),
            ("var/jb/Library/MobileSubstrate/DynamicLibraries/", "dylib"),
            ("Library/Application Support/", "bundle"),
            ("var/jb/Library/Application Support/", "bundle")
        ]
        
        for baseURL in urls {
            for (path, type) in searchPaths {
                let dirURL = baseURL.appendingPathComponent(path)
                
                guard fileManager.fileExists(atPath: dirURL.path) else {
                    continue
                }
                
                switch type {
                case "dylib":
                    let dylibs = try locateDylibs(in: dirURL)
                    if !dylibs.isEmpty {
                        urlsToInject.append(contentsOf: dylibs)
                    }
                    
                case "framework":
                    let frameworks = try locateFrameworks(in: dirURL)
                    if !frameworks.isEmpty {
                        urlsToInject.append(contentsOf: frameworks)
                    }
                    
                case "bundle":
                    let bundles = try locateBundles(in: dirURL)
                    if !bundles.isEmpty {
                        urlsToInject.append(contentsOf: bundles)
                    }
                    
                default:
                    break
                }
            }
        }
    }
    
    private func handleExtractedContents(at urls: [URL]) async throws {
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "dylib":
                try await handleDylib(at: url)
            case "framework":
                try await handleFramework(at: url)
            case "bundle":
                try await handleBundle(at: url)
            default:
                break
            }
        }
    }
    
    // MARK: - File Locators
    
    private func locateDylibs(in directory: URL) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.filter { url in
            let isSymlink = (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
            return url.pathExtension.lowercased() == "dylib" && !isSymlink
        }
    }
    
    private func locateFrameworks(in directory: URL) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.filter { url in
            let isSymlink = (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
            return url.pathExtension.lowercased() == "framework" && url.hasDirectoryPath && !isSymlink
        }
    }
    
    private func locateBundles(in directory: URL) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.filter { url in
            let isSymlink = (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
            return url.pathExtension.lowercased() == "bundle" && url.hasDirectoryPath && !isSymlink
        }
    }
    
    // MARK: - Disabled Tweaks Check
    
    private func isDisabled(fileName: String) -> Bool {
        if disabledTweaks.contains(fileName) {
            return true
        }
        
        if disabledTweaks.contains("Frameworks/\(fileName)") {
            return true
        }
        
        for disabled in disabledTweaks {
            if disabled.hasSuffix(fileName) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - File Extraction Helper
    
    private func extractFile(at fileURL: inout URL) throws {
        let outputDir = fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        // Implementation depends on your extraction library
        fileURL = outputDir
    }
}

extension FileManager {
    func moveFileIfNeeded(from source: URL, to destination: URL) throws {
        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }
        try moveItem(at: source, to: destination)
    }
}

// MARK: - Errors

enum TweakError: LocalizedError {
    case executableNotFound
    case injectionFailed
    case ellekitNotFound
    case extractionFailed
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "App executable not found"
        case .injectionFailed:
            return "Dylib injection failed"
        case .ellekitNotFound:
            return "ellekit.deb not found in app bundle"
        case .extractionFailed:
            return "Failed to extract deb file"
        }
    }
}
