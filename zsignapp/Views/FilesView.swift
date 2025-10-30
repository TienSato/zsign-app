//
//  FilesView.swift
//  zsignapp
//

import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @StateObject private var viewModel = FilesViewModel()
    @State private var showImportPicker = false
    @State private var showShareSheet = false
    @State private var fileToShare: URL?
    @State private var selectedFile: FileItem?
    @State private var showDeleteAlert = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showIPAActionSheet = false
    @State private var showAppActionSheet = false
    @State private var showDylibActionSheet = false
    @State private var showDebActionSheet = false
    @State private var showDependencyEditor = false
    @State private var navigateToSign = false
    @State private var navigateToHexEditor = false
    
    var filteredFiles: [FileItem] {
        if searchText.isEmpty {
            return viewModel.sortedFiles
        } else {
            return viewModel.sortedFiles.filter { file in
                file.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            mainContent
                .navigationTitle(isSearching ? "" : "Files")
                .navigationBarTitleDisplayMode(isSearching ? .inline : .large)
                .toolbar {
                    toolbarContent
                }
                .sheet(isPresented: $showImportPicker) {
                    FileImporterRepresentableView(
                        allowedContentTypes: [.item],
                        onDocumentsPicked: { urls in
                            guard let url = urls.first else { return }
                            Task {
                                await viewModel.importFile(from: url)
                            }
                        }
                    )
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showShareSheet) {
                    if let url = fileToShare {
                        ShareSheet(items: [url])
                    }
                }
                .sheet(isPresented: $viewModel.showDownloadSheet) {
                    downloadURLSheet
                }
                .confirmationDialog("IPA Actions", isPresented: $showIPAActionSheet, presenting: selectedFile) { file in
                    ipaActionButtons(for: file)
                } message: { file in
                    Text("Choose an action for \(file.name)")
                }
                .confirmationDialog("App Bundle Actions", isPresented: $showAppActionSheet, presenting: selectedFile) { file in
                    appActionButtons(for: file)
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
                .background(
                    NavigationLink(
                        destination: Group {
                            if let file = selectedFile {
                                HexEditorView(fileURL: file.url)
                            }
                        },
                        isActive: $navigateToHexEditor
                    ) {
                        EmptyView()
                    }
                    .hidden()
                )
                .alert("Delete Item", isPresented: $showDeleteAlert) {
                    deleteAlertButtons
                } message: {
                    deleteAlertMessage
                }
                .alert("Error", isPresented: $viewModel.showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(viewModel.errorMessage ?? "An error occurred")
                }
                .onAppear {
                    viewModel.loadFiles()
                }
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            contentView
            
            overlays
            
            
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBar
            }
            
            if viewModel.isLoading {
                Spacer()
                loadingView
                Spacer()
            } else if viewModel.files.isEmpty {
                Spacer()
                emptyStateView
                Spacer()
            } else {
                fileListView
            }
        }
    }
    
    private var overlays: some View {
        Group {
            if viewModel.isImporting || viewModel.isDownloading {
                progressOverlay(
                    progress: viewModel.importProgress,
                    step: viewModel.isDownloading ? "Downloading..." : viewModel.importStep,
                    icon: viewModel.isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle.fill"
                )
            }
            
            if viewModel.isProcessingIPA {
                progressOverlay(
                    progress: viewModel.ipaProgress,
                    step: viewModel.ipaStep,
                    icon: "app.badge.fill"
                )
            }
            
            if viewModel.isPackaging {
                progressOverlay(
                    progress: viewModel.packagingProgress,
                    step: viewModel.packagingStep,
                    icon: "archivebox.fill"
                )
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isSearching.toggle()
                        if !isSearching {
                            searchText = ""
                        }
                    }
                }) {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.blue)
                }
                
                Menu {
                    Button(action: {
                        viewModel.showDownloadDialog()
                    }) {
                        Label("Download from URL", systemImage: "arrow.down.circle")
                    }
                    
                    Button(action: {
                        showImportPicker = true
                    }) {
                        Label("Import File", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    private var downloadURLSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter URL")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("https://example.com/file.ipa", text: $viewModel.downloadURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    
                    Text("Enter the direct URL to download the file. Supported formats: IPA, ZIP, and more.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding()
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        tipRow(icon: "checkmark.circle.fill", text: "Make sure the URL is a direct download link")
                        tipRow(icon: "checkmark.circle.fill", text: "File will be saved to Files directory")
                        tipRow(icon: "checkmark.circle.fill", text: "You can download IPA, ZIP, and other files")
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Download from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.showDownloadSheet = false
                        viewModel.downloadURL = ""
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Download") {
                        Task {
                            await viewModel.startDownload()
                        }
                    }
                    .disabled(viewModel.downloadURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 12)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Action Buttons
    
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
        
        Button("Hex Editor") {
            selectedFile = file
            navigateToHexEditor = true
        }
        
        Button("Delete", role: .destructive) {
            showDeleteAlert = true
        }
        
        Button("Cancel", role: .cancel) {}
    }
    
    @ViewBuilder
    private func appActionButtons(for file: FileItem) -> some View {
        Button("View Files") {
            // Will be handled by NavigationLink in file list
        }
        
        Button("Package to IPA") {
            Task {
                await viewModel.packageAppToIPA(file)
            }
        }
        
        Button("Delete", role: .destructive) {
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
        
        Button("Hex Editor") {
            selectedFile = file
            navigateToHexEditor = true
        }
        
        Button("Share") {
            fileToShare = file.url
            showShareSheet = true
        }
        
        Button("Delete", role: .destructive) {
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
        
        Button("Hex Editor") {
            selectedFile = file
            navigateToHexEditor = true
        }
        
        Button("Share") {
            fileToShare = file.url
            showShareSheet = true
        }
        
        Button("Delete", role: .destructive) {
            showDeleteAlert = true
        }
        
        Button("Cancel", role: .cancel) {}
    }
    
    
    
    // MARK: - Alert Content
    private var deleteAlertButtons: some View {
        Group {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let file = selectedFile {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.deleteFile(file)
                    }
                }
            }
        }
    }
    @ViewBuilder
    private var deleteAlertMessage: some View {
        if let file = selectedFile {
            Text("Are you sure you want to delete \"\(file.name)\"?")
        }
    }
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search files", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading files...")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder")
                .font(.system(size: 70))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Files")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Import or download files to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    viewModel.showDownloadDialog()
                }) {
                    Label("Download from URL", systemImage: "arrow.down.circle")
                        .frame(maxWidth: 250)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    showImportPicker = true
                }) {
                    Label("Import File", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: 250)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
    }
    
    // MARK: - File List
    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                fileListHeader
                
                ForEach(filteredFiles) { file in
                    fileRow(for: file)
                }
            }
        }
        .refreshable {
            viewModel.loadFiles()
        }
    }
    
    private var fileListHeader: some View {
        HStack {
            Text("ALL FILES")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(filteredFiles.count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private func fileRow(for file: FileItem) -> some View {
        if file.isDirectory && !file.isAppBundle {
            folderNavigationLink(for: file)
        } else {
            tappableFileRow(for: file)
        }
    }
    
    private func folderNavigationLink(for file: FileItem) -> some View {
        NavigationLink(destination: FolderView(
            folderURL: file.url,
            folderName: file.name
        )) {
            FileRowView(file: file)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            folderContextMenu(for: file)
        }
    }
    
    private func tappableFileRow(for file: FileItem) -> some View {
        FileRowView(file: file)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                handleFileTap(file)
            }
            .contextMenu {
                fileContextMenu(for: file)
            }
    }
    
    @ViewBuilder
    private func folderContextMenu(for file: FileItem) -> some View {
        Button {
            fileToShare = file.url
            showShareSheet = true
        } label: {
            Label("Share Folder", systemImage: "square.and.arrow.up")
        }
        
        Button(role: .destructive) {
            selectedFile = file
            showDeleteAlert = true
        } label: {
            Label("Delete Folder", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for file: FileItem) -> some View {
        if file.isAppBundle {
            Button {
                selectedFile = file
                showAppActionSheet = true
            } label: {
                Label("App Actions", systemImage: "app")
            }
            
            Divider()
        } else if file.isIPA {
            Button {
                selectedFile = file
                showIPAActionSheet = true
            } label: {
                Label("IPA Actions", systemImage: "app.badge")
            }
            
            Divider()
        } else if file.url.pathExtension.lowercased() == "dylib" {
            Button {
                selectedFile = file
                showDylibActionSheet = true
            } label: {
                Label("Dylib Actions", systemImage: "gearshape.fill")
            }
            
            Divider()
        } else if file.url.pathExtension.lowercased() == "deb" {
            Button {
                selectedFile = file
                showDebActionSheet = true
            } label: {
                Label("Deb Actions", systemImage: "shippingbox.fill")
            }
            
            Divider()
        }
        
        Button {
            selectedFile = file
            navigateToHexEditor = true
        } label: {
            Label("Hex Editor", systemImage: "chevron.left.forwardslash.chevron.right")
        }
        
        Divider()
        
        Button {
            fileToShare = file.url
            showShareSheet = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        
        Button(role: .destructive) {
            selectedFile = file
            showDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func progressOverlay(progress: Double, step: String, icon: String) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                // Step text
                Text(step)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                // Progress bar with gradient (giống AppsView)
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
                            .frame(width: 200 * progress, height: 8)
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                    .frame(width: 200)
                    
                    Text("\(Int(progress * 100))%")
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
    
    // MARK: - Handle File Tap
    private func handleFileTap(_ file: FileItem) {
        if file.isAppBundle {
            selectedFile = file
            showAppActionSheet = true
        } else if file.isIPA {
            selectedFile = file
            showIPAActionSheet = true
        } else if file.url.pathExtension.lowercased() == "dylib" {
            selectedFile = file
            showDylibActionSheet = true
        } else if file.url.pathExtension.lowercased() == "deb" {
            selectedFile = file
            showDebActionSheet = true
        } else {
            selectedFile = file
            navigateToHexEditor = true
        }
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: FileItem
    
    var body: some View {
        HStack(spacing: 15) {
            fileIcon
            fileInfo
            Spacer(minLength: 8)
            chevron
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    private var fileIcon: some View {
        Group {
            if file.isImageFile, let image = UIImage(contentsOfFile: file.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(file.color.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: file.icon)
                        .font(.system(size: 26))
                        .foregroundColor(file.color)
                }
            }
        }
    }
    
    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(file.name)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            HStack(spacing: 4) {
                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(file.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary.opacity(0.5))
    }
}
