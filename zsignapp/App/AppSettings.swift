//
//  AppSettings.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import Foundation
import Zip

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Keys
    private enum Keys {
        static let compressionLevel = "compressionLevel"
        static let compressionLevelIsSet = "compressionLevel_isSet"
        static let backgroundAudioEnabled = "zsignapp.backgroundAudioEnabled"
        
        static let autoSignAfterDownload = "zsignapp.autoSignAfterDownload"
    }
    
    // MARK: - Settings
  
    @Published var compressionLevel: Int {
        didSet {
            defaults.set(compressionLevel, forKey: Keys.compressionLevel)
            defaults.set(true, forKey: Keys.compressionLevelIsSet)
        }
    }
    
    @Published var backgroundAudioEnabled: Bool {
        didSet {
            defaults.set(backgroundAudioEnabled, forKey: Keys.backgroundAudioEnabled)
            
            if backgroundAudioEnabled {
                BackgroundAudioManager.shared.startBackgroundAudio()
            } else {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
    }
    
    @Published var autoSignAfterDownload: Bool {
        didSet {
            defaults.set(autoSignAfterDownload, forKey: Keys.autoSignAfterDownload)
        }
    }
    
    // MARK: - Init
    private init() {
        
        
        // Migrate old compression settings
        CompressionMigrationHelper.migrateCompressionSetting(key: Keys.compressionLevel)
        
        let savedLevel = defaults.integer(forKey: Keys.compressionLevel)
        
        if savedLevel == 0 && !defaults.bool(forKey: Keys.compressionLevelIsSet) {
            self.compressionLevel = 1  // BestSpeed (fastest)
        } else {
            self.compressionLevel = savedLevel
        }
        
        self.backgroundAudioEnabled = defaults.bool(forKey: Keys.backgroundAudioEnabled)
        
        self.autoSignAfterDownload = defaults.bool(forKey: Keys.autoSignAfterDownload)
    }
    
    // MARK: - Helpers
    
    var compressionType: CompressionLevel {
        return CompressionLevel.from(rawValue: compressionLevel)
    }
    
    func setCompressionType(_ level: CompressionLevel) {
        compressionLevel = level.intValue
    }
    
    var compressionRawValue: Int {
        return compressionLevel
    }
    
    // MARK: - Reset to Default
    func resetToDefaults() {
        
        compressionLevel = 1  // BestSpeed (default)
        backgroundAudioEnabled = false
        
        autoSignAfterDownload = false
        
        // Clear the "isSet" flag
        defaults.removeObject(forKey: Keys.compressionLevelIsSet)
    }
}
