//
//  DownloadManager.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import Foundation
import Combine
import UIKit

// MARK: - Download Model
class Download: Identifiable, ObservableObject {
    let id: String
    let url: URL
    let appName: String
    
    @Published var progress: Double = 0.0
    @Published var bytesDownloaded: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var status: DownloadStatus = .downloading
    
    var task: URLSessionDownloadTask?
    var resumeData: Data?
    
    var destinationURL: URL?
    var downloadType: DownloadType
    
    init(id: String, url: URL, appName: String, destinationURL: URL? = nil, downloadType: DownloadType = .ipaToLibrary) {
        self.id = id
        self.url = url
        self.appName = appName
        self.destinationURL = destinationURL
        self.downloadType = downloadType
    }
    
    enum DownloadStatus {
        case downloading
        case importing
        case completed
        case failed
        case cancelled
    }
    
    enum DownloadType {
        case ipaToLibrary
        case fileToDirectory
    }
}

// MARK: - Download Manager
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloads: [Download] = []
    
    private var session: URLSession!
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Start Download (IPA to Library - Original)
    func startDownload(url: URL, id: String, appName: String) -> Download {
        // Check if already downloading
        if let existing = downloads.first(where: { $0.id == id }) {
            return existing
        }
        
        let download = Download(id: id, url: url, appName: appName, downloadType: .ipaToLibrary)
        
        let task = session.downloadTask(with: url)
        download.task = task
        
        DispatchQueue.main.async {
            self.downloads.append(download)
        }
        task.resume()
        updateBackgroundAudio()
        return download
    }
    
    /// Download file thông thường và lưu vào directory cụ thể
    /// - Parameters:
    ///   - url: URL của file cần download
    ///   - fileName: Tên file (optional, mặc định lấy từ URL)
    ///   - destinationDir: Thư mục đích
    /// - Returns: Download object để tracking
    func downloadFile(from url: URL, fileName: String? = nil, to destinationDir: URL) -> Download {
        let finalFileName = fileName ?? url.lastPathComponent
        let destinationURL = destinationDir.appendingPathComponent(finalFileName)
        
        // Check if already downloading
        if let existing = downloads.first(where: { $0.url == url && $0.downloadType == .fileToDirectory }) {
            return existing
        }
        
        let downloadId = "file_\(UUID().uuidString)"
        let download = Download(
            id: downloadId,
            url: url,
            appName: finalFileName,
            destinationURL: destinationURL,
            downloadType: .fileToDirectory
        )
        
        let task = session.downloadTask(with: url)
        download.task = task
        
        DispatchQueue.main.async {
            self.downloads.append(download)
        }
        task.resume()
        updateBackgroundAudio()
        return download
    }
    
    // MARK: - Cancel Download
    func cancelDownload(_ download: Download) {
        download.task?.cancel()
        
        DispatchQueue.main.async {
            download.status = .cancelled
            
            if let index = self.downloads.firstIndex(where: { $0.id == download.id }) {
                self.downloads.remove(at: index)
            }
            
            self.updateBackgroundAudio()
        }
    }
    
    // MARK: - Get Download
    func getDownload(by id: String) -> Download? {
        return downloads.first(where: { $0.id == id })
    }
    
    // ✅ THAY ĐỔI CHÍNH: Logic tự động bật/tắt background mode
    private func updateBackgroundAudio() {
        DispatchQueue.main.async {
            if !self.downloads.isEmpty {
                // ✅ CÓ DOWNLOAD: Tự động bật background mode (bypass flag)
                BackgroundAudioManager.shared.startBackgroundAudio(force: true)
            } else {
                // ✅ KHÔNG CÒN DOWNLOAD: Kiểm tra user setting
                if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                    // User KHÔNG bật toggle → Tắt background mode
                    BackgroundAudioManager.shared.stopBackgroundAudio()
                }
                // User ĐÃ BẬT toggle → Giữ background mode tiếp
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        guard let download = downloads.first(where: { $0.task == downloadTask }) else { return }
        
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        
        DispatchQueue.main.async {
            download.progress = progress
            download.bytesDownloaded = totalBytesWritten
            download.totalBytes = totalBytesExpectedToWrite
            download.objectWillChange.send()
        }
        
        // Debug log
        if Int(progress * 100) % 10 == 0 {
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        
        guard let download = downloads.first(where: { $0.task == downloadTask }) else { return }
        
        DispatchQueue.main.async {
            download.status = .importing
            download.objectWillChange.send()
        }
        
        switch download.downloadType {
        case .ipaToLibrary:
            handleIPADownload(location: location, download: download)
            
        case .fileToDirectory:
            handleFileDownload(location: location, download: download)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let download = downloads.first(where: { $0.task == downloadTask }) else {
            return
        }
        
        if let error = error {
            DispatchQueue.main.async {
                download.status = .failed
                self.removeDownload(download)
            }
        }
    }
    
    private func handleFileDownload(location: URL, download: Download) {
        guard let destinationURL = download.destinationURL else {
            DispatchQueue.main.async {
                download.status = .failed
                self.removeDownload(download)
            }
            return
        }
        
        do {
            // Remove existing file if needed
            try? FileManager.default.removeItem(at: destinationURL)
            
            // Move downloaded file to destination
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                download.status = .completed
                download.objectWillChange.send()
                
                // Remove from list after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.removeDownload(download)
                }
            }
            
        } catch {
            DispatchQueue.main.async {
                download.status = .failed
                self.removeDownload(download)
            }
        }
    }
    
    // MARK: - Handle IPA Download (Original)
    private func handleIPADownload(location: URL, download: Download) {
        // Move file to temp location
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ipa")
        
        do {
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: location, to: tempURL)
            
            // Import IPA in background
            Task {
                await self.importIPA(tempURL, for: download)
            }
            
        } catch {
            DispatchQueue.main.async {
                download.status = .failed
                self.removeDownload(download)
            }
        }
    }
    
    // MARK: - Import IPA (Original)
    private func importIPA(_ url: URL, for download: Download) async {
        do {
            try await IPAHandler().importIPA(from: url)
            
            await MainActor.run {
                download.status = .completed
                download.objectWillChange.send()
                // ✅ THÊM: Trigger auto sign nếu cần
                    self.handleAutoSignIfNeeded(for: download)
                // Remove from list after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.removeDownload(download)
                }
            }
            
            // Cleanup
            try? FileManager.default.removeItem(at: url)
            
        } catch {
            await MainActor.run {
                download.status = .failed
                self.removeDownload(download)
            }
            
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func removeDownload(_ download: Download) {
        DispatchQueue.main.async {
            if let index = self.downloads.firstIndex(where: { $0.id == download.id }) {
                self.downloads.remove(at: index)
            }
            // ✅ Tự động kiểm tra và tắt background mode nếu cần
            self.updateBackgroundAudio()
        }
    }
}
// MARK: - Auto Sign Integration
extension DownloadManager {
    
    // ✅ THÊM: Handler được gọi sau khi import IPA xong
    private func handleAutoSignIfNeeded(for download: Download) {
        let settings = AppSettings.shared
        
        // Chỉ xử lý với IPA downloads
        guard download.downloadType == .ipaToLibrary,
              settings.autoSignAfterDownload else {
            return
        }
        
        print("🎯 Triggering auto sign for: \(download.appName)")
        
        // Gọi auto sign helper
        Task {
            await AutoSignHelper.shared.handleDownloadCompletion(
                downloadId: download.id,
                appName: download.appName
            )
        }
    }
}
