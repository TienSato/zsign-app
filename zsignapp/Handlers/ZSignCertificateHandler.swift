//
//  ZSignCertificateHandler.swift
//  zsignapp
//
//  Created by Sato on 30/10/25.
//

import Foundation
import Zip

// MARK: - ZSign Certificate Handler
struct ZSignCertificateHandler {
    
    // MARK: - Cleanup
    
    /// Clean up old exported certificate files
    static func cleanupOldExports() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tempShareDir = documentsPath.appendingPathComponent("Temp")
        
        guard fileManager.fileExists(atPath: tempShareDir.path) else { return }
        
        // Get all .zsigncert files
        if let files = try? fileManager.contentsOfDirectory(at: tempShareDir, includingPropertiesForKeys: [.creationDateKey]) {
            for file in files where file.pathExtension == "zsigncert" {
                // Delete files older than 1 hour
                if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   Date().timeIntervalSince(creationDate) > 3600 {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
    
    // MARK: - Export
    
    /// Export certificate to .zsigncert file
    static func export(certificate: CertificatePair) async throws -> URL {
        let fileManager = FileManager.default
        
        guard let uuid = certificate.uuid else {
            throw ZSignCertError.invalidCertificate
        }
        
        // Get certificate directory
        let certDirectory = fileManager.certificateDirectory(uuid)
        
        // Check if files exist
        let p12Path = certDirectory.appendingPathComponent("certificate.p12")
        let provisionPath = certDirectory.appendingPathComponent("profile.mobileprovision")
        
        guard fileManager.fileExists(atPath: p12Path.path),
              fileManager.fileExists(atPath: provisionPath.path) else {
            throw ZSignCertError.filesNotFound
        }
        
        // Create temp directory for zip
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }
        
        // Copy files to temp directory
        let tempP12 = tempDirectory.appendingPathComponent("certificate.p12")
        let tempProvision = tempDirectory.appendingPathComponent("profile.mobileprovision")
        
        try fileManager.copyItem(at: p12Path, to: tempP12)
        try fileManager.copyItem(at: provisionPath, to: tempProvision)
        
        // Create metadata file with password and nickname
        let metadata = ZSignCertMetadata(
            password: certificate.password ?? "",
            nickname: certificate.nickname,
            version: "1.0"
        )
        
        let metadataPath = tempDirectory.appendingPathComponent("metadata.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataPath)
        
        // Create zip file name
        let nickname = certificate.nickname ?? "certificate"
        let sanitizedNickname = nickname.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let zipFileName = "\(sanitizedNickname)_\(UUID().uuidString.prefix(8)).zsigncert"
        
        // Create zip in temp location first
        let tempZipPath = tempDirectory.appendingPathComponent(zipFileName)
        
        // Add custom file extension
        Zip.addCustomFileExtension("zsigncert")
        
        // Create zip archive using Zip library
        try Zip.zipFiles(
            paths: [tempP12, tempProvision, metadataPath],
            zipFilePath: tempZipPath,
            password: nil,
            compression: .DefaultCompression,
            progress: nil
        )
        
        // Copy to a more persistent temp location (outside of defer cleanup)
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let finalZipPath = documentsPath.appendingPathComponent("Temp").appendingPathComponent(zipFileName)
        
        // Create Temp directory if needed
        let tempShareDir = documentsPath.appendingPathComponent("Temp")
        if !fileManager.fileExists(atPath: tempShareDir.path) {
            try fileManager.createDirectory(at: tempShareDir, withIntermediateDirectories: true)
        }
        
        // Remove existing file if exists
        if fileManager.fileExists(atPath: finalZipPath.path) {
            try fileManager.removeItem(at: finalZipPath)
        }
        
        // Copy to final location
        try fileManager.copyItem(at: tempZipPath, to: finalZipPath)
        
        return finalZipPath
    }
    
    // MARK: - Import
    
    /// Import certificate from .zsigncert file
    static func `import`(from url: URL, nickname: String?, isDefault: Bool) async throws {
        let fileManager = FileManager.default
        
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Create temp directory for extraction
        let uuid = UUID().uuidString
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("ZSignCertImport_\(uuid)")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }
        
        // Copy file to temp location (like IPAHandler does)
        let copiedZSignCert = tempDirectory.appendingPathComponent(url.lastPathComponent)
        
        try? fileManager.removeItem(at: copiedZSignCert)
        try fileManager.copyItem(at: url, to: copiedZSignCert)
        
        guard fileManager.fileExists(atPath: copiedZSignCert.path) else {
            throw ZSignCertError.invalidZipFile
        }
        
        // Check file size
        let attributes = try fileManager.attributesOfItem(atPath: copiedZSignCert.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        
        guard fileSize > 0 else {
            throw ZSignCertError.invalidZipFile
        }
        
        // Add custom file extension for Zip library
        Zip.addCustomFileExtension("zsigncert")
        
        // Unzip the .zsigncert file using async/await pattern (like IPAHandler)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try Zip.unzipFile(
                        copiedZSignCert,
                        destination: tempDirectory,
                        overwrite: true,
                        password: nil,
                        progress: nil
                    )
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: ZSignCertError.invalidZipFile)
                }
            }
        }
        
        // Read metadata
        let metadataPath = tempDirectory.appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: metadataPath.path) else {
            throw ZSignCertError.missingMetadata
        }
        
        let metadataData = try Data(contentsOf: metadataPath)
        let decoder = JSONDecoder()
        let metadata: ZSignCertMetadata
        
        do {
            metadata = try decoder.decode(ZSignCertMetadata.self, from: metadataData)
        } catch {
            throw ZSignCertError.missingMetadata
        }
        
        // Verify required files exist
        let p12Path = tempDirectory.appendingPathComponent("certificate.p12")
        let provisionPath = tempDirectory.appendingPathComponent("profile.mobileprovision")
        
        let p12Exists = fileManager.fileExists(atPath: p12Path.path)
        let provisionExists = fileManager.fileExists(atPath: provisionPath.path)
        
        guard p12Exists && provisionExists else {
            throw ZSignCertError.filesNotFound
        }
        
        // Use provided nickname or fallback to metadata nickname
        let finalNickname = nickname ?? metadata.nickname
        
        // Create certificate handler and import
        let handler = CertificateHandler(
            p12URL: p12Path,
            provisionURL: provisionPath,
            password: metadata.password,
            nickname: finalNickname,
            isDefault: isDefault
        )
        
        // Validate certificate
        guard handler.validate() else {
            throw CertificateError.passwordMismatch
        }
        
        // Copy files and add to database
        try await handler.copy()
        try await handler.addToDatabase()
    }
}

