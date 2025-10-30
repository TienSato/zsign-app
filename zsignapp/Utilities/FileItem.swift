//
//  FileItem.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let dateCreated: Date
    let dateModified: Date
    let type: UTType?
    let isDirectory: Bool
    
    var isIPA: Bool {
        return url.pathExtension.lowercased() == "ipa"
    }
    
    var isAppBundle: Bool {
        return url.pathExtension.lowercased() == "app"
    }
    
    var isImageFile: Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "heif"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
    
    var formattedSize: String {
        if isDirectory {
            return "Folder"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateModified)
    }
    
    var icon: String {
        if isAppBundle {
            return "app.fill"
        }
        if isDirectory {
            return "folder.fill"
        }
        if isIPA {
            return "app.badge.fill"
        }
        let ext = url.pathExtension.lowercased()
        // Images
        if ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "heif"].contains(ext) {
            return "photo.fill"
        }
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
            return "archivebox.fill"
        }
        if ext == "pdf" {
            return "doc.text.fill"
        }
        if ["txt", "log", "md"].contains(ext) {
            return "doc.plaintext.fill"
        }
        if ["mp3", "m4a", "wav", "aac", "flac"].contains(ext) {
            return "music.note"
        }
        if ["mp4", "mov", "avi", "mkv", "m4v"].contains(ext) {
            return "film.fill"
        }
        if ["mobileprovision", "p12", "cer", "pem"].contains(ext) {
            return "key.fill"
        }
        if ["swift", "m", "h", "c", "cpp", "java", "py", "js", "html", "css"].contains(ext) {
            return "doc.plaintext.fill"
        }
        if ["plist", "xml"].contains(ext) {
            return "doc.text.fill"
        }
        if ["dylib", "framework", "a"].contains(ext) {
            return "gearshape.fill"
        }
        return "doc.fill"
    }
    
    var colorName: String {
        if isAppBundle {
            return "purple"
        }
        if isDirectory {
            return "blue"
        }
        if isIPA {
            return "blue"
        }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "heif"].contains(ext) {
            return "blue"
        }
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
            return "orange"
        }
        if ext == "pdf" {
            return "red"
        }
        if ["mp3", "m4a", "wav", "aac", "flac"].contains(ext) {
            return "pink"
        }
        if ["mp4", "mov", "avi", "mkv", "m4v"].contains(ext) {
            return "purple"
        }
        if ["mobileprovision", "p12", "cer", "pem"].contains(ext) {
            return "yellow"
        }
        if ["swift", "m", "h", "c", "cpp", "java", "py", "js", "html", "css", "txt", "log", "md"].contains(ext) {
            return "green"
        }
        if ["dylib", "framework", "a"].contains(ext) {
            return "gray"
        }
        return "gray"
    }
    
    var color: Color {
        switch colorName {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "yellow": return .yellow
        case "green": return .green
        case "gray": return .gray
        default: return .gray
        }
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}
