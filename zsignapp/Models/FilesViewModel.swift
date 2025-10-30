//
//  FilesViewModel.swift
//  zsignapp

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Zip
@MainActor
class FilesViewModel: ObservableObject {
    @Published var files: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importStep: String = ""
    
    @Published var isProcessingIPA = false
    @Published var ipaProgress: Double = 0
    @Published var ipaStep: String = ""
    
    @Published var isPackaging = false
    @Published var packagingProgress: Double = 0
    @Published var packagingStep: String = ""
    
    @Published var showDownloadSheet = false
    @Published var downloadURL: String = ""
    @Published var isDownloading = false
    @Published var currentDownload: Download?
    
    private let fileManager = FileManager.default
    private let ipaHandler = IPAHandler()
    private let downloadManager = DownloadManager.shared
    
    var filesDirectory: URL {
        fileManager.filesDirectory
    }
    
    var sortedFiles: [FileItem] {
        files.sorted { $0.dateModified > $1.dateModified }
    }
    
    init() {
        setupIPAHandler()
    }
    
    private func setupIPAHandler() {
        ipaHandler.progressCallback = { [weak self] progress in
            Task { @MainActor in
                self?.ipaProgress = progress
            }
        }
        
        ipaHandler.stepCallback = { [weak self] step in
            Task { @MainActor in
                self?.ipaStep = step
            }
        }
    }
    
    // MARK: - Load Files
    
