//
//  AllSourceAppsView.swift
//  zsignapp
//
//  Kho ứng dụng: danh sách tổng hợp, trang chi tiết kiểu App Store,
//  quản lý nguồn. Giao diện dùng bộ thẻ chung (Theme + CardComponents).
//
import SwiftUI
import AltSourceKit
import Combine
import UIKit

// MARK: - Danh sách ứng dụng dùng chung (tổng hợp & theo nguồn)

/// Một thẻ chứa toàn bộ hàng ứng dụng, có tiêu đề đếm số lượng phía trên.
private struct StoreAppsList: View {
    let apps: [StoreApp]
    /// Hiện tên nguồn ở mỗi dòng (tắt khi đang xem đúng một nguồn).
    var showsSource: Bool = true
    /// Do nút kính lúp trên thanh công cụ bật/tắt.
    @Binding var isSearching: Bool

    @State private var query = ""
    /// nil = không lọc, hiện tất cả. Lưu sẵn kết quả thay vì lọc trong body.
    @State private var results: [StoreApp]?
    @FocusState private var focused: Bool

    private var visible: [StoreApp] { results ?? apps }

    var body: some View {
        // Tính MỘT lần cho cả danh sách thay vì gọi trong vòng lặp.
        let list = visible
        let firstID = list.first?.id

        ScrollView {
            VStack(spacing: 0) {
                if isSearching {
                    searchBar
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }

                HStack {
                    Text(isSearching && !query.isEmpty ? "RESULTS" : "APPS")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                    Text("\(list.count)")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 4)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if list.isEmpty {
                    EmptyStateView(
                        title: "No Results",
                        systemImage: "magnifyingglass",
                        message: "No app matches what you typed",
                        style: .compact
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        // Duyệt thẳng mảng: không Array(enumerated()), không dựng
                        // lại chuỗi id cho từng phần tử ở mỗi lần vẽ.
                        ForEach(list) { item in
                            SourceAppRow(item: item,
                                         showsSource: showsSource,
                                         showsDivider: item.id != firstID)
                        }
                    }
                    .cardStyle(padding: 0)
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 32)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        // Đổi query hoặc đổi danh sách nguồn thì lọc lại. .task(id:) tự huỷ
        // lượt trước nên việc chờ 220ms bên dưới thành ra là chống gõ dồn.
        .task(id: "\(query)#\(apps.count)") { await applyFilter() }
        .onChange(of: isSearching) { searching in
            if searching {
                focused = true
            } else {
                query = ""
                results = nil
            }
        }
    }

    // MARK: - Thanh tìm kiếm ngay tại chỗ

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink3)

                TextField("Search apps", text: $query)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.card))

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isSearching = false }
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Lọc

    private func applyFilter() async {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else {
            results = nil
            return
        }

        // Chờ một nhịp: gõ tiếp thì .task(id:) huỷ lượt này, không lọc thừa.
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }

        let source = apps
        let filtered = await Task.detached(priority: .userInitiated) {
            source.filter { $0.searchName.contains(term) }
        }.value

        guard !Task.isCancelled else { return }
        results = filtered
    }
}

// MARK: - All Source Apps View (TAB 1 - Grid Layout)
struct AllSourceAppsView: View {
    @EnvironmentObject private var viewModel: SourcesViewModel
    @EnvironmentObject private var sourcesCache: SourcesCacheManager
    @State private var isSearching = false
    
    private var sources: [AltSource] {
        sourcesCache.cachedSources
    }

    /// Đọc thẳng danh sách đã dựng sẵn — KHÔNG gộp lại ở đây.
    private var allApps: [StoreApp] {
        viewModel.catalog
    }
    
