//
//  SigningOptionsManager.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import Foundation
import UIKit

class SigningOptionsManager: ObservableObject {
    static let shared = SigningOptionsManager()
    
    @Published var options: SigningOptions
    private let key = "zsignapp_signing_options"
    
    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let savedOptions = try? JSONDecoder().decode(SigningOptions.self, from: data) {
            self.options = savedOptions
        } else {
            self.options = SigningOptions.createDefaultOptions()
            self.saveOptions()
        }
    }
    
    func saveOptions() {
        if let encoded = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(encoded, forKey: key)
            objectWillChange.send()
        }
    }
    
    func resetToDefaults() {
        options = SigningOptions.createDefaultOptions()
        saveOptions()
    }
}
struct SigningOptions: Codable, Equatable {
    // Basic info
    var appName: String?
    var appVersion: String?
    var appIdentifier: String?
    var appAppearance: String
    var minimumAppRequirement: String
    // Injection
    var injectPath: String
    var injectFolder: String
    // Protection
    var ppqString: String
    var ppqProtection: Bool
    var dynamicProtection: Bool
    // Features
    var fileSharing: Bool
    var itunesFileSharing: Bool
    var proMotion: Bool
    var gameMode: Bool
    var ipadFullscreen: Bool
    // Removal
    var removeSupportedDevices: Bool
    var removeURLScheme: Bool
    var removeProvisioning: Bool
    var removeWatchPlaceholder: Bool
    var removeFiles: [String]
    // Experimental
    var experiment_supportLiquidGlass: Bool
    var experiment_replaceSubstrateWithEllekit: Bool
    // Custom Info.plist
    var customInfoPlistEntries: [String: String]
    // Injection files
    var injectionFiles: [URL]
    var disInjectionFiles: [String]
    // Remove provision after signing
    var removeProvisionAfterSigning: Bool
    static func createDefaultOptions() -> SigningOptions {
        return SigningOptions(
            appName: nil,
            appVersion: nil,
            appIdentifier: nil,
            appAppearance: appAppearanceValues[0],
            minimumAppRequirement: appMinimumAppRequirementValues[0],
            injectPath: injectPathValues[0],
            injectFolder: injectFolderValues[1],
            ppqString: randomString(),
            ppqProtection: false,
            dynamicProtection: false,
            fileSharing: false,
            itunesFileSharing: false,
            proMotion: false,
            gameMode: false,
            ipadFullscreen: false,
            removeSupportedDevices: false,
            removeURLScheme: false,
            removeProvisioning: false,
            removeWatchPlaceholder: false,
            removeFiles: [],
            experiment_supportLiquidGlass: false,
            experiment_replaceSubstrateWithEllekit: IOSVersionHelper.shouldEnableElleKitByDefault(), // ← Auto enable on iOS 26+
            customInfoPlistEntries: [:],
            injectionFiles: [],
            disInjectionFiles: [],
            removeProvisionAfterSigning: false
        )
    }
    static let appAppearanceValues = ["Default", "Light", "Dark"]
    static let appMinimumAppRequirementValues = ["Default", "16.0", "15.0", "14.0", "13.0", "12.0"]
    static let injectPathValues = ["@executable_path", "@rpath"]
    static let injectFolderValues = ["/", "/Frameworks/"]
    
    static func randomString() -> String {
        let letters = UUID().uuidString
        return String((0..<6).compactMap { _ in letters.randomElement() })
    }
}
