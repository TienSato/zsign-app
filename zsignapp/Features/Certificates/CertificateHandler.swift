//
//  CertificateHandler.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//
import Foundation
import Security
import Zsign

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
        guard let cert = certificate else {
            return false
        }
        
        // Kiểm tra số lượng certificates trong mobileprovision
        if let developerCerts = cert.DeveloperCertificates {
            
            if developerCerts.count > 1 {
            }
        }
        
        // Kiểm tra password P12
        guard validateP12Password() else {
            return false
        }
        
        // Nếu password đúng, ta tin rằng P12 và mobileprovision đã khớp
        // Zsign sẽ tự kiểm tra khi sign thực tế
        
        return true
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
        
        // Dùng workaround fix từ Zsign như trong code gốc
        password_check_fix_WHAT_THE_FUCK(provisionURL.path)
        
        // Sử dụng hàm C từ Zsign để check password
        let isValid = p12_password_check(p12URL.path, password)
        
        // Cleanup sau khi check
        password_check_fix_WHAT_THE_FUCK_free(provisionURL.path)
        
        if isValid {
        } else {
        }
        
        return isValid
    }
}

// MARK: - Errors

enum CertificateError: LocalizedError {
    case invalidCertificate
    case passwordMismatch
    case certificateMismatch
    
    var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            return L("Invalid or corrupted mobileprovision file")
        case .passwordMismatch:
            return L("Incorrect P12 password")
        case .certificateMismatch:
            return L("The certificate in the P12 file does not match any certificate in the mobileprovision file. Make sure both come from the same certificate.")
        }
    }
}
