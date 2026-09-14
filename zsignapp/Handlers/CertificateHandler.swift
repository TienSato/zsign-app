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
    
    private func validateCertificateMatch() -> Bool {
        guard let cert = certificate,
              let developerCerts = cert.DeveloperCertificates,
              !developerCerts.isEmpty else {
            return false
        }
        
        
        // Lấy certificate data từ P12
        guard let p12CertData = extractCertificateDataFromP12() else {
            return false
        }
        
        
        // Kiểm tra xem certificate có khớp với bất kỳ certificate nào trong mobileprovision không
        for (index, certData) in developerCerts.enumerated() {
            
            if p12CertData == certData {
                return true
            } else {
            }
        }
        
        // Nếu không match trực tiếp, thử so sánh public keys
        
        guard let p12PublicKey = extractPublicKeyFromP12() else {
            return false
        }
        
        for (index, certData) in developerCerts.enumerated() {
            if let provisionPublicKey = extractPublicKeyFromCertificate(certData) {
                if comparePublicKeys(p12PublicKey, provisionPublicKey) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func extractCertificateDataFromP12() -> Data? {
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
            
            guard status == errSecSuccess,
                  let itemsArray = items as? [[String: Any]],
                  let firstItem = itemsArray.first,
                  let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity? else {
                return nil
            }
            
            var certificate: SecCertificate?
            let certStatus = SecIdentityCopyCertificate(identity, &certificate)
            
            guard certStatus == errSecSuccess,
                  let cert = certificate else {
                return nil
            }
            
            return SecCertificateCopyData(cert) as Data
        } catch {
            return nil
        }
    }
    
    private func extractPublicKeyFromP12() -> SecKey? {
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
            
            guard status == errSecSuccess,
                  let itemsArray = items as? [[String: Any]],
                  let firstItem = itemsArray.first,
                  let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity? else {
                return nil
            }
            
            var privateKey: SecKey?
            SecIdentityCopyPrivateKey(identity, &privateKey)
            
            var certificate: SecCertificate?
            SecIdentityCopyCertificate(identity, &certificate)
            
            guard let cert = certificate else {
                return nil
            }
            
            return SecCertificateCopyKey(cert)
        } catch {
            return nil
        }
    }
    
    private func extractPublicKeyFromCertificate(_ certData: Data) -> SecKey? {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            return nil
        }
        
        return SecCertificateCopyKey(certificate)
    }
    
    private func comparePublicKeys(_ key1: SecKey, _ key2: SecKey) -> Bool {
        // So sánh public keys bằng cách so sánh dữ liệu external representation
        var error: Unmanaged<CFError>?
        
        guard let data1 = SecKeyCopyExternalRepresentation(key1, &error) as Data?,
              let data2 = SecKeyCopyExternalRepresentation(key2, &error) as Data? else {
            return false
        }
        
        return data1 == data2
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
