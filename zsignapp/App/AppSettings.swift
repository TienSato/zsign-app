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
        
        // ✅ THÊM MỚI: Chỉ cần 2 keys (bỏ certificate UUID key)
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
            
            // Apply immediately
            if backgroundAudioEnabled {
                BackgroundAudioManager.shared.startBackgroundAudio()
            } else {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
    }
    
    // ✅ THÊM MỚI: Chỉ cần 2 settings đơn giản
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
        
        // Default to BestSpeed (1) if not set
        if savedLevel == 0 && !defaults.bool(forKey: Keys.compressionLevelIsSet) {
            self.compressionLevel = 1  // BestSpeed (fastest)
        } else {
            self.compressionLevel = savedLevel
        }
        
        // Load background audio setting
        self.backgroundAudioEnabled = defaults.bool(forKey: Keys.backgroundAudioEnabled)
        
        // ✅ THÊM MỚI: Load auto sign settings
        self.autoSignAfterDownload = defaults.bool(forKey: Keys.autoSignAfterDownload)
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
        
        compressionLevel = 1  // BestSpeed (default)
        backgroundAudioEnabled = false
        
        // ✅ THÊM MỚI: Reset auto sign settings
        autoSignAfterDownload = false
        
        // Clear the "isSet" flag
        defaults.removeObject(forKey: Keys.compressionLevelIsSet)
    }
}
