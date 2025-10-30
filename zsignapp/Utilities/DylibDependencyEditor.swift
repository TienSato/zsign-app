//
//  DylibDependencyEditor.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import Foundation
import ZsignSwift

class DylibDependencyEditor {
    private let fileURL: URL
    private let fileManager = FileManager.default
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    // MARK: - Read Dependencies
    
    func getDependencies() -> [String] {
        var dependencies: [String] = []
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return dependencies
        }
        
        // Parse Mach-O header
        var offset = 0
        
        // Read magic
        guard data.count >= 4 else { return dependencies }
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Determine if 64-bit
        let is64bit = (magic == 0xfeedfacf || magic == 0xcffaedfe) // MH_MAGIC_64 or reverse
        
        // Skip to load commands
        offset = is64bit ? 32 : 28 // sizeof(mach_header_64) : sizeof(mach_header)
        
        // Get number of load commands
        guard data.count >= 16 else { return dependencies }
        let ncmds = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 16, as: UInt32.self)
        }
        
        // Parse load commands
        for _ in 0..<ncmds {
            guard offset + 8 <= data.count else { break }
            
            let cmd = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: offset, as: UInt32.self)
            }
            
            let cmdsize = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: offset + 4, as: UInt32.self)
            }
            
            // LC_LOAD_DYLIB = 0xC, LC_LOAD_WEAK_DYLIB = 0x18, LC_REEXPORT_DYLIB = 0x1F
            if cmd == 0xC || cmd == 0x18 || cmd == 0x1F || cmd == 0x80000018 {
                // Path offset is at +24 in dylib_command
                let pathStart = offset + 24
                
                if pathStart < data.count {
                    // Read until null terminator
                    var pathBytes: [UInt8] = []
                    for i in pathStart..<min(pathStart + Int(cmdsize) - 24, data.count) {
                        let byte = data[i]
                        if byte == 0 { break }
                        pathBytes.append(byte)
                    }
                    
                    if let path = String(bytes: pathBytes, encoding: .utf8) {
                        dependencies.append(path)
                    }
                }
            }
            
            offset += Int(cmdsize)
        }
        
        return dependencies
    }
    
    // MARK: - Modify Dependency (Using Zsign)
    
    func replaceDependency(old: String, new: String) throws {
        // Use ZsignSwift's changeDylibPath
        let result = Zsign.changeDylibPath(
            appExecutable: fileURL.path,
            for: old,
            with: new
        )
        
        if result {
        } else {
            throw DependencyError.replacementFailed
        }
    }
}

enum DependencyError: LocalizedError {
    case cannotReadFile
    case replacementFailed
    case dependencyNotFound
    
    var errorDescription: String? {
        switch self {
        case .cannotReadFile:
            return "Cannot read dylib file"
        case .replacementFailed:
            return "Failed to replace dependency path"
        case .dependencyNotFound:
            return "Dependency not found in dylib"
        }
    }
}
