//
//  AutoSignHelper.swift
//  zsignapp
//  Created by Sato on 31/10/25.

import Foundation
import UIKit

class AutoSignHelper {
    static let shared = AutoSignHelper()
    
    private init() {}
    
    func handleDownloadCompletion(downloadId: String, appName: String) async {
        let settings = AppSettings.shared
        
        guard settings.autoSignAfterDownload else {
            return
        }
        
        await MainActor.run {
            AutoSignProgressManager.shared.start(appName: appName)
        }
        
        guard let certificate = getDefaultCertificate() else {
            await MainActor.run {
                AutoSignProgressManager.shared.fail(error: "No default certificate")
            }
            return
        }
        
        await MainActor.run {
            AutoSignProgressManager.shared.updateProgress(0.1, step: "Waiting for import to finish...")
        }
        
        var attempts = 0
        var importedApp: ImportedApp?
        
        while attempts < 30 && importedApp == nil {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            importedApp = findRecentlyImportedApp(appName: appName)
            attempts += 1
            
            await MainActor.run {
                AutoSignProgressManager.shared.updateProgress(
                    0.1 + (Double(attempts) / 30.0 * 0.1),
                    step: L("Waiting for import...") + " (\(attempts)s)"
                )
            }
        }
        
        guard let importedApp = importedApp else {
            await MainActor.run {
                AutoSignProgressManager.shared.fail(error: "App not found")
            }
            return
        }
        
        await MainActor.run {
            AutoSignProgressManager.shared.updateProgress(0.2, step: "Starting to sign...")
        }
        
        BackgroundAudioManager.shared.startBackgroundAudio(force: true)
        
        do {
            var options = SigningOptionsManager.shared.options
            
            let handler = SigningHandler(
                sourceApp: importedApp,
                certificate: certificate,
                options: options,
                customIcon: nil,
                disabledTweaks: []
            )
            
            handler.stepProgressCallback = { step in
                Task { @MainActor in
                    let progress = self.parseSigningProgress(from: step)
                    AutoSignProgressManager.shared.updateProgress(
                        0.2 + (progress * 0.5),
                        step: step
                    )
                }
            }
            
            try await handler.performFullSigning()
            
            await MainActor.run {
                AutoSignProgressManager.shared.updateProgress(0.7, step: "Signed successfully!")
            }
            
            await handleAutoInstall(for: importedApp, downloadId: downloadId)
            
        } catch {
            await MainActor.run {
                AutoSignProgressManager.shared.fail(error: error.localizedDescription)
            }
        }
        
        if DownloadManager.shared.downloads.isEmpty {
            if !settings.backgroundAudioEnabled {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
    }
    
    private func parseSigningProgress(from step: String) -> Double {
        if step.contains("Preparing") || step.contains("Preparing") {
            return 0.0
        } else if step.contains("Extracting") || step.contains("Extracting") {
            return 0.1
        } else if step.contains("Reading") || step.contains("Reading") {
            return 0.2
        } else if step.contains("Processing") || step.contains("Processing") {
            return 0.4
        } else if step.contains("Signing") || step.contains("Signing") {
            return 0.6
        } else if step.contains("Packaging") || step.contains("Packaging") {
            return 0.8
        } else if step.contains("Finalizing") || step.contains("Finishing") {
            return 0.95
        }
        return 0.5
    }
    
    private func getDefaultCertificate() -> CertificatePair? {
        let certificates = Storage.shared.fetchCertificates()
        
        if let defaultCert = certificates.first(where: { $0.isDefault }) {
            return defaultCert
        }
        
        if let firstValid = certificates.first(where: { !$0.revoked }) {
            return firstValid
        }
        
        if let firstCert = certificates.first {
            return firstCert
        }
        
        return nil
    }
    
    private func findRecentlyImportedApp(appName: String) -> ImportedApp? {
        let context = Storage.shared.container.viewContext
        let fetchRequest = ImportedApp.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ImportedApp.date, ascending: false)]
        fetchRequest.fetchLimit = 10
        
        if let results = try? context.fetch(fetchRequest) {
            let twoMinutesAgo = Date().addingTimeInterval(-120)
            
            if let exactMatch = results.first(where: { app in
                guard let importDate = app.date else { return false }
                return importDate > twoMinutesAgo && app.name == appName
            }) {
                return exactMatch
            }
            
            if let latestApp = results.first,
               let importDate = latestApp.date,
               importDate > twoMinutesAgo {
                return latestApp
            }
        }
        
        return nil
    }
    
    private func handleAutoInstall(for app: ImportedApp, downloadId: String) async {
        await MainActor.run {
            AutoSignProgressManager.shared.updateProgress(0.75, step: "Preparing to install...")
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        await MainActor.run {
            AutoSignProgressManager.shared.updateProgress(0.8, step: "Looking for the signed app...")
        }
        
        guard let signedApp = findRecentlySignedApp(bundleID: app.identifier ?? "") else {
            await MainActor.run {
                AutoSignProgressManager.shared.fail(error: "Signed app not found")
            }
            return
        }
        
        await MainActor.run {
            AutoSignProgressManager.shared.updateProgress(0.85, step: "Installing...")
        }
        
        let installHandler = InstallHandler(signedApp: signedApp)
        
        Task.detached {
            try? await installHandler.install()
        }
        
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        await MainActor.run {
            AutoSignProgressManager.shared.updateProgress(0.95, step: "Installation complete!")
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await MainActor.run {
            AutoSignProgressManager.shared.updateProgress(1.0, step: "Done!")
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await MainActor.run {
            AutoSignProgressManager.shared.finish()
        }
    }
    
    private func findRecentlySignedApp(bundleID: String) -> SignedApp? {
        let context = Storage.shared.container.viewContext
        let fetchRequest = SignedApp.fetchRequest()
        
        // Sort: mới nhất trước
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \SignedApp.date, ascending: false)
        ]
        
        fetchRequest.predicate = NSPredicate(
            format: "identifier == %@", bundleID
        )
        
        fetchRequest.fetchLimit = 1
        
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        
        if let results = try? context.fetch(fetchRequest),
           let signedApp = results.first,
           let signedDate = signedApp.date,
           signedDate > twoMinutesAgo {
            return signedApp
        }
        
        return nil
    }
}
