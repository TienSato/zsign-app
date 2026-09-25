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
    
    static func cleanupOldExports() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tempShareDir = documentsPath.appendingPathComponent("Temp")
        
        guard fileManager.fileExists(atPath: tempShareDir.path) else { return }
        
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
    
    static func export(certificate: CertificatePair) async throws -> URL {
        let fileManager = FileManager.default
        
        guard let uuid = certificate.uuid else {
            throw ZSignCertError.invalidCertificate
        }
        
        let certDirectory = fileManager.certificateDirectory(uuid)
        
        let p12Path = certDirectory.appendingPathComponent("certificate.p12")
        let provisionPath = certDirectory.appendingPathComponent("profile.mobileprovision")
        
        guard fileManager.fileExists(atPath: p12Path.path),
              fileManager.fileExists(atPath: provisionPath.path) else {
            throw ZSignCertError.filesNotFound
        }
        
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }
        
        let tempP12 = tempDirectory.appendingPathComponent("certificate.p12")
        let tempProvision = tempDirectory.appendingPathComponent("profile.mobileprovision")
        
        try fileManager.copyItem(at: p12Path, to: tempP12)
        try fileManager.copyItem(at: provisionPath, to: tempProvision)
        
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
        
        let nickname = certificate.nickname ?? "certificate"
        let sanitizedNickname = nickname.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let zipFileName = "\(sanitizedNickname)_\(UUID().uuidString.prefix(8)).zsigncert"
        
        let tempZipPath = tempDirectory.appendingPathComponent(zipFileName)
        
        Zip.addCustomFileExtension("zsigncert")
        
        try Zip.zipFiles(
            paths: [tempP12, tempProvision, metadataPath],
            zipFilePath: tempZipPath,
            password: nil,
            compression: .DefaultCompression,
            progress: nil
        )
        
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let finalZipPath = documentsPath.appendingPathComponent("Temp").appendingPathComponent(zipFileName)
        
        let tempShareDir = documentsPath.appendingPathComponent("Temp")
        if !fileManager.fileExists(atPath: tempShareDir.path) {
            try fileManager.createDirectory(at: tempShareDir, withIntermediateDirectories: true)
        }
        
        if fileManager.fileExists(atPath: finalZipPath.path) {
            try fileManager.removeItem(at: finalZipPath)
        }
        
        try fileManager.copyItem(at: tempZipPath, to: finalZipPath)
        
        return finalZipPath
    }
    
    // MARK: - Import
    
    static func `import`(from url: URL, nickname: String?, isDefault: Bool) async throws {
        let fileManager = FileManager.default
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let uuid = UUID().uuidString
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("ZSignCertImport_\(uuid)")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }
        
        let copiedZSignCert = tempDirectory.appendingPathComponent(url.lastPathComponent)
        
        try? fileManager.removeItem(at: copiedZSignCert)
        try fileManager.copyItem(at: url, to: copiedZSignCert)
        
        guard fileManager.fileExists(atPath: copiedZSignCert.path) else {
            throw ZSignCertError.invalidZipFile
        }
        
        let attributes = try fileManager.attributesOfItem(atPath: copiedZSignCert.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        
        guard fileSize > 0 else {
            throw ZSignCertError.invalidZipFile
        }
        
        Zip.addCustomFileExtension("zsigncert")
        
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
        
        let p12Path = tempDirectory.appendingPathComponent("certificate.p12")
        let provisionPath = tempDirectory.appendingPathComponent("profile.mobileprovision")
        
        let p12Exists = fileManager.fileExists(atPath: p12Path.path)
        let provisionExists = fileManager.fileExists(atPath: provisionPath.path)
        
        guard p12Exists && provisionExists else {
            throw ZSignCertError.filesNotFound
        }
        
        let finalNickname = nickname ?? metadata.nickname
        
        let handler = CertificateHandler(
            p12URL: p12Path,
            provisionURL: provisionPath,
            password: metadata.password,
            nickname: finalNickname,
            isDefault: isDefault
        )
        
        guard handler.validate() else {
            throw CertificateError.passwordMismatch
        }
        
        try await handler.copy()
        try await handler.addToDatabase()
    }
}

// MARK: - Zip Certificate Handler

struct ZipCertificateHandler {
    
    static func `import`(from url: URL, password: String, nickname: String?, isDefault: Bool) async throws {
        let fileManager = FileManager.default
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let uuid = UUID().uuidString
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("ZipCertImport_\(uuid)")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }
        
        let copiedZip = tempDirectory.appendingPathComponent(url.lastPathComponent)
        
        try? fileManager.removeItem(at: copiedZip)
        try fileManager.copyItem(at: url, to: copiedZip)
        
        guard fileManager.fileExists(atPath: copiedZip.path) else {
            throw ZipCertError.invalidZipFile
        }
        
        let attributes = try fileManager.attributesOfItem(atPath: copiedZip.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        
        guard fileSize > 0 else {
            throw ZipCertError.invalidZipFile
        }
        
        Zip.addCustomFileExtension("zip")
        
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
        
        let (p12Path, provisionPath) = try findCertificateFiles(in: tempDirectory)
        
        let finalNickname = nickname ?? p12Path.deletingPathExtension().lastPathComponent
        
        let handler = CertificateHandler(
            p12URL: p12Path,
            provisionURL: provisionPath,
            password: password,
            nickname: finalNickname,
            isDefault: isDefault
        )
        
        guard handler.validate() else {
            throw CertificateError.passwordMismatch
        }
        
        try await handler.copy()
        try await handler.addToDatabase()
    }
    
    // MARK: - Helper Methods
    
    private static func findCertificateFiles(in directory: URL) throws -> (p12: URL, provision: URL) {
        let fileManager = FileManager.default
        
        var p12File: URL?
        var provisionFile: URL?
        
        func searchDirectory(_ dir: URL) throws {
            let contents = try fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    try searchDirectory(item)
                } else {
                    if item.pathExtension.lowercased() == "p12" && p12File == nil {
                        p12File = item
                    } else if item.pathExtension.lowercased() == "mobileprovision" && provisionFile == nil {
                        provisionFile = item
                    }
                }
                
                if p12File != nil && provisionFile != nil {
                    break
                }
            }
        }
        
        try searchDirectory(directory)
        
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
            return L("Invalid certificate")
        case .filesNotFound:
            return L("Certificate file not found")
        case .invalidZipFile:
            return L("Invalid or corrupted .zsigncert file")
        case .missingMetadata:
            return L("Missing metadata in certificate")
        case .unsupportedVersion:
            return L("Unsupported certificate version")
        case .accessDenied:
            return L("Cannot access file")
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
            return L("Invalid or corrupted ZIP file")
        case .filesNotFound:
            return L("No .p12 or .mobileprovision found in the ZIP")
        }
    }
}
