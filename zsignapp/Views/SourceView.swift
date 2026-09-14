//
//  SourcesView.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import SwiftUI
import AltSourceKit
import Combine

// MARK: - Main Sources View (3 TABS)
struct SourcesView: View {
    @StateObject private var sourcesCache = SourcesCacheManager.shared
    @StateObject private var viewModel = SourcesViewModel.shared
    
    var body: some View {
        NavigationView {
            AllSourceAppsView()
                .environmentObject(sourcesCache)
                .environmentObject(viewModel)
                .navigationTitle("AppStore")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Sources Cache Manager
class SourcesCacheManager: ObservableObject {
    static let shared = SourcesCacheManager()
    @Published var cachedSources: [AltSource] = []
    
    private init() {
        loadSources()
    }
    
    func loadSources() {
        cachedSources = Storage.shared.fetchSources()
    }
    
    func refresh() {
        loadSources()
    }
}

// MARK: - ViewModel
final class SourcesViewModel: ObservableObject {
    static let shared = SourcesViewModel()
    
    var isFinished = true
    @Published var sources: [AltSource: ASRepository] = [:]
    
    private var fetchTask: Task<Void, Never>?
    
    func fetchSources(_ sources: [AltSource], refresh: Bool = false, batchSize: Int = 3) async {
        fetchTask?.cancel()
        
        guard isFinished else { return }
        
        if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) {
            return
        }
        
        isFinished = false
        
        fetchTask = Task {
            defer {
                Task { @MainActor in
                    self.isFinished = true
                }
            }
            
            if refresh {
                await MainActor.run {
                    self.sources = [:]
                }
            }
            for startIndex in stride(from: 0, to: sources.count, by: batchSize) {
                if Task.isCancelled { break }
                
                let endIndex = min(startIndex + batchSize, sources.count)
                let batch = Array(sources[startIndex..<endIndex])
                
                await withTaskGroup(of: (AltSource, ASRepository?).self) { group in
                    for source in batch {
                        if Task.isCancelled { break }
                        
                        group.addTask {
                            guard let url = source.sourceURL else {
                                return (source, nil)
                            }
                            
                            do {
                                let (data, _) = try await URLSession.shared.data(from: url)
                                let repo = try JSONDecoder().decode(ASRepository.self, from: data)
                                return (source, repo)
                            } catch {
                                return (source, nil)
                            }
                        }
                    }
                    
                    for await (source, repo) in group {
                        if let repo = repo {
                            await MainActor.run {
                                self.sources[source] = repo
                            }
                        }
                    }
                }
            }
        }
        await fetchTask?.value
    }
}

// MARK: - Shared Components

// MARK: - App Cell View
struct AppCellView: View {
    let app: ASRepository.App
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var currentDownload: Download?
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            AsyncImage(url: app.iconURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
                    .overlay(
                        Image(systemName: "app")
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name ?? "Unknown App")
                    .font(.headline)
                    .lineLimit(1)
                
                if let subtitle = app.subtitle ?? app.localizedDescription {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    if let version = app.currentVersion {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let size = app.size {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Progress bar
                if let download = currentDownload {
                    DownloadProgressView(download: download)
                }
            }
            
            Spacer()
            
            // Download Button
            Button {
                if let download = currentDownload {
                    downloadManager.cancelDownload(download)
                } else {
                    startDownload()
                }
            } label: {
                if let download = currentDownload {
                    DownloadButtonView(download: download)
                } else {
                    installStateIcon
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .onAppear {
            updateCurrentDownload()
        }
        .onChange(of: downloadManager.downloads.count) { _ in
            updateCurrentDownload()
        }
    }
    
    private var installState: InstallStateKind {
        InstalledRegistry.status(bundleId: app.id, availableVersion: app.currentVersion)
    }

    @ViewBuilder
    private var installStateIcon: some View {
        switch installState {
        case .notInstalled:
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
        case .updateAvailable:
            VStack(spacing: 1) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Update")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.orange)
            }
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
        }
    }

    private func updateCurrentDownload() {
        let id = app.id ?? app.currentUniqueId
        currentDownload = downloadManager.getDownload(by: id)
    }
    
    private func startDownload() {
        guard let url = app.currentDownloadUrl else {
            return
        }
        let id = app.id ?? app.currentUniqueId
        let download = downloadManager.startDownload(
            url: url,
            id: id,
            appName: app.name ?? "Unknown"
        )
        currentDownload = download
    }
}

// MARK: - Download Progress View
struct DownloadProgressView: View {
    @ObservedObject var download: Download
    
    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: download.progress, total: 1.0)
                .tint(.accentColor)
                .frame(height: 4)
            
            if download.status == .importing {
                Text("Importing...")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            } else {
                Text("\(Int(download.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .frame(width: 35)
            }
        }
    }
}

// MARK: - Download Button View
struct DownloadButtonView: View {
    @ObservedObject var download: Download
    
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: download.progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 28)
            
            Image(systemName: "xmark")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
        }
    }
}
