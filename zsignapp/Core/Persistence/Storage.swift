//
// Storage.swift
//  Created by Sato on 26/10/25.
import CoreData
import ZsignSwift

class Storage: ObservableObject {
    static let shared = Storage()
    
    let container: NSPersistentContainer
    
    init() {
        container = NSPersistentContainer(name: "SignApp")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data failed to load")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    var context: NSManagedObjectContext {
        container.viewContext
    }
    // MARK: - Apps
    func addApp(
        uuid: String,
        name: String?,
        identifier: String?,
        version: String?,
        iconFileName: String?
    ) {
        let app = ImportedApp(context: context)
        app.uuid = uuid
        app.name = name
        app.identifier = identifier
        app.version = version
        app.iconFileName = iconFileName
        app.date = Date()
        
        saveContext()
    }
    func fetchApps() -> [ImportedApp] {
        let request = ImportedApp.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ImportedApp.date, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    func deleteApp(_ app: ImportedApp) {
        if let uuid = app.uuid {
            try? FileManager.default.removeItem(at: FileManager.default.appDirectory(uuid))
        }
        
        context.delete(app)
        saveContext()
    }
    func getAppDirectory(for app: ImportedApp) -> URL? {
        guard let uuid = app.uuid else { return nil }
        return FileManager.default.appDirectory(uuid)
    }
    // MARK: - Certificates
    func addCertificate(
        uuid: String,
        password: String?,
        nickname: String?,
        ppqCheck: Bool,
        expiration: Date,
        isDefault: Bool
    ) {
        let cert = CertificatePair(context: context)
        cert.uuid = uuid
        cert.date = Date()
        cert.password = password
        cert.nickname = nickname
        cert.ppqCheck = ppqCheck
        cert.expiration = expiration
        cert.isDefault = isDefault
        cert.revoked = false
        
        saveContext()
        // Check revoked status after adding
        checkRevokedCertificate(for: cert)
    }
    func fetchCertificates() -> [CertificatePair] {
        let request = CertificatePair.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    func deleteCertificate(_ cert: CertificatePair) {
        if let uuid = cert.uuid {
            try? FileManager.default.removeItem(
                at: FileManager.default.certificateDirectory(uuid)
            )
        }
        context.delete(cert)
        saveContext()
    }
    func getCertificateFile(_ type: CertFileType, from cert: CertificatePair) -> URL? {
        guard let uuid = cert.uuid else { return nil }
        
        let dir = FileManager.default.certificateDirectory(uuid)
        let filename = type == .p12 ? "certificate.p12" : "profile.mobileprovision"
        
        return FileManager.default.getPath(in: dir, for: filename)
    }
    func getProvisionDecoded(for cert: CertificatePair) -> Certificate? {
        guard let provisionURL = getCertificateFile(.mobileprovision, from: cert) else {
            return nil
        }
        
        return CertificateReader(provisionURL).decoded
    }
    
    // MARK: - Check Revoked Certificate
    func checkRevokedCertificate(for cert: CertificatePair) {
        guard !cert.revoked else { return }
        let provisionPath = getCertificateFile(.mobileprovision, from: cert)?.path ?? ""
        let p12Path = getCertificateFile(.p12, from: cert)?.path ?? ""
        let p12Password = cert.password ?? ""
        Zsign.checkRevokage(
            provisionPath: provisionPath,
            p12Path: p12Path,
            p12Password: p12Password
        ) { (status, _, _) in
            if status == 1 {
                DispatchQueue.main.async {
                    cert.revoked = true
                    self.saveContext()
                }
            }
        }
    }
    func checkAllRevokedCertificates(completion: @escaping () -> Void) {
        let certificates = fetchCertificates()
        guard !certificates.isEmpty else {
            completion()
            return
        }
        let group = DispatchGroup()
        for cert in certificates {
            guard !cert.revoked else { continue }
            group.enter()
            let provisionPath = getCertificateFile(.mobileprovision, from: cert)?.path ?? ""
            let p12Path = getCertificateFile(.p12, from: cert)?.path ?? ""
            let p12Password = cert.password ?? ""
            Zsign.checkRevokage(
                provisionPath: provisionPath,
                p12Path: p12Path,
                p12Password: p12Password
            ) { (status, _, _) in
                if status == 1 {
                    DispatchQueue.main.async {
                        cert.revoked = true
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.saveContext()
            completion()
        }
    }
    enum CertFileType {
        case p12
        case mobileprovision
    }
    // MARK: - Signed Apps
    func addSignedApp(
        uuid: String,
        sourceUUID: String?,
        certificateUUID: String?,
        name: String?,
        identifier: String?,
        version: String?,
        iconFileName: String?
    ) {
        let signedApp = SignedApp(context: context)
        signedApp.uuid = uuid
        signedApp.date = Date()
        signedApp.sourceUUID = sourceUUID
        signedApp.certificateUUID = certificateUUID
        signedApp.name = name
        signedApp.identifier = identifier
        signedApp.version = version
        signedApp.iconFileName = iconFileName
        
        saveContext()
    }
    func fetchSignedApps() -> [SignedApp] {
        let request = SignedApp.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SignedApp.date, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    func deleteSignedApp(_ app: SignedApp) {
        if let uuid = app.uuid {
            try? FileManager.default.removeItem(
                at: FileManager.default.signedAppDirectory(uuid)
            )
        }
        context.delete(app)
        saveContext()
    }
    // MARK: - Save Context
    func saveContext() {  
        if context.hasChanges {
            do {
                try context.save()
            } catch {
            }
        }
    }
}
