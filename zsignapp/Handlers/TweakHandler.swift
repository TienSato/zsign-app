//
//  TweakHandler-zsignapp.swift
//  zsignapp
//  Created by Sato on 26/10/25.

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
        // Check if we need to inject anything
        if !options.experiment_replaceSubstrateWithEllekit {
            guard !urls.isEmpty else {
                return
            }
        }
        
        try await checkEllekit()
        
        let baseTmpDir = fileManager.temporaryDirectory
            .appendingPathComponent("ZsignTweak_\(UUID().uuidString)")
        try fileManager.createDirectory(at: baseTmpDir, withIntermediateDirectories: true)
        
        // Process each file
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
        
        // Handle extracted directories from debs
        if !directoriesToCheck.isEmpty {
            try await handleDirectories(at: directoriesToCheck)
            
            if !urlsToInject.isEmpty {
                try await handleExtractedContents(at: urlsToInject)
            }
        }
        
        // Cleanup temp directory
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
            urls.insert(ellekitURL, at: 0)
        }
        
        // Check if CydiaSubstrate.framework exists
        if fileManager.fileExists(atPath: substrateFramework.path) {
            if options.experiment_replaceSubstrateWithEllekit {
                try fileManager.removeItem(at: substrateFramework)
                try await addEllekit()
            } else {
                return
            }
        } else {
            guard !urls.isEmpty else {
                return
            }
            try await addEllekit()
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
        
        // Determine injection location
        if options.injectFolder.contains(SigningOptions.injectFolderValues[1]) {
            destinationURL = destinationURL.appendingPathComponent("Frameworks")
            try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }
        
        // Adjust inject path if using @rpath and Frameworks
        if options.injectPath.contains(SigningOptions.injectPathValues[1]) &&
           options.injectFolder.contains(SigningOptions.injectFolderValues[1]) {
            injectFolder = SigningOptions.injectFolderValues[0]
        }
        
        destinationURL = destinationURL.appendingPathComponent(url.lastPathComponent)
        
        try fileManager.moveFileIfNeeded(from: url, to: destinationURL)
        
        guard let appExec = Bundle(url: app)?.executableURL else {
            throw TweakError.executableNotFound
        }
        
        // Change CydiaSubstrate path
        let changed = Zsign.changeDylibPath(
            appExecutable: destinationURL.path,
            for: "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            with: "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
        )
        
        if !changed {
            print("Failed to change CydiaSubstrate path for: \(fileName)")
        }
        
        // Inject dylib
        let injectPath = "\(options.injectPath)\(injectFolder)\(destinationURL.lastPathComponent)"
        let success = Zsign.injectDyLib(
            appExecutable: appExec.path,
            with: injectPath
        )
        
        if success {
            print("Injected: \(fileName)")
        } else {
            throw TweakError.injectionFailed
        }
    }
    
    // MARK: - Framework Injection
    
    private func handleFramework(at url: URL) async throws {
        let fileName = url.lastPathComponent
        
        if isDisabled(fileName: fileName) {
            print("Skipping disabled framework: \(fileName)")
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
        
        // Change CydiaSubstrate path IN FRAMEWORK
        let changed = Zsign.changeDylibPath(
            appExecutable: fExec.path,
            for: "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            with: "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
        )
        
        if !changed {
            print(" Failed to change CydiaSubstrate path in framework: \(fileName)")
        }
        
        // Inject framework
        let injectPath = "@executable_path/Frameworks/\(url.lastPathComponent)/\(fExec.lastPathComponent)"
        let injected = Zsign.injectDyLib(
            appExecutable: appExec.path,
            with: injectPath
        )
        
        if injected {
            print("Injected framework: \(fileName)")
        } else {
            throw TweakError.injectionFailed
        }
    }
    
    // MARK: - Bundle Support
    
    private func handleBundle(at url: URL) async throws {
        let fileName = url.lastPathComponent
        
        if isDisabled(fileName: fileName) {
            print("Skipping disabled bundle: \(fileName)")
            return
        }
        
        let destinationURL = app.appendingPathComponent(url.lastPathComponent)
        
        try fileManager.moveFileIfNeeded(from: url, to: destinationURL)
        
        print("Copied bundle: \(fileName)")
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
            
            // Extract data.tar variants
            if ["data.tar.lzma", "data.tar.gz", "data.tar.xz", "data.tar.bz2", "data.tar"].contains(arFile.name) {
                var fileToProcess = outputPath
                // Decompress if needed
                if arFile.name != "data.tar" {
                    try extractFile(at: &fileToProcess)
                }
                // Extract tar
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
        // Check exact match
        if disabledTweaks.contains(fileName) {
            return true
        }
        
        // Check with Frameworks/ prefix
        if disabledTweaks.contains("Frameworks/\(fileName)") {
            return true
        }
        
        // Check if any disabled path ends with this filename
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
        // Remove destination if exists
        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }
        // Move (not copy!)
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
