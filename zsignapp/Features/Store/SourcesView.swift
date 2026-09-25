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
