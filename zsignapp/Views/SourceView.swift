//
//  SourcesView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import SwiftUI
import AltSourceKit

// MARK: - Main Sources View
struct SourcesView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Tab Picker
                Picker("", selection: $selectedTab) {
                    Text("All Apps").tag(0)
                    Text("Sources").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                TabView(selection: $selectedTab) {
                    AllSourceAppsView()
                        .tag(0)
                    
                    ManageSourcesView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("AppStore")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - All Source Apps View (TAB 1)
struct AllSourceAppsView: View {
    @StateObject private var viewModel = SourcesViewModel.shared
    @State private var searchText = ""
    @State private var sortOption: SortOption = .default
    @State private var sortAscending = true
    
    private var sources: [AltSource] {
        Storage.shared.fetchSources()
    }
    
    private var allApps: [ASRepository.App] {
        sources.compactMap { viewModel.sources[$0] }
            .flatMap { $0.apps }
    }
    
    private var filteredAndSortedApps: [ASRepository.App] {
        var apps = allApps
        
        if !searchText.isEmpty {
            apps = apps.filter {
                $0.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        if sortOption != .default {
            apps = apps.sorted { app1, app2 in
                let comparison: Bool
                switch sortOption {
                case .name:
                    comparison = (app1.name ?? "") < (app2.name ?? "")
                case .date:
                    let date1 = app1.currentDate?.date ?? Date.distantPast
                    let date2 = app2.currentDate?.date ?? Date.distantPast
                    comparison = date1 < date2
                case .default:
                    comparison = true
                }
                return sortAscending ? comparison : !comparison
            }
        }
        
        return apps
    }
    
    var body: some View {
        Group {
            if viewModel.sources.isEmpty {
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
            } else if filteredAndSortedApps.isEmpty && !searchText.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 70))
                        .foregroundColor(.gray)
                    
                    Text("No Apps Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Try a different search term")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(filteredAndSortedApps, id: \.id) { app in
                            AppCellView(app: app)
                        }
                    } header: {
                        HStack {
                            Text("APPS")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(filteredAndSortedApps.count)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Search Button
                    NavigationLink {
                        SearchAppsView(
                            apps: allApps,
                            searchText: $searchText
                        )
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    // Sort Button
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            sortAscending.toggle()
                        } label: {
                            Label(
                                sortAscending ? "Ascending" : "Descending",
                                systemImage: sortAscending ? "arrow.up" : "arrow.down"
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
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
    
    enum SortOption: CaseIterable {
        case `default`, name, date
        
        var displayName: String {
            switch self {
            case .default: return "Default"
            case .name: return "Name"
            case .date: return "Date Added"
            }
        }
    }
}

// MARK: - Search Apps View
struct SearchAppsView: View {
    let apps: [ASRepository.App]
    @Binding var searchText: String
    
    @Environment(\.dismiss) var dismiss
    @State private var localSearchText = ""
    
    private var filteredApps: [ASRepository.App] {
        if localSearchText.isEmpty {
            return apps
        }
        return apps.filter {
            $0.name?.localizedCaseInsensitiveContains(localSearchText) ?? false
        }
    }
    
    var body: some View {
        List {
            if filteredApps.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No Results")
                        .font(.headline)
                    
                    Text("Try a different search term")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredApps, id: \.id) { app in
                        AppCellView(app: app)
                    }
                } header: {
                    HStack {
                        Text("RESULTS")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(filteredApps.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search Apps")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $localSearchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search apps")
        .onAppear {
            localSearchText = searchText
        }
        .onDisappear {
            searchText = localSearchText
        }
    }
}

// MARK: - Manage Sources View (TAB 2)
struct ManageSourcesView: View {
    @StateObject private var viewModel = SourcesViewModel.shared
    @State private var isAddingPresenting = false
    @State private var searchText = ""
    
    private var sources: [AltSource] {
        Storage.shared.fetchSources()
    }
    
    private var filteredSources: [AltSource] {
        if searchText.isEmpty {
            return sources
        }
        return sources.filter {
            $0.name?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }
    
    var body: some View {
        Group {
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
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        NavigationLink {
                            SourceAppsView(sources: sources, viewModel: viewModel)
                        } label: {
                            HStack(spacing: 15) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
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
                        ForEach(filteredSources) { source in
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
                            Text("\(filteredSources.count)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Search Button
                    if !sources.isEmpty {
                        NavigationLink {
                            SearchSourcesView(
                                sources: sources,
                                searchText: $searchText
                            )
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    
                    // Add Button
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
        }
    }
    
    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            let source = filteredSources[index]
            Storage.shared.deleteSource(source)
        }
    }
}

// MARK: - Search Sources View
struct SearchSourcesView: View {
    let sources: [AltSource]
    @Binding var searchText: String
    
    @Environment(\.dismiss) var dismiss
    @State private var localSearchText = ""
    
    private var filteredSources: [AltSource] {
        if localSearchText.isEmpty {
            return sources
        }
        return sources.filter {
            $0.name?.localizedCaseInsensitiveContains(localSearchText) ?? false
        }
    }
    
    var body: some View {
        List {
            if filteredSources.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No Results")
                        .font(.headline)
                    
                    Text("Try a different search term")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredSources) { source in
                        SourceCellView(source: source)
                    }
                } header: {
                    HStack {
                        Text("RESULTS")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(filteredSources.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search Sources")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $localSearchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sources")
        .onAppear {
            localSearchText = searchText
        }
        .onDisappear {
            searchText = localSearchText
        }
    }
}

// MARK: - Source Cell View
struct SourceCellView: View {
    let source: AltSource
    
    var body: some View {
        HStack(spacing: 15) {
            // Icon
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
            
            // Info
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
    
    @State private var searchText = ""
    @State private var sortOption: SortOption = .default
    @State private var sortAscending = true
    
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
    
    private var filteredAndSortedApps: [ASRepository.App] {
        var apps = allApps
        
        if !searchText.isEmpty {
            apps = apps.filter {
                $0.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        if sortOption != .default {
            apps = apps.sorted { app1, app2 in
                let comparison: Bool
                switch sortOption {
                case .name:
                    comparison = (app1.name ?? "") < (app2.name ?? "")
                case .date:
                    let date1 = app1.currentDate?.date ?? Date.distantPast
                    let date2 = app2.currentDate?.date ?? Date.distantPast
                    comparison = date1 < date2
                case .default:
                    comparison = true
                }
                return sortAscending ? comparison : !comparison
            }
        }
        
        return apps
    }
    
    var body: some View {
        List {
            Section {
                ForEach(filteredAndSortedApps, id: \.id) { app in
                    AppCellView(app: app)
                }
            } header: {
                HStack {
                    Text("APPS")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(filteredAndSortedApps.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Search Button
                    NavigationLink {
                        SearchAppsView(
                            apps: allApps,
                            searchText: $searchText
                        )
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    // Sort Button
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            sortAscending.toggle()
                        } label: {
                            Label(
                                sortAscending ? "Ascending" : "Descending",
                                systemImage: sortAscending ? "arrow.up" : "arrow.down"
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
        }
    }
    
    enum SortOption: CaseIterable {
        case `default`, name, date
        
        var displayName: String {
            switch self {
            case .default: return "Default"
            case .name: return "Name"
            case .date: return "Date Added"
            }
        }
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
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
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
                .tint(.blue)
                .frame(height: 4)
            
            if download.status == .importing {
                Text("Importing...")
                    .font(.caption2)
                    .foregroundColor(.blue)
            } else {
                Text("\(Int(download.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.blue)
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
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 28)
            
            Image(systemName: "xmark")
                .font(.system(size: 10))
                .foregroundColor(.blue)
        }
    }
}