// MARK: - Zip Certificate Handler

struct ZipCertificateHandler {
    
    /// Import certificate from a ZIP file containing .p12 and .mobileprovision
    static func `import`(from url: URL, password: String, nickname: String?, isDefault: Bool) async throws {
        let fileManager = FileManager.default
        
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Create temp directory for extraction
        let uuid = UUID().uuidString
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("ZipCertImport_\(uuid)")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }
        
        // Copy file to temp location
        let copiedZip = tempDirectory.appendingPathComponent(url.lastPathComponent)
        
        try? fileManager.removeItem(at: copiedZip)
        try fileManager.copyItem(at: url, to: copiedZip)
        
        guard fileManager.fileExists(atPath: copiedZip.path) else {
            throw ZipCertError.invalidZipFile
        }
        
        // Check file size
        let attributes = try fileManager.attributesOfItem(atPath: copiedZip.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        
        guard fileSize > 0 else {
            throw ZipCertError.invalidZipFile
        }
        
        // Add custom file extension for Zip library
        Zip.addCustomFileExtension("zip")
        
        // Unzip the file
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try Zip.unzipFile(
                        copiedZip,
                        destination: tempDirectory,
                        overwrite: true,
                        password: nil,
                        progress: nil
                    )
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: ZipCertError.invalidZipFile)
                }
            }
        }
        
        // Find .p12 and .mobileprovision files recursively
        let (p12Path, provisionPath) = try findCertificateFiles(in: tempDirectory)
        
        // Generate nickname if not provided
        let finalNickname = nickname ?? p12Path.deletingPathExtension().lastPathComponent
        
        // Create certificate handler and import
        let handler = CertificateHandler(
            p12URL: p12Path,
            provisionURL: provisionPath,
            password: password,
            nickname: finalNickname,
            isDefault: isDefault
        )
        
        // Validate certificate
        guard handler.validate() else {
            throw CertificateError.passwordMismatch
        }
        
        // Copy files and add to database
        try await handler.copy()
        try await handler.addToDatabase()
    }
    
    // MARK: - Helper Methods
    
    /// Recursively find .p12 and .mobileprovision files in directory
    private static func findCertificateFiles(in directory: URL) throws -> (p12: URL, provision: URL) {
        let fileManager = FileManager.default
        
        var p12File: URL?
        var provisionFile: URL?
        
        // Function to search recursively
        func searchDirectory(_ dir: URL) throws {
            let contents = try fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    // Recursively search subdirectories
                    try searchDirectory(item)
                } else {
                    // Check file extension
                    if item.pathExtension.lowercased() == "p12" && p12File == nil {
                        p12File = item
                    } else if item.pathExtension.lowercased() == "mobileprovision" && provisionFile == nil {
                        provisionFile = item
                    }
                }
                
                // Early exit if both files found
                if p12File != nil && provisionFile != nil {
                    break
                }
            }
        }
        
        // Start searching
        try searchDirectory(directory)
        
        // Verify both files were found
        guard let p12 = p12File, let provision = provisionFile else {
            throw ZipCertError.filesNotFound
        }
        
        return (p12, provision)
    }
}

// MARK: - ZSignCert Metadata
struct ZSignCertMetadata: Codable {
    let password: String
    let nickname: String?
    let version: String
    let exportDate: Date
    
    init(password: String, nickname: String?, version: String) {
        self.password = password
        self.nickname = nickname
        self.version = version
        self.exportDate = Date()
    }
}

// MARK: - Errors
enum ZSignCertError: LocalizedError {
    case invalidCertificate
    case filesNotFound
    case invalidZipFile
    case missingMetadata
    case unsupportedVersion
    case accessDenied
    
    var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            return "Chứng chỉ không hợp lệ"
        case .filesNotFound:
            return "Không tìm thấy file chứng chỉ"
        case .invalidZipFile:
            return "File .zsigncert không hợp lệ hoặc bị hỏng"
        case .missingMetadata:
            return "Thiếu thông tin metadata trong chứng chỉ"
        case .unsupportedVersion:
            return "Phiên bản chứng chỉ không được hỗ trợ"
        case .accessDenied:
            return "Không thể truy cập file"
        }
    }
}

// MARK: - Zip Certificate Errors
enum ZipCertError: LocalizedError {
    case invalidZipFile
    case filesNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidZipFile:
            return "File ZIP không hợp lệ hoặc bị hỏng"
        case .filesNotFound:
            return "Không tìm thấy file .p12 hoặc .mobileprovision trong ZIP"
        }
    }
}
