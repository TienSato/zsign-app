
//Filemanager+Extensions.swift
//  Created by Sato on 26/10/25.

import Foundation

extension FileManager {
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func createDirectoryIfNeeded(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    func removeFileIfNeeded(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
    
    // MARK: - Setup All Directories
    
    func setupAppDirectories() {
        let directories = [
            documentsDirectory,
            appsDirectory,
            certificatesDirectory,
            signedAppsDirectory,
            filesDirectory
        ]
        
        for directory in directories {
            do {
                try createDirectoryIfNeeded(at: directory)
            } catch {
            }
        }
        
    }
    
    // MARK: - Apps
    
    var appsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Apps")
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func appDirectory(_ uuid: String) -> URL {
        let dir = appsDirectory.appendingPathComponent(uuid)
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func iconsDirectory(for uuid: String) -> URL {
        let dir = appDirectory(uuid).appendingPathComponent("Icons")
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - Certificates
    
    var certificatesDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Certificates")
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func certificateDirectory(_ uuid: String) -> URL {
        let dir = certificatesDirectory.appendingPathComponent(uuid)
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func getPath(in directory: URL, for filename: String) -> URL? {
        let fileURL = directory.appendingPathComponent(filename)
        return fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    // MARK: - Files Directory
    var filesDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Files")
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    // MARK: - Signed Apps
    
    var signedAppsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("SignedApps")
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func signedAppDirectory(_ uuid: String) -> URL {
        let dir = signedAppsDirectory.appendingPathComponent(uuid)
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    func signedAppIconsDirectory(for uuid: String) -> URL {
        let dir = signedAppDirectory(uuid).appendingPathComponent("Icons")
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