    var body: some View {
        appsList
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // Toolbar KHÔNG truyền @EnvironmentObject sang đích của NavigationLink,
                // nên ManageSourcesView vừa dùng singleton vừa được tiêm lại ở đây.
                // Bỏ một trong hai là crash.
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
                // Mở ô tìm ngay trên màn này, không đẩy sang màn khác.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
                } label: {
                    Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                }
            }
        }
        .refreshable {
            await viewModel.fetchSources(sources, refresh: true)
        }
        .task(id: sources.count) {
            // Bản lưu trên đĩa hiện ra ngay, rồi mới làm mới ngầm nếu đã cũ.
            await viewModel.loadCachedIfNeeded(sources)
            await viewModel.refreshIfStale(sources)
        }
    }
    
    @ViewBuilder
    private var appsList: some View {
        if sources.isEmpty {
            emptyView
        } else if allApps.isEmpty {
            if viewModel.isRefreshing {
                ProgressOverlay(title: "Loading apps...")
            } else {
                noAppsView
            }
        } else {
            appsListContent
        }
    }
    
    @ViewBuilder
    private var appsListContent: some View {
        StoreAppsList(apps: allApps, isSearching: $isSearching)
    }
    
    @ViewBuilder
    private var emptyView: some View {
        EmptyStateView(title: "No Sources Added",
                       systemImage: "square.stack.3d.up",
                       message: "Add a source in the Sources tab to browse apps")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
    }
    
    @ViewBuilder
    private var noAppsView: some View {
        EmptyStateView(title: "No Apps Available",
                       systemImage: "app.badge",
                       message: "Your sources don't have any apps yet")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
    }
}

// MARK: - Source App Row (danh sách 1 cột)

struct SourceAppRow: View {
    let item: StoreApp
    var showsSource: Bool = true
    var showsDivider: Bool = false

    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var currentDownload: Download?

