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

    @Published var lastError: String?

    private let certLinkFileName = "cc365-cert"
    private let defaultPassword = "1"
    private let importedUDIDsKey = "importedCertificateUDIDs"

    private let passwordFileNames = ["password.txt", "pass.txt"]

    private init() {}

    func autoImportCertificate() async {
        guard let udid = readUDID() else {
            log("Không có udid.txt trong bundle — bỏ qua.")
            return
        }

        if isAlreadyImported(udid: udid) {
            return
        }

        guard let downloadURL = certificateDownloadURL(udid: udid) else {
            log("Chưa cấu hình được địa chỉ tải chứng chỉ — bỏ qua.")
            return
        }

        await downloadAndImport(from: downloadURL, udid: udid)
    }

    // MARK: - Đọc cấu hình đã vá vào bundle

    private func readUDID() -> String? {
        readBundleText(resource: "udid")
    }

    private func certificateDownloadURL(udid: String) -> String? {
        if let link = readBundleText(resource: certLinkFileName),
           link.lowercased().hasPrefix("https://") || link.lowercased().hasPrefix("http://") {
            return link
        }

        guard let apiBaseURL = getAPIBaseURL() else { return nil }
        let goc = apiBaseURL.hasSuffix("/") ? String(apiBaseURL.dropLast()) : apiBaseURL
        return "\(goc)/\(udid)/certificate.zip"
    }

    private func readBundleText(resource: String) -> String? {
        guard let path = Bundle.main.path(forResource: resource, ofType: "txt") else {
            return nil
        }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    private func getAPIBaseURL() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "API_CERT") as? String
    }

    private func isAlreadyImported(udid: String) -> Bool {
        let importedUDIDs = UserDefaults.standard.stringArray(forKey: importedUDIDsKey) ?? []
        return importedUDIDs.contains(udid)
    }

    private func markAsImported(udid: String) {
        var importedUDIDs = UserDefaults.standard.stringArray(forKey: importedUDIDsKey) ?? []
        if !importedUDIDs.contains(udid) {
            importedUDIDs.append(udid)
            UserDefaults.standard.set(importedUDIDs, forKey: importedUDIDsKey)
        }
    }

    private func hasExistingCertificates() -> Bool {
        let fetchRequest: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
        fetchRequest.fetchLimit = 1

        do {
            let count = try Storage.shared.context.count(for: fetchRequest)
            return count > 0
        } catch {
            return false
        }
    }

    // MARK: - Tải và nhập

    private func downloadAndImport(from urlString: String, udid: String) async {
        guard let url = URL(string: urlString) else {
            await fail("Địa chỉ tải chứng chỉ không hợp lệ: \(urlString)")
            return
        }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
            statusMessage = "Downloading certificate..."
            lastError = nil
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

            // 404 = đơn này chưa có chứng chỉ. Không phải lỗi, lần mở app sau
            // sẽ thử lại.
            if httpResponse.statusCode == 404 {
                log("Chưa có chứng chỉ cho đơn này (404) — sẽ thử lại lần sau.")
                await MainActor.run {
                    isDownloading = false
                    statusMessage = ""
                }
                try? FileManager.default.removeItem(at: tempDir)
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
            // Hiện lý do thật thay vì im lặng. Trước đây mọi nhánh hỏng đều
            // xoá sạch statusMessage, nên một lỗi 404 vì sai đường dẫn trông
            // y hệt lúc chạy bình thường.
            await fail(error.localizedDescription)
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func extractAndImport(zipURL: URL, tempDir: URL) async throws {
        let extractionDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)

        try Zip.unzipFile(zipURL, destination: extractionDir, overwrite: true, password: nil)

        // Quét CẢ thư mục con. Gói do máy chủ tự đóng thì mọi tệp nằm ngay ở
        // gốc, nhưng gói lấy nguyên từ nhà cung cấp thì hay bọc thêm một lớp
        // thư mục — chỉ đọc mức gốc là không thấy gì cả.
        var p12File: URL?
        var provisionFile: URL?
        var passwordFiles: [String: URL] = [:]

        if let walker = FileManager.default.enumerator(at: extractionDir, includingPropertiesForKeys: nil) {
            for case let file as URL in walker {
                let ext = file.pathExtension.lowercased()
                let name = file.lastPathComponent.lowercased()

                // Bỏ qua rác của macOS trong zip
                if file.path.contains("__MACOSX") || name.hasPrefix("._") { continue }

                if ext == "p12" && p12File == nil {
                    p12File = file
                } else if ext == "mobileprovision" && provisionFile == nil {
                    provisionFile = file
                } else if passwordFileNames.contains(name) && passwordFiles[name] == nil {
                    passwordFiles[name] = file
                }
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

        let candidates = passwordCandidates(from: passwordFiles)

        try await importToDatabase(
            p12URL: permanentP12,
            provisionURL: permanentProvision,
            passwordCandidates: candidates
        )
    }

    private func passwordCandidates(from files: [String: URL]) -> [String] {
        var result: [String] = []

        for name in passwordFileNames {
            guard let url = files[name],
                  let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && !result.contains(value) {
                result.append(value)
            }
        }

        if !result.contains(defaultPassword) {
            result.append(defaultPassword)
        }
        // Chứng chỉ không đặt mật khẩu: thử luôn chuỗi rỗng.
        if !result.contains("") {
            result.append("")
        }
        return result
    }

    private func importToDatabase(
        p12URL: URL,
        provisionURL: URL,
        passwordCandidates: [String]
    ) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let nickname = "Auto Import \(dateFormatter.string(from: Date()))"

        let shouldBeDefault = !hasExistingCertificates()

        // Thử từng mật khẩu bằng ĐÚNG hàm kiểm mà app vẫn dùng
        // (CertificateHandler.validate gọi p12_password_check), nên cái nào
        // qua được ở đây thì sau này ký cũng qua.
        for password in passwordCandidates {
            let handler = CertificateHandler(
                p12URL: p12URL,
                provisionURL: provisionURL,
                password: password,
                nickname: nickname,
                isDefault: shouldBeDefault
            )

            guard handler.validate() else { continue }

            try await handler.copy()
            try await handler.addToDatabase()
            let moTaMatKhau = password.isEmpty ? "rỗng" : password
            log("Đã nhập chứng chỉ (mật khẩu: \(moTaMatKhau)).")
            return
        }

        throw CertError.invalidCertificate
    }

    func resetImportHistory() {
        UserDefaults.standard.removeObject(forKey: importedUDIDsKey)
    }

    // MARK: - Báo lỗi

    private func fail(_ message: String) async {
        log("Lỗi: \(message)")
        await MainActor.run {
            isDownloading = false
            lastError = message
            statusMessage = message
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        await MainActor.run {
            if statusMessage == message { statusMessage = "" }
        }
    }

    private func log(_ message: String) {
        print("[CertificateAutoImporter] \(message)")
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
            return "Invalid certificate, or none of the passwords in the ZIP worked"
        }
    }
}
