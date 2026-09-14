//
//  SourcesView.swift
//  zsignapp
//  Created by Sato on 26/10/25.
//
//  Vỏ điều hướng của tab AppStore + cache nguồn + view model dùng chung.
//  Giao diện theo bộ thẻ chung (Theme + CardComponents).

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
                .screenChrome("AppStore")
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
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("\(Int(download.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
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
                .stroke(Theme.hairline, lineWidth: 2.5)
                .frame(width: 28, height: 28)
            
            Circle()
                .trim(from: 0, to: download.progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 28)
            
            Image(systemName: "xmark")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
        }
    }
}
