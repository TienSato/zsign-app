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
        static let autoCleanTemp = "autoCleanTemp"
        static let showDebugLog = "showDebugLog"
        static let compressionLevel = "compressionLevel"
        static let compressionLevelIsSet = "compressionLevel_isSet"
        static let backgroundAudioEnabled = "zsignapp.backgroundAudioEnabled"
    }
    
    // MARK: - Settings
    @Published var autoCleanTemp: Bool {
        didSet {
            defaults.set(autoCleanTemp, forKey: Keys.autoCleanTemp)
        }
    }
    
    @Published var showDebugLog: Bool {
        didSet {
            defaults.set(showDebugLog, forKey: Keys.showDebugLog)
        }
    }
    
    @Published var compressionLevel: Int {
        didSet {
            defaults.set(compressionLevel, forKey: Keys.compressionLevel)
            defaults.set(true, forKey: Keys.compressionLevelIsSet)
        }
    }
    
    @Published var backgroundAudioEnabled: Bool {
        didSet {
            defaults.set(backgroundAudioEnabled, forKey: Keys.backgroundAudioEnabled)
            
            // Apply immediately
            if backgroundAudioEnabled {
                BackgroundAudioManager.shared.startBackgroundAudio()
            } else {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
    }
    
    // MARK: - Init
    private init() {
        self.autoCleanTemp = defaults.bool(forKey: Keys.autoCleanTemp)
        self.showDebugLog = defaults.bool(forKey: Keys.showDebugLog)
        
        // Migrate old compression settings
        CompressionMigrationHelper.migrateCompressionSetting(key: Keys.compressionLevel)
        
        let savedLevel = defaults.integer(forKey: Keys.compressionLevel)
        
        // Default to BestSpeed (1) if not set
        if savedLevel == 0 && !defaults.bool(forKey: Keys.compressionLevelIsSet) {
            self.compressionLevel = 1  // BestSpeed (fastest)
        } else {
            self.compressionLevel = savedLevel
        }
        
        // Load background audio setting
        self.backgroundAudioEnabled = defaults.bool(forKey: Keys.backgroundAudioEnabled)
    }
    
    // MARK: - Helpers
    
    /// Get current compression type (CompressionLevel)
    var compressionType: CompressionLevel {
        return CompressionLevel.from(rawValue: compressionLevel)
    }
    
    /// Set compression type from CompressionLevel
    func setCompressionType(_ level: CompressionLevel) {
        compressionLevel = level.intValue
    }
    
    /// Get raw Int value for low-level usage
    var compressionRawValue: Int {
        return compressionLevel
    }
    
    // MARK: - Reset to Default
    func resetToDefaults() {
        autoCleanTemp = false
        showDebugLog = false
        compressionLevel = 1  // BestSpeed (default)
        backgroundAudioEnabled = false
        
        // Clear the "isSet" flag
        defaults.removeObject(forKey: Keys.compressionLevelIsSet)
    }
}
