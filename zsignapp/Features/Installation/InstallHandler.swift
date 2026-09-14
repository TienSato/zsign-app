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
                self?.statusMessage = L("Installing...")
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

        // Nhớ đã cài (bundle id -> version) để phân biệt Cài đặt vs Cập nhật
        InstalledRegistry.record(bundleId: signedApp.identifier, version: signedApp.version)
        
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
        comps.host = "sign.zsign.app"
        comps.path = "/plist"

        comps.queryItems = [
            URLQueryItem(name: "bundleid",   value: signedApp.identifier ?? ""),
            URLQueryItem(name: "name",       value: signedApp.name ?? ""),
            URLQueryItem(name: "version",    value: signedApp.version ?? ""),
            URLQueryItem(name: "fetchurl",   value: "http://127.0.0.1:\(port)/app.ipa"),
            URLQueryItem(name: "smallimage", value: "http://127.0.0.1:\(port)/app57x57.png"),
            URLQueryItem(name: "largeimage", value: "http://127.0.0.1:\(port)/app512x512.png"),
            URLQueryItem(name: "t",          value: String(Int(Date().timeIntervalSince1970)))
        ]

        return comps.url ?? URL(string: "https://sign.zsign.app/error")!
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
