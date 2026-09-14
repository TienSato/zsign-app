//
//  ZipCompression+Extensions.swift
//  zsignapp
//  Created by Sato on 26/10/25.
//  FIXED: Use Zip library compression enum

import Foundation
import Zip

// ✅ ĐÚNG: ZipCompression là top-level enum, không phải Zip.ZipCompression
typealias CompressionLevel = ZipCompression

extension ZipCompression {
    /// Human-readable label for compression level
    var label: String {
        switch self {
        case .NoCompression:
            return "None"
        case .BestSpeed:
            return "Speed"
        case .DefaultCompression:
            return "Default"
        case .BestCompression:
            return "Best"
        }
    }
    
    /// Detailed description for each level
    var description: String {
        switch self {
        case .NoCompression:
            return "No compression - Fastest (largest file)"
        case .BestSpeed:
            return "Low compression - Very fast"
        case .DefaultCompression:
            return "Balanced - Recommended"
        case .BestCompression:
            return "Maximum compression - Slowest (smallest file)"
        }
    }
    
    /// Icon for each level
    var icon: String {
        switch self {
        case .NoCompression:
            return "hare.fill"
        case .BestSpeed:
            return "hare.fill"
        case .DefaultCompression:
            return "tortoise.fill"
        case .BestCompression:
            return "snail.fill"
        }
    }
    
    /// Color for each level
    var color: String {
        switch self {
        case .NoCompression:
            return "green"
        case .BestSpeed:
            return "green"
        case .DefaultCompression:
            return "orange"
        case .BestCompression:
            return "red"
        }
    }
    
    /// Convert from Int to CompressionLevel
    static func from(rawValue: Int) -> ZipCompression {
        switch rawValue {
        case 0:
            return .NoCompression
        case 1:
            return .BestSpeed
        case 2:
            return .DefaultCompression
        case 3, 9:
            return .BestCompression
        default:
            return .BestSpeed  // Default to fastest
        }
    }
    
    /// Convert CompressionLevel to Int for storage
    var intValue: Int {
        return self.rawValue
    }
    
    /// Convert from old ZipCompression rawValue (for migration)
    static func fromLegacyRawValue(_ rawValue: Int) -> ZipCompression {
        return from(rawValue: rawValue)
    }
}

// MARK: - Codable Support

extension ZipCompression: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        self = ZipCompression.from(rawValue: rawValue)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.intValue)
    }
}

// MARK: - Equatable & Hashable

extension ZipCompression: Equatable {
    public static func == (lhs: ZipCompression, rhs: ZipCompression) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

extension ZipCompression: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

// MARK: - Migration Helper

struct CompressionMigrationHelper {
    static func migrateCompressionSetting(key: String = "compressionLevel") {
        let defaults = UserDefaults.standard
        
        if let oldRawValue = defaults.object(forKey: key) as? Int {
            let newLevel = ZipCompression.from(rawValue: oldRawValue)
            defaults.set(newLevel.intValue, forKey: key)
        }
    }
}
