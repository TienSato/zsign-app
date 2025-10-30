//
//  CertificateHandler.swift
//  zsignapp
//
//  Created by Sato on 26/10/25. 
//
import Foundation
import Security

class CertificateHandler {
    private let fileManager = FileManager.default
    private let uuid = UUID().uuidString
    
    private let p12URL: URL
    private let provisionURL: URL
    private let password: String
    private let nickname: String?
    private let isDefault: Bool
    
    private var certificate: Certificate?
    
    init(
        p12URL: URL,
        provisionURL: URL,
        password: String,
        nickname: String? = nil,
        isDefault: Bool = false
    ) {
        self.p12URL = p12URL
        self.provisionURL = provisionURL
        self.password = password
        self.nickname = nickname
        self.isDefault = isDefault
        
        self.certificate = CertificateReader(provisionURL).decoded
    }
    
    func validate() -> Bool {
        guard certificate != nil else {
            return false
        }
        
        return validateP12Password()
    }
    
    func copy() async throws {
        let destinationDirectory = fileManager.certificateDirectory(uuid)
        
        let p12Destination = destinationDirectory.appendingPathComponent("certificate.p12")
        try fileManager.copyItem(at: p12URL, to: p12Destination)
        
        let provisionDestination = destinationDirectory.appendingPathComponent("profile.mobileprovision")
        try fileManager.copyItem(at: provisionURL, to: provisionDestination)
    }
    
    func addToDatabase() async throws {
        guard let cert = certificate else {
            throw CertificateError.invalidCertificate
        }
        
        await MainActor.run {
            Storage.shared.addCertificate(
                uuid: uuid,
                password: password,
                nickname: nickname,
                ppqCheck: cert.PPQCheck ?? false,
                expiration: cert.ExpirationDate,
                isDefault: isDefault
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func validateP12Password() -> Bool {
        do {
            let p12Data = try Data(contentsOf: p12URL)
            let options: [String: Any] = [
                kSecImportExportPassphrase as String: password
            ]
            
            var items: CFArray?
            let status = SecPKCS12Import(
                p12Data as CFData,
                options as CFDictionary,
                &items
            )
            
            return status == errSecSuccess
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum CertificateError: LocalizedError {
    case invalidCertificate
    case passwordMismatch
    
    var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            return "Invalid mobileprovision file"
        case .passwordMismatch:
            return "Incorrect P12 password"
        }
    }
}
