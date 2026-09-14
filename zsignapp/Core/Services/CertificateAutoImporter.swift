//
//  CertificateAutoImporter.swift
//  zsignapp
//

import Foundation
import Zip
import UIKit
import CoreData

class CertificateAutoImporter: ObservableObject {
    static let shared = CertificateAutoImporter()
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String = ""
    
    private let udidFileName = "udid.txt"
    private let defaultPassword = "1"
    private let importedUDIDsKey = "importedCertificateUDIDs"
    
    private init() {}
    
    func autoImportCertificate() async {
        guard let udid = readUDID() else {
            print("No UDID found in bundle")
            return
        }
        
        // ✅ KIỂM TRA: Đã import UDID này chưa?
        if isAlreadyImported(udid: udid) {
            print("Certificate for UDID \(udid) already imported. Skipping...")
            return
        }
        
        guard let apiBaseURL = getAPIBaseURL() else {
            print("API_CERT not found in Info.plist")
            return
        }
        
        let downloadURL = "\(apiBaseURL)/\(udid)/certificate.zip"
        
        await downloadAndImport(from: downloadURL, udid: udid)
    }
    
    private func readUDID() -> String? {
        guard let path = Bundle.main.path(forResource: "udid", ofType: "txt") else {
            return nil
        }
        
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let udid = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return udid.isEmpty ? nil : udid
        } catch {
            return nil
        }
    }
    
    private func getAPIBaseURL() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "API_CERT") as? String
    }
    
    // ✅ THÊM: Kiểm tra đã import chưa
    private func isAlreadyImported(udid: String) -> Bool {
        let importedUDIDs = UserDefaults.standard.stringArray(forKey: importedUDIDsKey) ?? []
        return importedUDIDs.contains(udid)
    }
    
    // ✅ THÊM: Đánh dấu đã import
    private func markAsImported(udid: String) {
        var importedUDIDs = UserDefaults.standard.stringArray(forKey: importedUDIDsKey) ?? []
        if !importedUDIDs.contains(udid) {
            importedUDIDs.append(udid)
            UserDefaults.standard.set(importedUDIDs, forKey: importedUDIDsKey)
        }
    }
    
    // ✅ THÊM: Kiểm tra xem đã có chứng chỉ nào chưa
    private func hasExistingCertificates() -> Bool {
        let fetchRequest: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        do {
            let count = try Storage.shared.context.count(for: fetchRequest)
            return count > 0
        } catch {
            print("Error checking existing certificates: \(error)")
            return false
        }
    }
    
    private func downloadAndImport(from urlString: String, udid: String) async {
        guard let url = URL(string: urlString) else { return }
        
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
            statusMessage = "Downloading certificate..."
        }
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cert_download_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let zipDestination = tempDir.appendingPathComponent("certificate.zip")
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CertError.invalidResponse
            }
            
            if httpResponse.statusCode == 404 {
                await MainActor.run {
                    isDownloading = false
                    statusMessage = ""
                }
                try? FileManager.default.removeItem(at: tempDir)
                print("Certificate not found for UDID: \(udid)")
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                throw CertError.downloadFailed(statusCode: httpResponse.statusCode)
            }
            
            try data.write(to: zipDestination)
            
            await MainActor.run {
                statusMessage = "Extracting certificate..."
            }
            
            try await extractAndImport(zipURL: zipDestination, tempDir: tempDir)
            
            // ✅ THÊM: Đánh dấu đã import thành công
            markAsImported(udid: udid)
            
            await MainActor.run {
                isDownloading = false
                downloadProgress = 1.0
                statusMessage = "Certificate imported successfully"
            }
            
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                statusMessage = ""
            }
            
            try? FileManager.default.removeItem(at: tempDir)
            
        } catch {
            await MainActor.run {
                isDownloading = false
                statusMessage = ""
            }
            try? FileManager.default.removeItem(at: tempDir)
            print("Certificate auto-import failed: \(error)")
        }
    }
    
    private func extractAndImport(zipURL: URL, tempDir: URL) async throws {
        let extractionDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        
        try Zip.unzipFile(zipURL, destination: extractionDir, overwrite: true, password: nil)
        
        let extractedFiles = try FileManager.default.contentsOfDirectory(
            at: extractionDir,
            includingPropertiesForKeys: nil
        )
        
        var p12File: URL?
        var provisionFile: URL?
        
        for file in extractedFiles {
            let ext = file.pathExtension.lowercased()
            
            if ext == "p12" {
                p12File = file
            } else if ext == "mobileprovision" {
                provisionFile = file
            }
        }
        
        guard let p12 = p12File, let provision = provisionFile else {
            throw CertError.missingFiles
        }
        
        let permanentDir = tempDir.appendingPathComponent("permanent")
        try FileManager.default.createDirectory(at: permanentDir, withIntermediateDirectories: true)
        
        let permanentP12 = permanentDir.appendingPathComponent(p12.lastPathComponent)
        let permanentProvision = permanentDir.appendingPathComponent(provision.lastPathComponent)
        
        try FileManager.default.copyItem(at: p12, to: permanentP12)
        try FileManager.default.copyItem(at: provision, to: permanentProvision)
        
        try await importToDatabase(p12URL: permanentP12, provisionURL: permanentProvision)
    }
    
    private func importToDatabase(p12URL: URL, provisionURL: URL) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        let nickname = "Auto Import \(dateFormatter.string(from: Date()))"
        
        // ✅ THAY ĐỔI: Kiểm tra nếu chưa có chứng chỉ nào thì set làm default
        let shouldBeDefault = !hasExistingCertificates()
        
        let handler = CertificateHandler(
            p12URL: p12URL,
            provisionURL: provisionURL,
            password: defaultPassword,
            nickname: nickname,
            isDefault: shouldBeDefault  // ✅ Thay đổi từ false thành shouldBeDefault
        )
        
        guard handler.validate() else {
            throw CertError.invalidCertificate
        }
        
        try await handler.copy()
        try await handler.addToDatabase()
    }
    
    // ✅ THÊM: Reset (dùng khi test hoặc muốn import lại)
    func resetImportHistory() {
        UserDefaults.standard.removeObject(forKey: importedUDIDsKey)
    }
}

enum CertError: LocalizedError {
    case invalidResponse
    case downloadFailed(statusCode: Int)
    case missingFiles
    case invalidCertificate
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .downloadFailed(let code):
            return "Download failed with status code: \(code)"
        case .missingFiles:
            return "Missing .p12 or .mobileprovision file in ZIP"
        case .invalidCertificate:
            return "Invalid certificate or password"
        }
    }
}
