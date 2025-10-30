//
//  InstallHandler.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import Foundation
import UIKit
import CommonCrypto

class InstallHandler {
    private let signedApp: SignedApp
    private let port: UInt16 = UInt16.random(in: 4000...8000)
    private var server: SimpleServer?
    private let settings = AppSettings.shared
    
    @Published var status: InstallStatus = .none
    @Published var statusMessage: String = ""
    
    init(signedApp: SignedApp) {
        self.signedApp = signedApp
    }
    
    func install() async throws {
        await updateStatus(.packaging, "Preparing IPA...")
        
        guard let uuid = signedApp.uuid else {
            throw InstallError.invalidApp
        }
        
        let signedDir = FileManager.default.signedAppDirectory(uuid)
        let contents = try FileManager.default.contentsOfDirectory(
            at: signedDir,
            includingPropertiesForKeys: nil
        )
        
        guard let ipaFile = contents.first(where: { $0.pathExtension == "ipa" }) else {
            throw InstallError.ipaNotFound
        }
        
        await updateStatus(.ready, "IPA ready")
        
        server = SimpleServer(
            port: port,
            ipaPath: ipaFile,
            app: signedApp
        )
        
        server?.onInstallationDetected = { [weak self] in
            Task { @MainActor in
                self?.status = .installing
                self?.statusMessage = "Installing..."
            }
        }
        
        server?.onInstallationComplete = { [weak self] in
            Task { @MainActor in
                self?.status = .completed
                self?.statusMessage = "Installation completed!"
                
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.server?.stop()
            }
        }
        
        try server?.start()
        
        await updateStatus(.sendingManifest, "Starting installation...")
        
        let zsignURL = buildZsignURL()
        let iTunesURL = buildITunesLink(manifestURL: zsignURL)
        
        let opened = await openITunesLink(iTunesURL)
        
        if !opened {
            await updateStatus(.broken, "Failed to open link")
            throw InstallError.failedToOpenLink
        }
        
        await updateStatus(.sendingPayload, "Sending to device...")
        
        let maxWaitTime: UInt64 = 900_000_000_000
        let checkInterval: UInt64 = 1_000_000_000
        var elapsed: UInt64 = 0
        
        while elapsed < maxWaitTime {
            if status == .completed {
                break
            }
            
            try await Task.sleep(nanoseconds: checkInterval)
            elapsed += checkInterval
        }
        
        server?.stop()
        
        if status != .completed {
            await updateStatus(.completed, "Installation may have completed")
        }
    }
    
    @MainActor
    private func updateStatus(_ status: InstallStatus, _ message: String) {
        self.status = status
        self.statusMessage = message
    }
    
    private func buildZsignURL() -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "zsign.app"
        comps.path = "/server.php"
        
        let requestData: [String: Any] = [
            "b": signedApp.identifier ?? "",
            "n": signedApp.name ?? "",
            "v": signedApp.version ?? "",
            "f": "http://127.0.0.1:\(port)/app.ipa",
            "s": "http://127.0.0.1:\(port)/app57x57.png",
            "l": "http://127.0.0.1:\(port)/app512x512.png",
            "t": Int(Date().timeIntervalSince1970)
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let encrypted = encryptAES256CBC(
                plaintext: jsonString,
                key: "Satodeptrai"
              ) else {
            return URL(string: "https://zsign.app/error")!
        }
        
        comps.queryItems = [URLQueryItem(name: "d", value: encrypted)]
        return comps.url!
    }
    
    private func buildITunesLink(manifestURL: URL) -> URL {
        var comps = URLComponents()
        comps.scheme = "itms-services"
        comps.path = "/"
        comps.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString)
        ]
        return comps.url!
    }
    
    @MainActor
    private func openITunesLink(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
    
    private func encryptAES256CBC(plaintext: String, key: String) -> String? {
        guard let data = plaintext.data(using: .utf8),
              let keyData = key.data(using: .utf8) else {
            return nil
        }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(keyData.count), &hash)
        }
        let keyBytes = Data(hash).prefix(32)
        
        var iv = Data(repeating: 0, count: 16)
        let copyLength = min(16, keyBytes.count)
        iv.replaceSubrange(0..<copyLength, with: keyBytes.prefix(copyLength))
        
        let cryptLength = data.count + kCCBlockSizeAES128
        var cryptData = Data(count: cryptLength)
        var numBytesEncrypted: size_t = 0
        
        let cryptStatus = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                iv.withUnsafeBytes { ivBytes in
                    keyBytes.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyBytes.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            cryptBytes.baseAddress, cryptLength,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }
        
        guard cryptStatus == kCCSuccess else { return nil }
        
        let encryptedData = cryptData.prefix(numBytesEncrypted)
        return encryptedData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum InstallStatus {
    case none
    case packaging
    case ready
    case sendingManifest
    case sendingPayload
    case installing
    case completed
    case broken
}


enum InstallError: LocalizedError {
    case invalidApp
    case ipaNotFound
    case serverFailed
    case failedToOpenLink
    
    var errorDescription: String? {
        switch self {
        case .invalidApp:
            return "Invalid app"
        case .ipaNotFound:
            return "IPA file not found. Please re-sign the app."
        case .serverFailed:
            return "Failed to start server"
        case .failedToOpenLink:
            return "Failed to open iTunes link"
        }
    }
}