    private var app: ASRepository.App { item.app }

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 0.5)
                    .padding(.leading, 84)
            }

            HStack(spacing: 10) {
                NavigationLink {
                    SourceAppDetailView(app: app, sourceName: item.sourceName)
                } label: {
                    HStack(spacing: 13) {
                        iconView
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)

                            if let dev = item.developer, !dev.isEmpty {
                                Text(dev)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.ink2)
                                    .lineLimit(1)
                            }

                            if !item.versionAndSize.isEmpty {
                                Text(item.versionAndSize)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.ink3)
                                    .lineLimit(1)
                            }

                            // Ứng dụng này đến từ nguồn nào.
                            if showsSource {
                                HStack(spacing: 3) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.system(size: 9))
                                    Text(item.sourceName)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Color.accentColor.opacity(0.85))
                                .padding(.top, 1)
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
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.vertical, 10)
        }
        .onAppear { updateCurrentDownload() }
        .onChange(of: downloadManager.downloads.count) { _ in updateCurrentDownload() }
    }

    private var iconView: some View {
        CachedAsyncImage(url: item.iconURL, size: 56) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.cardAlt)
                Image(systemName: "app")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
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
                    .foregroundStyle(actionColor)
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
        case .installed:       return Theme.ink3
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
    /// Nguồn mà ứng dụng này đến từ. Rỗng thì không hiện dòng nguồn.
    var sourceName: String = ""
    
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
            Theme.canvas
                .ignoresSafeArea()
            
            if isLoadingAppStore {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero Section
                        heroSection
                        
                        // Content
                        VStack(spacing: Theme.Metric.cardSpacing) {
                            // Stats Row (3 columns)
                            statsThreeColumn
                                .padding(.vertical, 18)
                                .cardStyle(padding: 0)
                                .padding(.horizontal, Theme.Metric.screenPadding)
                            
                            // Screenshots — tràn hết bề ngang, không bọc thẻ
                            if !finalScreenshots.isEmpty {
                                screenshotsSection
                            }
                            
                            // What's New / Description
                            if let description = app.localizedDescription ?? app.description {
                                whatsNewSection(description: description)
                                    .cardStyle()
                                    .padding(.horizontal, Theme.Metric.screenPadding)
                            }
                            
                            // Ratings & Reviews
                            if let rating = finalRating, rating > 0 {
                                ratingsSection
                                    .cardStyle()
                                    .padding(.horizontal, Theme.Metric.screenPadding)
                            }
                            
                            // Information
                            informationSection
                                .cardStyle()
                                .padding(.horizontal, Theme.Metric.screenPadding)
                        }
                        .padding(.top, 16)
                        
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
                .foregroundStyle(Theme.ink2)
        }
    }
    
    // MARK: - Hero Section
    // Nền lấy màu từ icon app nên KHÔNG dùng Theme ở đây: chữ và nút phải
    // trắng để đọc được trên bất kỳ màu chủ đạo nào (giống FilledButton).
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
                        Theme.canvas.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                LinearGradient(
                    colors: [
                        .white.opacity(0.2),
                        .white.opacity(0.1),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 340)
            
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 110)
                
                HStack(alignment: .bottom, spacing: 16) {
                    CachedAsyncImage(url: finalIconURL, size: 100) {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(.white.opacity(0.3))
                            .overlay(
                                Image(systemName: "app.badge")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.8))
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(app.currentName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(radius: 3, y: 2)
                        
                        if let developer = finalDeveloper {
                            Text(developer)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .shadow(radius: 3, y: 2)
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
                            .stroke(.white.opacity(0.4), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 16, height: 16)
                    
                    if download.status == .importing {
                        Text("Import...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    Button {
                        downloadManager.cancelDownload(download)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                
                ProgressView(value: downloadProgress)
                    .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.3))
                    .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
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
                .foregroundStyle(dominantColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white)
                        .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
                )
            }
            .buttonStyle(.plain)
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
                        .foregroundStyle(Theme.ink2)
                    Text("RATINGS")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
                }
                
                if let rating = finalRating, rating > 0 {
                    Spacer().frame(height: 8)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 3) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 60)
            
            // Awards
            VStack(spacing: 8) {
                Text("AWARDS")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14))
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(Theme.ink2)
                    
                    Text("Editors'")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Choice")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    
                    Text("Apps")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .frame(maxWidth: .infinity)
            
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 60)
            
            // Age or Version
            VStack(spacing: 8) {
                Text("AGES")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
                
                if let ageRating = finalAgeRating {
                    Text(ageRating)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("In-App Controls")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
                        .multilineTextAlignment(.center)
                } else if let version = app.currentVersion {
                    Text(version)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Version")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
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
                            .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Theme.cardAlt)
                            .frame(width: 250, height: 450)
                            .overlay(ProgressView())
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
        }
    }
    
    // MARK: - What's New Section
    @ViewBuilder
    private func whatsNewSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("What's New")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                CardChevron()
            }
            
            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
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
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            HStack {
                if let version = app.currentVersion {
                    Text("Version \(version)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                if let date = app.currentDate {
                    Text(formatDate(date.date))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink3)
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
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                CardChevron()
            }
            
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 6) {
                    Text(String(format: "%.1f", finalRating ?? 0))
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    
                    Text("out of 5")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                }
                .frame(minWidth: 90)
                
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
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink3)
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            
            VStack(spacing: 16) {
                // Ứng dụng này đến từ nguồn nào
                if !sourceName.isEmpty {
                    InfoRow(title: L("Source"), value: sourceName)
                    infoDivider
                }

                if let developer = finalDeveloper {
                    InfoRow(title: L("Developer"), value: developer)
                }
                
                if let category = finalCategory {
                    infoDivider
                    InfoRow(title: L("Category"), value: category)
                }
                
                if let size = app.size {
                    infoDivider
                    InfoRow(title: L("Size"), value: formatSize(size))
                }
                
                if let bundleId = app.id {
                    infoDivider
                    InfoRow(title: L("Bundle ID"), value: bundleId)
                }
                
                // Fix: Check cả nil, empty string VÀ URL hợp lệ
                if let appStoreUrlString = finalAppStoreUrl,
                   !appStoreUrlString.isEmpty,
                   let url = URL(string: appStoreUrlString) {
                    infoDivider
                    Link(destination: url) {
                        HStack {
                            Text("App Store")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            CardChevron()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var infoDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
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
// Giữ List vì có swipe-to-delete (.onDelete) — LUẬT 3.
struct ManageSourcesView: View {
    // Toolbar không truyền EnvironmentObject xuống đích NavigationLink,
    // nên màn này tự lấy singleton. GIỮ NGUYÊN, đừng đổi sang @EnvironmentObject.
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
                    HStack(spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("All Repositories")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(String(format: L("%d sources"), sources.count))
                                .font(.caption)
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.card)
            }
            
            Section {
                ForEach(sources) { source in
                    NavigationLink {
                        SourceAppsView(sources: [source], viewModel: viewModel)
                    } label: {
                        SourceCellView(source: source)
                    }
                    .listRowBackground(Theme.card)
                }
                .onDelete(perform: deleteSources)
            } header: {
                HStack {
                    Text("MY SOURCES")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                    Text("\(sources.count)")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay {
            if sources.isEmpty {
                VStack(spacing: 16) {
                    EmptyStateView(title: "No Sources",
                                   systemImage: "externaldrive.badge.plus",
                                   message: "Tap + to add your first source",
                                   style: .compact)
                    
                    FilledButton(title: L("Add Source"), icon: "plus") {
                        isAddingPresenting = true
                    }
                    .frame(maxWidth: 240)
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
            }
        }
        .screenChrome("Sources")
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
        HStack(spacing: 13) {
            CachedAsyncImage(url: source.iconURL, size: 56) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.cardAlt)
                    Image(systemName: "app.badge")
                        .foregroundStyle(Theme.ink3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name ?? L("Unknown Source"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                
                if let date = source.date {
                    Text("Added \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
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
            CardScreen {
                CardGroup(L("Source URL"),
                          footnote: L("Enter a valid AltStore/SideStore repository URL")) {
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: Theme.Metric.iconBox, alignment: .center)
                        
                        TextField("https://example.com/source.json", text: $sourceURL)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, Theme.Metric.cardPadding)
                    .padding(.vertical, 14)
                    .frame(minHeight: Theme.Metric.rowHeight)
                }
                
                if let errorMessage = errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .cardStyle()
                }
                
                addButton
            }
            .screenChrome("Add Source")
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
    
    private var addButton: some View {
        Button {
            addSource()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add Source")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(sourceURL.isEmpty || isLoading ? Theme.ink3 : Color.accentColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(sourceURL.isEmpty || isLoading)
        .padding(.top, 4)
    }
    
    private func addSource() {
        guard let url = URL(string: sourceURL.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = L("Invalid URL format")
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
                    errorMessage = L("Failed to load source. Please check the URL and try again.")
                }
            }
        }
    }
}

// MARK: - Source Apps View (Detail)
struct SourceAppsView: View {
    let sources: [AltSource]
    @ObservedObject var viewModel: SourcesViewModel
    @State private var isSearching = false
    
    private var navigationTitle: String {
        if sources.count == 1 {
            return sources[0].name ?? L("Source")
        }
        return L("All Repositories")
    }
    
    /// Lọc từ danh sách đã dựng sẵn theo khoá nguồn — không gộp lại từ đầu.
    private var allApps: [StoreApp] {
        let keys = Set(sources.compactMap { source -> String? in
            guard let url = source.sourceURL else { return nil }
            return source.identifier ?? url.absoluteString
        })
        guard !keys.isEmpty else { return [] }
        return viewModel.catalog.filter { keys.contains($0.sourceKey) }
    }

    var body: some View {
        StoreAppsList(apps: allApps,
                      showsSource: sources.count > 1,
                      isSearching: $isSearching)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
                    } label: {
                        Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    }
                }
            }
    }
}