    func loadFiles() {
        isLoading = true
        
        Task {
            do {
                let urls = try fileManager.contentsOfDirectory(
                    at: filesDirectory,
                    includingPropertiesForKeys: [
                        .fileSizeKey,
                        .creationDateKey,
                        .contentModificationDateKey,
                        .contentTypeKey,
                        .isDirectoryKey
                    ],
                    options: [.skipsHiddenFiles]
                )
                
                var items: [FileItem] = []
                
                for url in urls {
                    let resourceValues = try url.resourceValues(forKeys: [
                        .fileSizeKey,
                        .creationDateKey,
                        .contentModificationDateKey,
                        .isDirectoryKey
                    ])
                    
                    let isDirectory = resourceValues.isDirectory ?? false
                    let size = resourceValues.fileSize.map { Int64($0) } ?? 0
                    let created = resourceValues.creationDate ?? Date()
                    let modified = resourceValues.contentModificationDate ?? Date()
                    
                    let type = UTType(filenameExtension: url.pathExtension)
                    
                    let item = FileItem(
                        url: url,
                        name: url.lastPathComponent,
                        size: size,
                        dateCreated: created,
                        dateModified: modified,
                        type: type,
                        isDirectory: isDirectory
                    )
                    
                    items.append(item)
                }
                
                self.files = items
            } catch {
                showErrorMessage("Failed to load files: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
    
    // MARK: - Import File
    
    func importFile(from url: URL) async {
        isImporting = true
        importProgress = 0
        importStep = "Starting import..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            importProgress = 0.3
            importStep = "Copying file..."
            let destinationURL = filesDirectory.appendingPathComponent(url.lastPathComponent)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            importProgress = 0.6
            importStep = "Saving file..."
            try fileManager.copyItem(at: url, to: destinationURL)
            importProgress = 1.0
            importStep = "Import complete!"
            try await Task.sleep(nanoseconds: 500_000_000)
            loadFiles()
            
        } catch {
            showErrorMessage("Failed to import file: \(error.localizedDescription)")
        }
        
        isImporting = false
    }
    
    // MARK: - Download from URL
    
    func showDownloadDialog() {
        downloadURL = ""
        showDownloadSheet = true
    }
    
    func startDownload() async {
        guard !downloadURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            showErrorMessage("Please enter a valid URL")
            return
        }
        
        guard let url = URL(string: downloadURL.trimmingCharacters(in: .whitespaces)) else {
            showErrorMessage("Invalid URL format")
            return
        }
        
        let fileName = url.lastPathComponent.isEmpty ? "downloaded_file" : url.lastPathComponent
        
        let destinationURL = filesDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            showErrorMessage("File '\(fileName)' already exists in Files")
            return
        }
        
        showDownloadSheet = false
        
        let download = downloadManager.downloadFile(
            from: url,
            fileName: fileName,
            to: filesDirectory
        )
        
        currentDownload = download
        
        Task {
            await monitorDownload(download)
        }
    }
    
    private func monitorDownload(_ download: Download) async {
        isDownloading = true
        importProgress = 0
        importStep = "Starting download..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        while download.status == .downloading || download.status == .importing {
            await MainActor.run {
                importProgress = download.progress
                
                switch download.status {
                case .downloading:
                    let percentage = Int(download.progress * 100)
                    
                    if download.totalBytes > 0 {
                        let downloaded = ByteCountFormatter.string(fromByteCount: download.bytesDownloaded, countStyle: .file)
                        let total = ByteCountFormatter.string(fromByteCount: download.totalBytes, countStyle: .file)
                        
                        if percentage % 5 == 0 {
                            importStep = "Downloading: \(percentage)% (\(downloaded) / \(total))"
                        }
                    } else {
                        importStep = "Downloading: \(percentage)%"
                    }
                    
                case .importing:
                    importStep = "Saving file..."
                    
                default:
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        await MainActor.run {
            if download.status == .completed {
                importProgress = 1.0
                importStep = "Download complete!"
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    loadFiles()
                }
            } else if download.status == .failed {
                importStep = "Download failed"
                showErrorMessage("Download failed. Please try again.")
            } else if download.status == .cancelled {
                importStep = "Download cancelled"
            }
            
            isDownloading = false
            currentDownload = nil
            
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
    }
    
    func importIPAToLibrary(_ file: FileItem) async {
        isProcessingIPA = true
        ipaProgress = 0
        ipaStep = "Preparing to import IPA..."
        
        do {
            try await ipaHandler.importIPA(from: file.url)
            
            ipaStep = "Import successful!"
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
        } catch {
            showErrorMessage("Failed to import IPA: \(error.localizedDescription)")
        }
        
        isProcessingIPA = false
    }
    
    // MARK: - Extract IPA (DÙNG ZIP LIBRARY)
    
    func extractIPA(_ file: FileItem) async {
        isProcessingIPA = true
        ipaProgress = 0
        ipaStep = "Preparing to extract..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        do {
            let extractFolder = filesDirectory.appendingPathComponent(
                file.name.replacingOccurrences(of: ".ipa", with: "")
            )
            
            try? fileManager.removeItem(at: extractFolder)
            try fileManager.createDirectory(at: extractFolder, withIntermediateDirectories: true)
            
            ipaProgress = 0.2
            ipaStep = "Extracting IPA..."
            
            Zip.addCustomFileExtension("ipa")
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    do {
                        try Zip.unzipFile(
                            file.url,  // ← Trực tiếp dùng .ipa file
                            destination: extractFolder,
                            overwrite: true,
                            password: nil,
                            progress: { progress in
                                Task { @MainActor in
                                    let mappedProgress = 0.2 + (progress * 0.7)
                                    self?.ipaProgress = mappedProgress
                                    
                                    let percentage = Int(progress * 100)
                                    if percentage % 10 == 0 {
                                        self?.ipaStep = "Extracting: \(percentage)%"
                                    }
                                }
                            }
                        )
                        
                        continuation.resume()
                        
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            ipaProgress = 1.0
            ipaStep = "Extraction complete!"
            try await Task.sleep(nanoseconds: 1_000_000_000)
            loadFiles()
            
        } catch {
            showErrorMessage("Failed to extract IPA: \(error.localizedDescription)")
        }
        
        isProcessingIPA = false
    }
    
    
    func packageAppToIPA(_ appBundle: FileItem) async {
        isPackaging = true
        packagingProgress = 0
        packagingStep = "Preparing to package..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        do {
            let workDir = fileManager.temporaryDirectory.appendingPathComponent("PackageIPA_\(UUID().uuidString)")
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
            
            packagingProgress = 0.1
            packagingStep = "Creating Payload folder..."
            
            let payloadDir = workDir.appendingPathComponent("Payload")
            try fileManager.createDirectory(at: payloadDir, withIntermediateDirectories: true)
            
            packagingProgress = 0.2
            packagingStep = "Copying .app bundle..."
            
            let destAppBundle = payloadDir.appendingPathComponent(appBundle.name)
            try fileManager.copyItem(at: appBundle.url, to: destAppBundle)
            
            packagingProgress = 0.5
            packagingStep = "Creating IPA archive..."
            
            let ipaName = appBundle.name.replacingOccurrences(of: ".app", with: ".ipa")
            let ipaPath = filesDirectory.appendingPathComponent(ipaName)
            
            try? fileManager.removeItem(at: ipaPath)
            
            let compressionLevel = AppSettings.shared.compressionType
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    do {
                        // Zip with progress callback
                        try Zip.zipFiles(
                            paths: [payloadDir],
                            zipFilePath: ipaPath,
                            password: nil,
                            compression: compressionLevel,
                            progress: { progress in
                                Task { @MainActor in
                                    // Map progress from 0.5 to 0.9
                                    let mappedProgress = 0.5 + (progress * 0.4)
                                    self?.packagingProgress = mappedProgress
                                    
                                    let percentage = Int(progress * 100)
                                    if percentage % 10 == 0 {
                                        self?.packagingStep = "Compressing: \(percentage)%"
                                    }
                                }
                            }
                        )
                        
                        continuation.resume()
                        
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            packagingProgress = 0.95
            packagingStep = "Cleaning up..."
            try? fileManager.removeItem(at: workDir)
            
            packagingProgress = 1.0
            packagingStep = "IPA created successfully!"
            try await Task.sleep(nanoseconds: 1_000_000_000)
            loadFiles()
            
        } catch {
            showErrorMessage("Failed to create IPA: \(error.localizedDescription)")
        }
        
        isPackaging = false
    }
    
    // MARK: - Delete File
    
    func deleteFile(_ file: FileItem) {
        do {
            try fileManager.removeItem(at: file.url)
            files.removeAll { $0.id == file.id }
        } catch {
            showErrorMessage("Failed to delete file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Extract Deb
    
    func extractDeb(_ file: FileItem) async {
        isProcessingIPA = true
        ipaProgress = 0
        ipaStep = "Extracting deb package..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        do {
            let extractFolder = filesDirectory.appendingPathComponent(
                file.name.replacingOccurrences(of: ".deb", with: "")
            )
            
            try? fileManager.removeItem(at: extractFolder)
            try fileManager.createDirectory(at: extractFolder, withIntermediateDirectories: true)
            
            ipaProgress = 0.3
            ipaStep = "Reading deb archive..."
            
            let ar = AR(with: file.url)
            let arFiles = try await ar.extract()
            
            ipaProgress = 0.7
            ipaStep = "Extracting contents..."
            
            for arFile in arFiles {
                let outputPath = extractFolder.appendingPathComponent(arFile.name)
                try arFile.content.write(to: outputPath)
            }
            
            ipaProgress = 1.0
            ipaStep = "Extraction complete!"
            try await Task.sleep(nanoseconds: 1_000_000_000)
            loadFiles()
            
        } catch {
            showErrorMessage("Failed to extract deb: \(error.localizedDescription)")
        }
        
        isProcessingIPA = false
    }
    
    // MARK: - Class Dump
    
    func classDump(_ file: FileItem) async {
        await MainActor.run {
            errorMessage = "Class dump feature - coming soon!\nWould integrate with class-dump tool to extract Objective-C headers from the dylib."
            showError = true
        }
    }
    
    // MARK: - Share File
    
    func shareFile(_ file: FileItem) -> URL {
        return file.url
    }
    
    // MARK: - Error Handling
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
