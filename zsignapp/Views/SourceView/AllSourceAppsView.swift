//
//  AllSourceAppsView.swift
//  zsignapp
//
import SwiftUI
import AltSourceKit
import Combine
import UIKit

// MARK: - All Source Apps View (TAB 1 - Grid Layout)
struct AllSourceAppsView: View {
    @EnvironmentObject private var viewModel: SourcesViewModel
    @EnvironmentObject private var sourcesCache: SourcesCacheManager
    
    private var sources: [AltSource] {
        sourcesCache.cachedSources
    }
    
    private var allApps: [ASRepository.App] {
        sources.compactMap { viewModel.sources[$0] }
            .flatMap { $0.apps }
    }
    
    var body: some View {
        appsList
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    ManageSourcesView()
                        .environmentObject(viewModel)
                        .environmentObject(sourcesCache)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.stack.3d.up")
                        Text("Sources")
                    }
                    .font(.system(size: 15, weight: .medium))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SearchAppsView(apps: allApps)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .refreshable {
            await viewModel.fetchSources(sources, refresh: true)
        }
        .task(id: sources.count) {
            if viewModel.sources.isEmpty {
                await viewModel.fetchSources(sources)
            }
        }
    }
    
    @ViewBuilder
    private var appsList: some View {
        if viewModel.sources.isEmpty {
            emptyView
        } else if allApps.isEmpty {
            noAppsView
        } else {
            appsListContent
        }
    }
    
    @ViewBuilder
    private var appsListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("APPS")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(allApps.count)")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
                
                ForEach(allApps, id: \.currentUniqueId) { app in
                    VStack(spacing: 0) {
                        SourceAppRow(app: app)
                        Divider().padding(.leading, 84)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("No Sources Added")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a source in the Sources tab to browse apps")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var noAppsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "app.badge")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("No Apps Available")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your sources don't have any apps yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Source App Grid Cell
// MARK: - Source App Row (danh sách 1 cột)

struct SourceAppRow: View {
    let app: ASRepository.App
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var currentDownload: Download?
    
    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                SourceAppDetailView(app: app)
            } label: {
                HStack(spacing: 13) {
                    iconView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.currentName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if let dev = app.developer, !dev.isEmpty {
                            Text(dev)
                                .font(.system(size: 12.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        if let download = currentDownload {
                            DownloadProgressView(download: download)
                                .padding(.top, 3)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear { updateCurrentDownload() }
        .onChange(of: downloadManager.downloads.count) { _ in updateCurrentDownload() }
    }
    
    private var iconView: some View {
        AsyncImage(url: app.iconURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                Image(systemName: "app")
                    .font(.system(size: 22))
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    private var metaLine: String {
        var parts: [String] = []
        if let v = app.currentVersion, !v.isEmpty { parts.append("v\(v)") }
        if let size = app.size {
            let f = ByteCountFormatter()
            f.allowedUnits = [.useAll]
            f.countStyle = .file
            parts.append(f.string(fromByteCount: Int64(size)))
        }
        return parts.joined(separator: " · ")
    }
    
    private var installState: InstallStateKind {
        InstalledRegistry.status(bundleId: app.id, availableVersion: app.currentVersion)
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if let download = currentDownload {
            Button { downloadManager.cancelDownload(download) } label: {
                DownloadButtonView(download: download)
            }
            .buttonStyle(.plain)
        } else {
            Button { startDownload() } label: {
                Text(actionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(actionColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(actionColor.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(installState == .installed)
        }
    }
    
    private var actionTitle: String {
        switch installState {
        case .notInstalled:    return L("Install")
        case .updateAvailable: return L("Update")
        case .installed:       return L("Installed")
        }
    }
    
    private var actionColor: Color {
        switch installState {
        case .notInstalled:    return .accentColor
        case .updateAvailable: return .orange
        case .installed:       return .secondary
        }
    }
    
    private func updateCurrentDownload() {
        let id = app.id ?? app.currentUniqueId
        currentDownload = downloadManager.getDownload(by: id)
    }
    
    private func startDownload() {
        guard let url = app.currentDownloadUrl else { return }
        let id = app.id ?? app.currentUniqueId
        currentDownload = downloadManager.startDownload(
            url: url, id: id, appName: app.name ?? "Unknown"
        )
    }
}

// MARK: - Source App Detail View (App Store Style)
struct SourceAppDetailView: View {
    let app: ASRepository.App
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var currentDownload: Download?
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var showFullDescription = false
    @State private var appStoreData: AppStoreApp?
    @State private var isLoadingAppStore = true
    @State private var dominantColor: Color = Color(red: 1.0, green: 0.4, blue: 0.7)
    @State private var secondaryColor: Color = Color(red: 1.0, green: 0.5, blue: 0.3)
    
    // Final computed properties with App Store fallback
    private var finalIconURL: URL? {
        app.iconURL ?? appStoreData?.iconURL
    }
    
    private var finalScreenshots: [URL] {
        var urls: [URL] = []
        
        if let screenshotURLs = app.screenshotURLs, !screenshotURLs.isEmpty {
            urls.append(contentsOf: screenshotURLs)
        }
        
        if let screenshots = app.screenshots {
            if let iPhone = screenshots.iPhone, !iPhone.isEmpty {
                urls.append(contentsOf: iPhone)
            }
            if let iPad = screenshots.iPad, !iPad.isEmpty {
                urls.append(contentsOf: iPad)
            }
        }
        
        if urls.isEmpty, let appStoreData = appStoreData {
            urls.append(contentsOf: appStoreData.allScreenshots)
        }
        
        return urls
    }
    
    private var finalDeveloper: String? {
        if let developer = app.developer, !developer.isEmpty {
            return developer
        }
        return appStoreData?.artistName
    }
    
    private var finalCategory: String? {
        if let category = app.category, !category.isEmpty {
            return category
        }
        return appStoreData?.primaryGenreName
    }
    
    private var finalRating: Double? {
        appStoreData?.averageUserRating
    }
    
    private var finalRatingCount: Int? {
        appStoreData?.userRatingCount
    }
    
    private var finalAgeRating: String? {
        appStoreData?.contentAdvisoryRating
    }
    
    private var finalAppStoreUrl: String? {
        appStoreData?.trackViewUrl
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            if isLoadingAppStore {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero Section
                        heroSection
                        
                        // Content
                        VStack(spacing: 0) {
                            // Stats Row (3 columns)
                            statsThreeColumn
                                .padding(.vertical, 20)
                                .background(Color(.systemBackground))
                            
                            Divider()
                            
                            // Screenshots
                            if !finalScreenshots.isEmpty {
                                screenshotsSection
                                    .padding(.top, 30)
                            }
                            
                            Divider()
                                .padding(.vertical, 30)
                            
                            // What's New / Description
                            if let description = app.localizedDescription ?? app.description {
                                whatsNewSection(description: description)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 30)
                                
                                Divider()
                            }
                            
                            // Ratings & Reviews
                            if let rating = finalRating, rating > 0 {
                                ratingsSection
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 30)
                                
                                Divider()
                            }
                            
                            
                            
                            // Information
                            informationSection
                                .padding(.horizontal, 20)
                                .padding(.vertical, 30)
                        }
                        
                        Color.clear.frame(height: 40)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAppStoreData()
            await extractColors()
            setupDownloadObserver()
        }
        .onDisappear {
            cancellable?.cancel()
        }
        .onChange(of: downloadManager.downloads.description) { _ in
            setupDownloadObserver()
        }
    }
    
    // MARK: - Loading View
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading info...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Hero Section
    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            // Dynamic Gradient with Frosted Overlay
            ZStack {
                LinearGradient(
                    colors: [
                        dominantColor.opacity(0.85),
                        dominantColor.opacity(0.65),
                        secondaryColor.opacity(0.55),
                        Color(.systemBackground).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 340)
            
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 110)
                
                HStack(alignment: .bottom, spacing: 16) {
                    AsyncImage(url: finalIconURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.white.opacity(0.3))
                            .overlay(
                                Image(systemName: "app.badge")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.8))
                            )
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(app.currentName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                        
                        if let developer = finalDeveloper {
                            Text(developer)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                        }
                        
                        Spacer()
                        
                        downloadButtonCompact
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .frame(height: 100)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Download Button Compact
    @ViewBuilder
    private var downloadButtonCompact: some View {
        if let download = currentDownload {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 16, height: 16)
                    
                    if download.status == .importing {
                        Text("Import...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button {
                        downloadManager.cancelDownload(download)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                }
                
                ProgressView(value: downloadProgress)
                    .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.3))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
        } else {
            Button {
                startDownload()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                    Text("DOWNLOAD")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(dominantColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                )
            }
        }
    }
    
    // MARK: - Stats Three Column
    @ViewBuilder
    private var statsThreeColumn: some View {
        HStack(spacing: 0) {
            // Ratings
            VStack(spacing: 8) {
                if let ratingCount = finalRatingCount {
                    Text(formatNumber(ratingCount))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("RATINGS")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                if let rating = finalRating, rating > 0 {
                    Spacer().frame(height: 8)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 28, weight: .bold))
                    HStack(spacing: 3) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 60)
            
            // Awards
            VStack(spacing: 8) {
                Text("AWARDS")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14))
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.secondary)
                    
                    Text("Editors'")
                        .font(.system(size: 16, weight: .bold))
                    Text("Choice")
                        .font(.system(size: 16, weight: .bold))
                    
                    Text("Apps")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 60)
            
            // Age or Version
            VStack(spacing: 8) {
                Text("AGES")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                if let ageRating = finalAgeRating {
                    Text(ageRating)
                        .font(.system(size: 28, weight: .bold))
                    Text("In-App Controls")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else if let version = app.currentVersion {
                    Text(version)
                        .font(.system(size: 28, weight: .bold))
                    Text("Version")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Screenshots Section
    @ViewBuilder
    private var screenshotsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(finalScreenshots.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 250, height: 450)
                            .overlay(ProgressView())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    // MARK: - What's New Section
    @ViewBuilder
    private func whatsNewSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("What's New")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            Text(description)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .lineLimit(showFullDescription ? nil : 3)
            
            if description.count > 150 {
                HStack {
                    Spacer()
                    Button {
                        withAnimation {
                            showFullDescription.toggle()
                        }
                    } label: {
                        Text(showFullDescription ? "less" : "more")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            HStack {
                if let version = app.currentVersion {
                    Text("Version \(version)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let date = app.currentDate {
                    Text(formatDate(date.date))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    // MARK: - Ratings Section
    @ViewBuilder
    private var ratingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Ratings & Reviews")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            HStack(alignment: .top, spacing: 40) {
                VStack(spacing: 6) {
                    Text(String(format: "%.1f", finalRating ?? 0))
                        .font(.system(size: 56, weight: .bold))
                    
                    Text("out of 5")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 100)
                
                VStack(spacing: 8) {
                    RatingBar(stars: 5, percentage: 0.70)
                    RatingBar(stars: 4, percentage: 0.15)
                    RatingBar(stars: 3, percentage: 0.08)
                    RatingBar(stars: 2, percentage: 0.04)
                    RatingBar(stars: 1, percentage: 0.03)
                }
                
                VStack(spacing: 4) {
                    Spacer()
                    if let count = finalRatingCount {
                        Text("\(formatNumber(count)) Ratings")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
    }
    
    
    
    // MARK: - Information Section
    @ViewBuilder
    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Information")
                .font(.system(size: 22, weight: .bold))
            
            VStack(spacing: 16) {
                if let developer = finalDeveloper {
                    InfoRow(title: "Developer", value: developer)
                }
                
                if let category = finalCategory {
                    Divider()
                    InfoRow(title: "Category", value: category)
                }
                
                if let size = app.size {
                    Divider()
                    InfoRow(title: "Size", value: formatSize(size))
                }
                
                if let bundleId = app.id {
                    Divider()
                    InfoRow(title: "Bundle ID", value: bundleId)
                }
                
                // Fix: Check cả nil, empty string VÀ URL hợp lệ
                if let appStoreUrlString = finalAppStoreUrl,
                   !appStoreUrlString.isEmpty,
                   let url = URL(string: appStoreUrlString) {
                    Divider()
                    Link(destination: url) {
                        HStack {
                            Text("App Store")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    
    // MARK: - Helper Functions
    private func formatSize(_ bytes: UInt) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1000000 {
            return String(format: "%.1fM", Double(number) / 1000000.0)
        } else if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000.0)
        } else {
            return "\(number)"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
    
    private func extractColors() async {
        let colors = await ColorExtractor.extractColors(from: finalIconURL)
        await MainActor.run {
            self.dominantColor = colors.dominant
            self.secondaryColor = colors.secondary
        }
    }
    
    private func loadAppStoreData() async {
        guard let bundleId = app.id else {
            await MainActor.run {
                self.isLoadingAppStore = false
            }
            return
        }
        
        isLoadingAppStore = true
        
        if let data = await AppStoreLookupService.shared.lookupApp(bundleId: bundleId) {
            await MainActor.run {
                self.appStoreData = data
                self.isLoadingAppStore = false
            }
        } else {
            await MainActor.run {
                self.isLoadingAppStore = false
            }
        }
    }
    
    private func setupDownloadObserver() {
        cancellable?.cancel()
        
        let downloadId = app.id ?? app.currentUniqueId
        if let currentDownload = downloadManager.getDownload(by: downloadId) {
            self.currentDownload = currentDownload
            downloadProgress = currentDownload.progress
            
            cancellable = currentDownload.$progress.sink { newProgress in
                self.downloadProgress = newProgress
            }
        } else {
            self.currentDownload = nil
        }
    }
    
    private func startDownload() {
        guard let downloadURL = app.currentDownloadUrl else { return }
        
        let downloadId = app.id ?? app.currentUniqueId
        let download = downloadManager.startDownload(
            url: downloadURL,
            id: downloadId,
            appName: app.currentName
        )
        currentDownload = download
        setupDownloadObserver()
    }
}

// MARK: - Manage Sources View (TAB 3)
struct ManageSourcesView: View {
    @ObservedObject private var viewModel = SourcesViewModel.shared
    @ObservedObject private var sourcesCache = SourcesCacheManager.shared
    @State private var isAddingPresenting = false
    
    private var sources: [AltSource] {
        sourcesCache.cachedSources
    }
    
    var body: some View {
        List {
            Section {
                NavigationLink {
                    SourceAppsView(sources: sources, viewModel: viewModel)
                } label: {
                    HStack(spacing: 15) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor)
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("All Repositories")
                                .font(.headline)
                            Text("\(sources.count) sources")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section {
                ForEach(sources) { source in
                    NavigationLink {
                        SourceAppsView(sources: [source], viewModel: viewModel)
                    } label: {
                        SourceCellView(source: source)
                    }
                }
                .onDelete(perform: deleteSources)
            } header: {
                HStack {
                    Text("MY SOURCES")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(sources.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .overlay {
            if sources.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 70))
                        .foregroundColor(.gray)
                    
                    Text("No Sources")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Tap + to add your first source")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        isAddingPresenting = true
                    } label: {
                        Text("Add Source")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 50)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                    .padding(.top, 10)
                }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if !sources.isEmpty {
                        NavigationLink {
                            SearchSourcesView(sources: sources)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    
                    Button {
                        isAddingPresenting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingPresenting) {
            AddSourceView()
        }
        .refreshable {
            await viewModel.fetchSources(sources, refresh: true)
            sourcesCache.refresh()
        }
    }
    
    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            let source = sources[index]
            Storage.shared.deleteSource(source)
        }
    }
}

// MARK: - Source Cell View
struct SourceCellView: View {
    let source: AltSource
    
    var body: some View {
        HStack(spacing: 15) {
            AsyncImage(url: source.iconURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                    Image(systemName: "app.badge")
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name ?? "Unknown Source")
                    .font(.headline)
                
                if let date = source.date {
                    Text("Added \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Source View
struct AddSourceView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var sourceURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://example.com/source.json", text: $sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Source URL")
                } footer: {
                    Text("Enter a valid AltStore/SideStore repository URL")
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
                    }
                }
                
                Section {
                    Button {
                        addSource()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Add Source")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(sourceURL.isEmpty || isLoading)
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func addSource() {
        guard let url = URL(string: sourceURL.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Invalid URL format"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let repository = try JSONDecoder().decode(ASRepository.self, from: data)
                await MainActor.run {
                    Storage.shared.addSource(
                        url,
                        repository: repository,
                        id: repository.id ?? url.absoluteString
                    ) { error in
                        isLoading = false
                        
                        if let error = error {
                            errorMessage = error.localizedDescription
                        } else {
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to load source. Please check the URL and try again."
                }
            }
        }
    }
}

// MARK: - Source Apps View (Detail)
struct SourceAppsView: View {
    let sources: [AltSource]
    @ObservedObject var viewModel: SourcesViewModel
    
    private var navigationTitle: String {
        if sources.count == 1 {
            return sources[0].name ?? "Source"
        }
        return "All Repositories"
    }
    
    private var allApps: [ASRepository.App] {
        sources.compactMap { viewModel.sources[$0] }
            .flatMap { $0.apps }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("APPS")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(allApps.count)")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
                
                ForEach(allApps, id: \.currentUniqueId) { app in
                    VStack(spacing: 0) {
                        SourceAppRow(app: app)
                        Divider().padding(.leading, 84)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SearchAppsView(apps: allApps)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
    }
}
