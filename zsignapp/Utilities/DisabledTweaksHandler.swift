//
//  DisabledTweaksHandler.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//  FIXED: Don't verify immediately after removal
//

import Foundation
import ZsignSwift

class DisabledTweaksHandler {
    private let fileManager = FileManager.default
    private let appURL: URL
    private let disabledTweaks: [String]
    
    init(appURL: URL, disabledTweaks: [String]) {
        self.appURL = appURL
        self.disabledTweaks = disabledTweaks
    }
    
    // MARK: - Main Function
    
    func removeDisabledTweaks() throws {
        guard !disabledTweaks.isEmpty else {
            return
        }
        
        guard let bundle = Bundle(url: appURL),
              let execURL = bundle.executableURL else {
            throw DisabledTweaksError.executableNotFound
        }
        
        let execPath = appURL.appendingPathComponent(execURL.relativePath).path
        
        print("Removing \(disabledTweaks.count) disabled tweak(s)")
        
        // List current load commands
        let currentLoadCommands = Zsign.listDylibs(appExecutable: execPath)
        
        // Build exact list of load commands to remove
        var loadCommandsToRemove: [String] = []
        
        for tweakPath in disabledTweaks {
            // Find matching load commands for this tweak
            let tweakName = (tweakPath as NSString).lastPathComponent
            let tweakNameNoExt = (tweakName as NSString).deletingPathExtension
            
            for loadCommand in currentLoadCommands {
                if loadCommand.contains(tweakName) ||
                   loadCommand.contains(tweakNameNoExt) ||
                   loadCommand.hasSuffix(tweakName) {
                    if !loadCommandsToRemove.contains(loadCommand) {
                        loadCommandsToRemove.append(loadCommand)
                        print("   → Will remove: \(loadCommand)")
                    }
                }
            }
        }
        
        // Remove load commands
        if !loadCommandsToRemove.isEmpty {
            let success = Zsign.removeDylibs(
                appExecutable: execPath,
                using: loadCommandsToRemove
            )
            
            if !success {
                throw DisabledTweaksError.removalFailed
            }
            
            print("✅ Successfully removed \(loadCommandsToRemove.count) load command(s)")
        } else {
            print("⚠️ No matching load commands found to remove")
        }
    }
    
    // MARK: - Verification (Optional - call later if needed)
    
    func verifyRemoval() -> Bool {
        // Wait for binary to be fully written first
        
        guard let bundle = Bundle(url: appURL),
              let execURL = bundle.executableURL else {
            return false
        }
        
        let execPath = appURL.appendingPathComponent(execURL.relativePath).path
        
        // Add small delay to ensure binary is flushed
        Thread.sleep(forTimeInterval: 0.1)
        
        let remainingDylibs = Zsign.listDylibs(appExecutable: execPath)
        
        var allRemoved = true
        
        for tweakPath in disabledTweaks {
            let fileName = (tweakPath as NSString).lastPathComponent
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            
            for loadCommand in remainingDylibs {
                if loadCommand.contains(fileName) || loadCommand.contains(nameWithoutExt) {
                    print("Load command still exists: \(loadCommand)")
                    allRemoved = false
                    break
                }
            }
        }
        
        return allRemoved
    }
    
    func cleanup() {
        // Nothing to clean up
    }
}

// MARK: - Error
enum DisabledTweaksError: LocalizedError {
    case executableNotFound
    case removalFailed
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "App executable not found"
        case .removalFailed:
            return "Failed to remove load commands"
        }
    }
}
