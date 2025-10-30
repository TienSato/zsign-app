//
//  FolderView.swift
//  zsignapp
//  FIXED: Use Zip library instead of SwiftMiniZip

import SwiftUI
import UniformTypeIdentifiers
import Zip  

struct FolderView: View {
    let folderURL: URL
    let folderName: String
    
    @StateObject private var viewModel = FolderViewModel()
    @State private var showShareSheet = false
    @State private var fileToShare: URL?
    @State private var selectedFile: FileItem?
    @State private var showDeleteAlert = false
    @State private var showAppActionSheet = false
    @State private var showIPAActionSheet = false
    @State private var showDylibActionSheet = false
    @State private var showDebActionSheet = false
    @State private var showDependencyEditor = false
    @State private var navigateToAppBundle: FileItem?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                loadingView
            } else if viewModel.items.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
            
            if viewModel.isPackaging {
                packagingOverlay
            }
            
            if viewModel.isProcessingIPA {
                ipaProcessingOverlay
            }
            
            NavigationLink(
                destination: Group {
                    if let appBundle = navigateToAppBundle {
                        FolderView(
                            folderURL: appBundle.url,
                            folderName: appBundle.name
                        )
                    }
                },
                isActive: Binding(
                    get: { navigateToAppBundle != nil },
                    set: { if !$0 { navigateToAppBundle = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = fileToShare {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog("App Bundle Actions", isPresented: $showAppActionSheet, presenting: selectedFile) { file in
            appActionButtons(for: file)
        } message: { file in
            Text("Choose an action for \(file.name)")
        }
        .confirmationDialog("IPA Actions", isPresented: $showIPAActionSheet, presenting: selectedFile) { file in
            ipaActionButtons(for: file)
        } message: { file in
            Text("Choose an action for \(file.name)")
        }
        .confirmationDialog("Dylib Actions", isPresented: $showDylibActionSheet, presenting: selectedFile) { file in
            dylibActionButtons(for: file)
        } message: { file in
            Text("Choose an action for \(file.name)")
        }
        .confirmationDialog("Deb Actions", isPresented: $showDebActionSheet, presenting: selectedFile) { file in
            debActionButtons(for: file)
        } message: { file in
            Text("Choose an action for \(file.name)")
        }
        .sheet(isPresented: $showDependencyEditor) {
            if let file = selectedFile {
                DependencyEditorView(fileURL: file.url)
            }
        }
        .alert("Delete Item", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = selectedFile {
                    viewModel.deleteItem(item)
                }
            }
        } message: {
            if let item = selectedFile {
                Text("Are you sure you want to delete \"\(item.name)\"?")
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .onAppear {
            viewModel.loadContents(of: folderURL)
        }
    }
    
    // MARK: - App Bundle Actions
    
    @ViewBuilder
    private func appActionButtons(for file: FileItem) -> some View {
        Button("View Contents") {
            navigateToAppBundle = file
            showAppActionSheet = false
        }
        
        Button("Package to IPA") {
            Task {
                await viewModel.packageAppToIPA(file)
            }
        }
        
        Button("Share") {
            fileToShare = file.url
            showShareSheet = true
        }
        
        Button("Delete", role: .destructive) {
            selectedFile = file
            showDeleteAlert = true
        }
        
        Button("Cancel", role: .cancel) {}
    }
    
    @ViewBuilder
    private func ipaActionButtons(for file: FileItem) -> some View {
        Button("Import to Library") {
            Task {
                await viewModel.importIPAToLibrary(file)
            }
        }
        
        Button("Extract IPA") {
            Task {
                await viewModel.extractIPA(file)
            }
        }
        
        Button("Share") {
            fileToShare = file.url
            showShareSheet = true
        }
        
        Button("Delete", role: .destructive) {
            selectedFile = file
            showDeleteAlert = true
        }
        
        Button("Cancel", role: .cancel) {}
    }
    
    @ViewBuilder
    private func dylibActionButtons(for file: FileItem) -> some View {
        Button("Class Dump") {
            Task {
                await viewModel.classDump(file)
            }
        }
        
        Button("Modify Dependencies") {
            showDependencyEditor = true
        }
        
        Button("Share") {
            fileToShare = file.url
            showShareSheet = true
        }
        
        Button("Delete", role: .destructive) {
            selectedFile = file
            showDeleteAlert = true
        }
        
        Button("Cancel", role: .cancel) {}
    }
    
    @ViewBuilder
    private func debActionButtons(for file: FileItem) -> some View {
        Button("Extract Deb") {
            Task {
                await viewModel.extractDeb(file)
            }
        }
        
        Button("Share") {
            fileToShare = file.url
            showShareSheet = true
        }
        
        Button("Delete", role: .destructive) {
            selectedFile = file
            showDeleteAlert = true
        }
        
        Button("Cancel", role: .cancel) {}
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading contents...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 25) {
            Image(systemName: "folder")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("Empty Folder")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("This folder doesn't contain any files")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
    
    // MARK: - File List
    
    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                listHeader
                
                ForEach(viewModel.items) { item in
                    fileRow(for: item)
                }
            }
        }
    }
    
    private var listHeader: some View {
        HStack {
            Text("\(viewModel.items.count) ITEMS")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private func fileRow(for item: FileItem) -> some View {
        if item.isAppBundle {
            appBundleRow(for: item)
        } else if item.isIPA {
            ipaFileRow(for: item)
        } else if item.url.pathExtension.lowercased() == "dylib" {
            dylibFileRow(for: item)
        } else if item.url.pathExtension.lowercased() == "deb" {
            debFileRow(for: item)
        } else if item.isDirectory {
            folderRow(for: item)
        } else {
            regularFileRow(for: item)
        }
    }
    
    private func appBundleRow(for item: FileItem) -> some View {
        FileRowView(file: item)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFile = item
                showAppActionSheet = true
            }
            .contextMenu {
                Button {
                    selectedFile = item
                    showAppActionSheet = true
                } label: {
                    Label("App Actions", systemImage: "app")
                }
                
                Divider()
                
                Button {
                    fileToShare = item.url
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    selectedFile = item
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
    
    private func ipaFileRow(for item: FileItem) -> some View {
        FileRowView(file: item)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFile = item
                showIPAActionSheet = true
            }
            .contextMenu {
                Button {
                    selectedFile = item
                    showIPAActionSheet = true
                } label: {
                    Label("IPA Actions", systemImage: "app.badge")
                }
                
                Divider()
                
                Button {
                    fileToShare = item.url
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    selectedFile = item
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
    
    private func dylibFileRow(for item: FileItem) -> some View {
        FileRowView(file: item)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFile = item
                showDylibActionSheet = true
            }
            .contextMenu {
                Button {
                    selectedFile = item
                    showDylibActionSheet = true
                } label: {
                    Label("Dylib Actions", systemImage: "gearshape.fill")
                }
                
                Divider()
                
                Button {
                    fileToShare = item.url
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    selectedFile = item
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
    
    private func debFileRow(for item: FileItem) -> some View {
        FileRowView(file: item)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFile = item
                showDebActionSheet = true
            }
            .contextMenu {
                Button {
                    selectedFile = item
                    showDebActionSheet = true
                } label: {
                    Label("Deb Actions", systemImage: "shippingbox.fill")
                }
                
                Divider()
                
                Button {
                    fileToShare = item.url
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    selectedFile = item
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
    
    private func folderRow(for item: FileItem) -> some View {
        NavigationLink(destination: FolderView(
            folderURL: item.url,
            folderName: item.name
        )) {
            FileRowView(file: item)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                fileToShare = item.url
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Button(role: .destructive) {
                selectedFile = item
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func regularFileRow(for item: FileItem) -> some View {
        FileRowView(file: item)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contextMenu {
                Button {
                    fileToShare = item.url
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    selectedFile = item
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
    
    // MARK: - Packaging Overlay
    
    private var packagingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text(viewModel.packagingStep)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                VStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray4))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 200 * viewModel.packagingProgress, height: 8)
                            .animation(.linear(duration: 0.3), value: viewModel.packagingProgress)
                    }
                    .frame(width: 200)
                    
                    Text("\(Int(viewModel.packagingProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            )
        }
    }
    
    private var ipaProcessingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "app.badge.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text(viewModel.ipaStep)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                VStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray4))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 200 * viewModel.ipaProgress, height: 8)
                            .animation(.linear(duration: 0.3), value: viewModel.ipaProgress)
                    }
                    .frame(width: 200)
                    
                    Text("\(Int(viewModel.ipaProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            )
        }
    }
}

// MARK: - Folder ViewModel (DÙNG ZIP LIBRARY)

@MainActor
class FolderViewModel: ObservableObject {
    @Published var items: [FileItem] = []
    @Published var isLoading = false
    @Published var isPackaging = false
    @Published var packagingProgress: Double = 0
    @Published var packagingStep: String = ""
    @Published var isProcessingIPA = false
    @Published var ipaProgress: Double = 0
    @Published var ipaStep: String = ""
    @Published var showError = false
    @Published var errorMessage: String?
    
    private let fileManager = FileManager.default
    private let ipaHandler = IPAHandler()
    
    init() {
        setupIPAHandler()
    }
    
    private func setupIPAHandler() {
        ipaHandler.progressCallback = { [weak self] progress in
            Task { @MainActor in
                self?.ipaProgress = progress
            }
        }
        
        ipaHandler.stepCallback = { [weak self] step in
            Task { @MainActor in
                self?.ipaStep = step
            }
        }
    }
    
    func loadContents(of folderURL: URL) {
        isLoading = true
        
        Task {
            do {
                let urls = try fileManager.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [
                        .fileSizeKey,
                        .creationDateKey,
                        .contentModificationDateKey,
                        .contentTypeKey,
                        .isDirectoryKey
                    ],
                    options: [.skipsHiddenFiles]
                )
                
                var loadedItems: [FileItem] = []
                
                for url in urls {
                    let resourceValues = try url.resourceValues(forKeys: [
                        .fileSizeKey,
                        .creationDateKey,
                        .contentModificationDateKey,
                        .isDirectoryKey
                    ])
                    
                    let isDirectory = resourceValues.isDirectory ?? false
                    let size = resourceValues.fileSize.map { Int64($0) } ?? 0
                    let created = resourceValues.creationDate ?? Date()
                    let modified = resourceValues.contentModificationDate ?? Date()
                    
                    let type = UTType(filenameExtension: url.pathExtension)
                    
                    let item = FileItem(
                        url: url,
                        name: url.lastPathComponent,
                        size: size,
                        dateCreated: created,
                        dateModified: modified,
                        type: type,
                        isDirectory: isDirectory
                    )
                    
                    loadedItems.append(item)
                }
                
                self.items = loadedItems.sorted { item1, item2 in
                    if item1.isDirectory != item2.isDirectory {
                        return item1.isDirectory
                    }
                    return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                }
                
            } catch {
                // Silent fail
            }
            
            isLoading = false
        }
    }
    
    func deleteItem(_ item: FileItem) {
        do {
            try fileManager.removeItem(at: item.url)
            items.removeAll { $0.id == item.id }
        } catch {
            showErrorMessage("Failed to delete: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Package .app to IPA (DÙNG ZIP LIBRARY)
    
    func packageAppToIPA(_ appBundle: FileItem) async {
        isPackaging = true
        packagingProgress = 0
        packagingStep = "Preparing to package..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
            isPackaging = false
        }
        
        do {
            let workDir = fileManager.temporaryDirectory.appendingPathComponent("PackageIPA_\(UUID().uuidString)")
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
            
            packagingProgress = 0.1
            packagingStep = "Creating Payload folder..."
            
            let payloadDir = workDir.appendingPathComponent("Payload")
            try fileManager.createDirectory(at: payloadDir, withIntermediateDirectories: true)
            
            packagingProgress = 0.2
            packagingStep = "Copying .app bundle..."
            
            let destAppBundle = payloadDir.appendingPathComponent(appBundle.name)
            try fileManager.copyItem(at: appBundle.url, to: destAppBundle)
            
            packagingProgress = 0.5
            packagingStep = "Creating IPA archive..."
            
            let parentFolder = appBundle.url.deletingLastPathComponent()
            let ipaName = appBundle.name.replacingOccurrences(of: ".app", with: ".ipa")
            let ipaPath = parentFolder.appendingPathComponent(ipaName)
            
            try? fileManager.removeItem(at: ipaPath)
            
            let compressionLevel = AppSettings.shared.compressionType
            
            // ✅ DÙNG ZIP LIBRARY
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    do {
                        try Zip.zipFiles(
                            paths: [payloadDir],
                            zipFilePath: ipaPath,
                            password: nil,
                            compression: compressionLevel,
                            progress: { progress in
                                Task { @MainActor in
                                    let mappedProgress = 0.5 + (progress * 0.4)
                                    self?.packagingProgress = mappedProgress
                                    
                                    let percentage = Int(progress * 100)
                                    if percentage % 10 == 0 {
                                        self?.packagingStep = "Compressing: \(percentage)%"
                                    }
                                }
                            }
                        )
                        
                        continuation.resume()
                        
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            packagingProgress = 0.95
            packagingStep = "Cleaning up..."
            
            try? fileManager.removeItem(at: workDir)
            
            packagingProgress = 1.0
            packagingStep = "IPA created successfully!"
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            loadContents(of: parentFolder)
            
        } catch {
            showErrorMessage("Failed to create IPA: \(error.localizedDescription)")
        }
    }
    
    func importIPAToLibrary(_ file: FileItem) async {
        isProcessingIPA = true
        ipaProgress = 0
        ipaStep = "Preparing to import IPA..."
        
        do {
            try await ipaHandler.importIPA(from: file.url)
            
            ipaStep = "Import successful!"
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
        } catch {
            showErrorMessage("Failed to import IPA: \(error.localizedDescription)")
        }
        
        isProcessingIPA = false
    }
    
    // MARK: - Extract IPA (DÙNG ZIP LIBRARY)
    
    func extractIPA(_ file: FileItem) async {
        isProcessingIPA = true
        ipaProgress = 0
        ipaStep = "Preparing to extract..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        do {
            let parentFolder = file.url.deletingLastPathComponent()
            let extractFolder = parentFolder.appendingPathComponent(
                file.name.replacingOccurrences(of: ".ipa", with: "")
            )
            
            try? fileManager.removeItem(at: extractFolder)
            try fileManager.createDirectory(at: extractFolder, withIntermediateDirectories: true)
            
            ipaProgress = 0.2
            ipaStep = "Extracting IPA..."
            
            // ✅ ADD .IPA AS VALID EXTENSION (GIỐNG IPAHandler)
            Zip.addCustomFileExtension("ipa")
            
            // ✅ DÙNG ZIP LIBRARY
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    do {
                        try Zip.unzipFile(
                            file.url,  // ← Trực tiếp dùng .ipa file
                            destination: extractFolder,
                            overwrite: true,
                            password: nil,
                            progress: { progress in
                                Task { @MainActor in
                                    let mappedProgress = 0.2 + (progress * 0.7)
                                    self?.ipaProgress = mappedProgress
                                    
                                    let percentage = Int(progress * 100)
                                    if percentage % 10 == 0 {
                                        self?.ipaStep = "Extracting: \(percentage)%"
                                    }
                                }
                            }
                        )
                        
                        continuation.resume()
                        
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            ipaProgress = 1.0
            ipaStep = "Extraction complete!"
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
            loadContents(of: parentFolder)
            
        } catch {
            showErrorMessage("Failed to extract IPA: \(error.localizedDescription)")
        }
        
        isProcessingIPA = false
    }
    
    func extractDeb(_ file: FileItem) async {
        isProcessingIPA = true
        ipaProgress = 0
        ipaStep = "Extracting deb package..."
        
        BackgroundAudioManager.shared.startBackgroundAudio()
        
        defer {
            if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                BackgroundAudioManager.shared.stopBackgroundAudio()
            }
        }
        
        do {
            let parentFolder = file.url.deletingLastPathComponent()
            let extractFolder = parentFolder.appendingPathComponent(
                file.name.replacingOccurrences(of: ".deb", with: "")
            )
            
            try? fileManager.removeItem(at: extractFolder)
            try fileManager.createDirectory(at: extractFolder, withIntermediateDirectories: true)
            
            ipaProgress = 0.3
            ipaStep = "Reading deb archive..."
            
            let ar = AR(with: file.url)
            let arFiles = try await ar.extract()
            
            ipaProgress = 0.7
            ipaStep = "Extracting contents..."
            
            for arFile in arFiles {
                let outputPath = extractFolder.appendingPathComponent(arFile.name)
                try arFile.content.write(to: outputPath)
            }
            
            ipaProgress = 1.0
            ipaStep = "Extraction complete!"
            try await Task.sleep(nanoseconds: 1_000_000_000)
            loadContents(of: parentFolder)
            
        } catch {
            showErrorMessage("Failed to extract deb: \(error.localizedDescription)")
        }
        
        isProcessingIPA = false
    }
    
    func classDump(_ file: FileItem) async {
        await MainActor.run {
            errorMessage = "Class dump feature - coming soon!\nWould integrate with class-dump tool to extract Objective-C headers from the dylib."
            showError = true
        }
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
