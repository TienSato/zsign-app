//
//  AppsView.swift
//  zsignapp
//  Created by Sato on 13/1/26.
//

import SwiftUI
import CoreData

struct AppsView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            Group {
                if selectedTab == 0 {
                    UnsignedAppsView(selectedTab: $selectedTab)
                } else {
                    SignedAppsView(selectedTab: $selectedTab)
                }
            }
            .navigationTitle("Apps")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Unsigned Apps View
struct UnsignedAppsView: View {
    @Binding var selectedTab: Int
    @StateObject private var storage = Storage.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ImportedApp.date, ascending: false)],
        animation: .default
    )
    private var apps: FetchedResults<ImportedApp>
    
    @State private var showFilePicker = false
    // ✅ THÊM 2 DÒNG NÀY
    @State private var showDownloadManager = false
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var isImporting = false
    @State private var importError: String?
    
    @State private var importProgress: Double = 0.0
    @State private var importStep: String = "Preparing..."
    @State private var isSelectionMode = false
    @State private var selectedApps: Set<NSManagedObjectID> = []
    @State private var showDeleteConfirmation = false
    @State private var navigateToBatchSign = false
    
    let ipaHandler = IPAHandler()
    
    var body: some View {
        ZStack {
            List {
                // Picker Section
                Section {
                    Picker("", selection: $selectedTab) {
                        Text("Unsigned").tag(0)
                        Text("Signed").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                // ✅ THÊM SECTION NÀY (Downloads Section)
                            if !downloadManager.downloads.isEmpty {
                                Section {
                                    ForEach(downloadManager.downloads) { download in
                                        DownloadListRow(download: download)
                                    }
                                } header: {
                                    Label("Active Downloads", systemImage: "arrow.down.circle.fill")
                                }
                            }
                // Apps Section
                Section {
                    ForEach(apps) { app in
                    UnsignedAppRow(
                        app: app,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedApps.contains(app.objectID),
                        onToggleSelection: {
                            toggleSelection(app)
                        }
                    )
                }
                .onDelete(perform: deleteApps)
            } header: {
                // ✅ THÊM ĐIỀU KIỆN NÀY CHO HEADER
                if !downloadManager.downloads.isEmpty {
                    Label("Imported Apps", systemImage: "app.badge")
                }
            }
            }
            .overlay {
                if apps.isEmpty {
                    EmptyStateView(
                        title: "No Apps",
                        systemImage: "app.badge",
                        message: "Import an IPA file to get started"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectionMode {
                        Button("Cancel") {
                            isSelectionMode = false
                            selectedApps.removeAll()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if isSelectionMode {
                            Button(action: {
                                navigateToBatchSign = true
                            }) {
                                Image(systemName: "signature")
                                    .foregroundColor(.accentColor)
                            }
                            .disabled(selectedApps.isEmpty)
                            
                            Button(action: {
                                showDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .disabled(selectedApps.isEmpty)
                        } else {
                            Button(isSelectionMode ? "Cancel" : "Select") {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedApps.removeAll()
                                }
                            }
                            
                            // ✅ THAY BUTTON NÀY BẰNG MENU
                                            Menu {
                                                Button {
                                                    showFilePicker = true
                                                } label: {
                                                    Label("Import from Files", systemImage: "folder")
                                                }
                                                
                                                Button {
                                                    showDownloadManager = true
                                                } label: {
                                                    Label("Download from URL", systemImage: "arrow.down.circle")
                                                }
                                            } label: {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 18, weight: .semibold))
                                            }
                                            .disabled(isImporting)
                                        }
                                    }
                                }
                            }
            
            NavigationLink(
                destination: BatchSignView(selectedApps: getSelectedApps()),
                isActive: $navigateToBatchSign
            ) {
                EmptyView()
            }
            .hidden()
            
            if isImporting {
                ProgressOverlay(
                    title: "Importing App",
                    step: L(importStep),
                    progress: importProgress
                )
            }
        }
        .sheet(isPresented: $showFilePicker) {
            FileImporterRepresentableView(
                allowedContentTypes: [.ipa],
                onDocumentsPicked: { urls in
                    guard let url = urls.first else { return }
                    handleImport(url: url)
                }
            )
            .ignoresSafeArea()
        }
        // ✅ THÊM SHEET NÀY
        .sheet(isPresented: $showDownloadManager) {
            DownloadManagerView()
        }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImportIPAFromShare"))) { notification in
                if let url = notification.object as? URL {
                    handleImport(url: url)
                }
            }
        .alert("Import Failed", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
        .alert("Delete Apps", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedApps()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedApps.count) app(s)?")
        }
    }
    
    private func toggleSelection(_ app: ImportedApp) {
        if selectedApps.contains(app.objectID) {
            selectedApps.remove(app.objectID)
        } else {
            selectedApps.insert(app.objectID)
        }
    }
    
    private func deleteSelectedApps() {
        withAnimation {
            let appsToDelete = apps.filter { selectedApps.contains($0.objectID) }
            appsToDelete.forEach { storage.deleteApp($0) }
            selectedApps.removeAll()
            isSelectionMode = false
        }
    }
    
    private func getSelectedApps() -> [ImportedApp] {
        return apps.filter { selectedApps.contains($0.objectID) }
    }
    
    private func handleImport(url: URL) {
        isImporting = true
        importError = nil
        importProgress = 0.0
        importStep = "Preparing..."
        
        Task {
            do {
                ipaHandler.progressCallback = { progress in
                    Task { @MainActor in
                        self.importProgress = progress
                    }
                }
                
                ipaHandler.stepCallback = { step in
                    Task { @MainActor in
                        self.importStep = step
                    }
                }
                
                try await ipaHandler.importIPA(from: url)
                
                await MainActor.run {
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                }
            }
        }
    }
    
    private func deleteApps(offsets: IndexSet) {
        withAnimation {
            offsets.map { apps[$0] }.forEach(storage.deleteApp)
        }
    }
}

// MARK: - Unsigned App Row
struct UnsignedAppRow: View {
    let app: ImportedApp
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    
    @State private var showActionSheet = false
    @State private var showDeleteAlert = false
    @State private var navigateToSign = false
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button {
                    onToggleSelection?()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .gray)
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
            }
            
            Button {
                if isSelectionMode {
                    onToggleSelection?()
                } else {
                    showActionSheet = true
                }
            } label: {
                HStack(spacing: 12) {
                    AppIconView(app: app, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name ?? "Unknown App")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if let identifier = app.identifier {
                            Text(identifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        if let version = app.version {
                            Text("Version \(version)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if !isSelectionMode {
                NavigationLink(destination: SignAppView(app: app), isActive: $navigateToSign) {
                    EmptyView()
                }
                .hidden()
                .frame(width: 0, height: 0)
                
                Button {
                    navigateToSign = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "signature")
                            .font(.system(size: 24))
                            .foregroundColor(.accentColor)
                        Text("Sign")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 60)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Options", isPresented: $showActionSheet, titleVisibility: .hidden) {
            Button("Sign App") { navigateToSign = true }
            Button("Delete", role: .destructive) { showDeleteAlert = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete App", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Storage.shared.deleteApp(app)
            }
        } message: {
            Text("Are you sure you want to delete this app?")
        }
    }
}

// MARK: - App Icon View
struct AppIconView: View {
    let app: ImportedApp
    let size: CGFloat
    
    var body: some View {
        if let iconImage = loadIcon() {
            Image(uiImage: iconImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                )
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.5))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }
    
    private func loadIcon() -> UIImage? {
        guard let uuid = app.uuid,
              let iconFileName = app.iconFileName else {
            return nil
        }
        
        let iconPath = FileManager.default
            .iconsDirectory(for: uuid)
            .appendingPathComponent(iconFileName)
        
        return UIImage(contentsOfFile: iconPath.path)
    }
}

// MARK: - Signed Apps View
struct SignedAppsView: View {
    @Binding var selectedTab: Int
    @StateObject private var storage = Storage.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SignedApp.date, ascending: false)],
        animation: .default
    )
    private var signedApps: FetchedResults<SignedApp>
    
    // Selection mode
    @State private var isSelectionMode = false
    @State private var selectedApps: Set<NSManagedObjectID> = []
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        List {
            // Picker Section
            Section {
                Picker("", selection: $selectedTab) {
                    Text("Unsigned").tag(0)
                    Text("Signed").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            
            // Apps Section
            Section {
                ForEach(signedApps) { app in
                SignedAppRow(
                    app: app,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedApps.contains(app.objectID),
                    onToggleSelection: {
                        toggleSelection(app)
                    }
                )
            }
            .onDelete(perform: deleteApps)
            }
        }
        .overlay {
            if signedApps.isEmpty {
                EmptyStateView(
                    title: "No Signed Apps",
                    systemImage: "signature",
                    message: "Sign an app to see it here"
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelectionMode {
                    Button("Cancel") {
                        isSelectionMode = false
                        selectedApps.removeAll()
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isSelectionMode {
                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .disabled(selectedApps.isEmpty)
                    } else {
                        Button("Select") {
                            isSelectionMode = true
                        }
                    }
                }
            }
        }
        .alert("Delete Apps", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedApps()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedApps.count) app(s)?")
        }
    }
    
    private func toggleSelection(_ app: SignedApp) {
        if selectedApps.contains(app.objectID) {
            selectedApps.remove(app.objectID)
        } else {
            selectedApps.insert(app.objectID)
        }
    }
    
    private func deleteSelectedApps() {
        withAnimation {
            let appsToDelete = signedApps.filter { selectedApps.contains($0.objectID) }
            appsToDelete.forEach { storage.deleteSignedApp($0) }
            selectedApps.removeAll()
            isSelectionMode = false
        }
    }
    
    private func deleteApps(offsets: IndexSet) {
        withAnimation {
            offsets.map { signedApps[$0] }.forEach(storage.deleteSignedApp)
        }
    }
}

// MARK: - Signed App Row (FIXED)
struct SignedAppRow: View {
    let app: SignedApp
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    
    @State private var showActionSheet = false
    @State private var showDetailSheet = false
    @State private var showShareSheet = false
    @State private var isInstalling = false
    @State private var installError: String?
    @State private var showDeleteAlert = false
    
    private var certificate: CertificatePair? {
        guard let certUUID = app.certificateUUID else { return nil }
        return Storage.shared.fetchCertificates().first(where: { $0.uuid == certUUID })
    }
    
    private var certificateDecoded: Certificate? {
        guard let cert = certificate else { return nil }
        return Storage.shared.getProvisionDecoded(for: cert)
    }
    
    private var ipaURL: URL? {
        guard let uuid = app.uuid else { return nil }
        let dir = FileManager.default.signedAppDirectory(uuid)
        let ipaName = (app.name ?? "SignedApp").replacingOccurrences(of: " ", with: "_") + ".ipa"
        let ipaPath = dir.appendingPathComponent(ipaName)
        return FileManager.default.fileExists(atPath: ipaPath.path) ? ipaPath : nil
    }
    
    private var fileSize: String {
        guard let url = ipaURL,
              let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button {
                    onToggleSelection?()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .gray)
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
            }
            
            Button {
                if isSelectionMode {
                    onToggleSelection?()
                } else {
                    showActionSheet = true
                }
            } label: {
                HStack(spacing: 12) {
                    if let iconImage = loadIcon() {
                        Image(uiImage: iconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 60 * 0.2237, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 60 * 0.2237, style: .continuous)
                                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 60 * 0.5))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 60 * 0.2237, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 60 * 0.2237, style: .continuous)
                                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name ?? "Unknown App")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let identifier = app.identifier {
                            Text(identifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        if let version = app.version {
                            Text("Version \(version)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let date = app.date {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                Text(date, style: .date)
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        if let teamName = certificateDecoded?.TeamName {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                Text(teamName)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .foregroundColor(.accentColor)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                            Text(fileSize)
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if !isSelectionMode {
                Button {
                    installApp()
                } label: {
                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.accentColor)
                            Text("Install")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isInstalling)
                .frame(width: 60)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Options", isPresented: $showActionSheet, titleVisibility: .hidden) {
            Button("Detail") { showDetailSheet = true }
            Button("Install") { installApp() }
            Button("Share") { showShareSheet = true }
            Button("Show in Files") { showInFiles() }
            Button("Delete", role: .destructive) { showDeleteAlert = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showDetailSheet) {
            SignedAppDetailView(app: app, certificate: certificate, certificateDecoded: certificateDecoded)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = ipaURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Install Failed", isPresented: .constant(installError != nil)) {
            Button("OK") { installError = nil }
        } message: {
            Text(installError ?? "")
        }
        .alert("Delete App", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Storage.shared.deleteSignedApp(app)
            }
        } message: {
            Text("Are you sure you want to delete this signed app?")
        }
    }
    
    // ✅ LOGIC ĐÚNG: Kiểm tra custom icon trước, nếu không có thì dùng icon từ source app
    private func loadIcon() -> UIImage? {
        guard let uuid = app.uuid,
              let iconFileName = app.iconFileName else {
            return nil
        }
        
        // 1️⃣ Nếu là custom_icon.png → đọc từ SignedApps/<uuid>/Icons/
        if iconFileName == "custom_icon.png" {
            let signedAppDir = FileManager.default.signedAppDirectory(uuid)
            let customIconPath = signedAppDir
                .appendingPathComponent("Icons")
                .appendingPathComponent(iconFileName)
            
            if FileManager.default.fileExists(atPath: customIconPath.path),
               let image = UIImage(contentsOfFile: customIconPath.path) {
                return image
            }
        }
        
        // 2️⃣ Nếu không phải custom icon → đọc từ source app: Apps/<sourceUUID>/Icons/
        if let sourceUUID = app.sourceUUID {
            let sourceIconPath = FileManager.default
                .iconsDirectory(for: sourceUUID)
                .appendingPathComponent(iconFileName)
            
            if FileManager.default.fileExists(atPath: sourceIconPath.path),
               let image = UIImage(contentsOfFile: sourceIconPath.path) {
                return image
            }
        }
        
        return nil
    }
    
    private func installApp() {
        isInstalling = true
        installError = nil
        
        Task {
            do {
                let handler = InstallHandler(signedApp: app)
                
                Task.detached {
                    try? await handler.install()
                }
                
                try await Task.sleep(nanoseconds: 5_000_000_000)
                
                await MainActor.run {
                    isInstalling = false
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    installError = error.localizedDescription
                }
            }
        }
    }
    
    private func showInFiles() {
        guard let uuid = app.uuid else { return }
        let dir = FileManager.default.signedAppDirectory(uuid)
        
        if let url = URL(string: "shareddocuments://\(dir.path)") {
            UIApplication.shared.open(url)
        }
    }
}
// MARK: - Detail View
struct SignedAppDetailView: View {
    let app: SignedApp
    let certificate: CertificatePair?
    let certificateDecoded: Certificate?
    
    @Environment(\.dismiss) var dismiss
    
    private var ipaURL: URL? {
        guard let uuid = app.uuid else { return nil }
        let dir = FileManager.default.signedAppDirectory(uuid)
        let ipaName = (app.name ?? "SignedApp").replacingOccurrences(of: " ", with: "_") + ".ipa"
        let ipaPath = dir.appendingPathComponent(ipaName)
        return FileManager.default.fileExists(atPath: ipaPath.path) ? ipaPath : nil
    }
    
    private var fileSize: String {
        guard let url = ipaURL,
              let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var body: some View {
        NavigationView {
            List {
                Section("App Information") {
                    DetailRow(label: "Name", value: app.name ?? "Unknown")
                    DetailRow(label: "Bundle ID", value: app.identifier ?? "Unknown")
                    DetailRow(label: "Version", value: app.version ?? "Unknown")
                    DetailRow(label: "File Size", value: fileSize)
                    
                    if let date = app.date {
                        DetailRow(label: "Signed Date", value: date.formatted(date: .long, time: .shortened))
                    }
                }
                
                if let decoded = certificateDecoded {
                    Section("Certificate Information") {
                        DetailRow(label: "Team Name", value: decoded.TeamName)
                        DetailRow(label: "Team ID", value: decoded.TeamIdentifier.first ?? "Unknown")
                        DetailRow(label: "Profile Name", value: decoded.Name)
                        DetailRow(label: "Expiration", value: decoded.ExpirationDate.formatted(date: .long, time: .omitted))
                        
                        if let ppq = decoded.PPQCheck {
                            DetailRow(label: "PPQ Check", value: ppq ? "Enabled" : "Disabled")
                        }
                    }
                }
                
                if let url = ipaURL {
                    Section("File Location") {
                        Text(url.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("App Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack) // FIX: Force stack style cho iPad
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIActivityViewController
    
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Batch Sign View
struct BatchSignView: View {
    let selectedApps: [ImportedApp]
    @Environment(\.dismiss) var dismiss
    
    @State private var appCertificates: [NSManagedObjectID: CertificatePair?] = [:]
    @State private var appCustomNames: [NSManagedObjectID: String] = [:]
    @State private var appCustomBundleIDs: [NSManagedObjectID: String] = [:]
    @State private var appCustomVersions: [NSManagedObjectID: String] = [:]
    @State private var isSigning = false
    @State private var currentSigningApp: String = ""
    @State private var overallProgress: Double = 0.0
    @State private var currentAppProgress: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var completedCount = 0
    @State private var failedApps: [String] = []
    
    private var certificates: [CertificatePair] {
        Storage.shared.fetchCertificates()
    }
    
    private var defaultCertificate: CertificatePair? {
        certificates.first(where: { $0.isDefault })
    }
    
    private var canStartSigning: Bool {
        !selectedApps.isEmpty && appCertificates.values.allSatisfy { $0 != nil }
    }
    
    var body: some View {
        ZStack {
            Form {
                Section {
                    Text("\(selectedApps.count) app(s) selected")
                        .font(.headline)
                } header: {
                    Text("Batch Signing")
                }
                
                Section {
                    ForEach(selectedApps, id: \.objectID) { app in
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                AppIconView(app: app, size: 50)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name ?? "Unknown")
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    if let identifier = app.identifier {
                                        Text(identifier)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    if let version = app.version {
                                        Text("Version \(version)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            
                            Divider()
                            
                            // Custom App Info
                            if !isSigning {
                                VStack(spacing: 8) {
                                    TextField("App Name", text: Binding(
                                        get: { appCustomNames[app.objectID] ?? "" },
                                        set: { appCustomNames[app.objectID] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)
                                    
                                    TextField("Bundle ID", text: Binding(
                                        get: { appCustomBundleIDs[app.objectID] ?? "" },
                                        set: { appCustomBundleIDs[app.objectID] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    
                                    TextField("Version", text: Binding(
                                        get: { appCustomVersions[app.objectID] ?? "" },
                                        set: { appCustomVersions[app.objectID] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)
                                }
                            }
                            
                            // Certificate Picker
                            if !isSigning {
                                Menu {
                                    ForEach(certificates, id: \.uuid) { cert in
                                        Button {
                                            appCertificates[app.objectID] = cert
                                        } label: {
                                            HStack {
                                                Text(cert.nickname ?? L("Certificate"))
                                                if cert.isDefault {
                                                    Text("(Default)")
                                                        .font(.caption)
                                                }
                                                if appCertificates[app.objectID]??.uuid == cert.uuid {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "signature")
                                            .foregroundColor(.accentColor)
                                        
                                        if let cert = appCertificates[app.objectID] ?? nil {
                                            Text(cert.nickname ?? L("Certificate"))
                                                .foregroundColor(.primary)
                                        } else {
                                            Text("Select Certificate")
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(8)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "signature")
                                        .foregroundColor(.accentColor)
                                    
                                    if let cert = appCertificates[app.objectID] ?? nil {
                                        Text(cert.nickname ?? L("Certificate"))
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Apps & Certificates")
                } footer: {
                    Text("Customize app info and select certificates. Leave fields empty to keep original values.")
                        .font(.caption)
                }
            }
            .navigationTitle("Batch Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isSigning {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isSigning {
                        Button("Sign All") {
                            startBatchSigning()
                        }
                        .disabled(!canStartSigning)
                    }
                }
            }
            .onAppear {
                // Auto-assign default certificate to all apps
                if let defaultCert = defaultCertificate {
                    for app in selectedApps {
                        appCertificates[app.objectID] = defaultCert
                    }
                }
                
                // Initialize custom fields with original values (empty = keep original)
                for app in selectedApps {
                    appCustomNames[app.objectID] = ""
                    appCustomBundleIDs[app.objectID] = ""
                    appCustomVersions[app.objectID] = ""
                }
            }
            
            if isSigning {
                ProgressOverlay(
                    title: "Signing Apps",
                    subtitle: currentSigningApp,
                    step: L(currentAppProgress),
                    progress: overallProgress,
                    trailingLabel: "\(completedCount)/\(selectedApps.count)"
                )
            }
        }
        .alert("Batch Signing Completed", isPresented: .constant(completedCount == selectedApps.count && !isSigning && completedCount > 0)) {
            Button("OK") {
                dismiss()
            }
        } message: {
            if failedApps.isEmpty {
                Text("All \(selectedApps.count) app(s) signed successfully!")
            } else {
                Text("Signed \(completedCount - failedApps.count) of \(selectedApps.count) app(s).\n\nFailed apps:\n\(failedApps.joined(separator: "\n"))")
            }
        }
        .alert("Signing Error", isPresented: $showError) {
            Button("OK") {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func startBatchSigning() {
        isSigning = true
        completedCount = 0
        failedApps = []
        overallProgress = 0.0
        
        Task {
            for (index, app) in selectedApps.enumerated() {
                guard let certificate = appCertificates[app.objectID] ?? nil else {
                    continue
                }
                
                await MainActor.run {
                    currentSigningApp = app.name ?? "Unknown App"
                    currentAppProgress = "Preparing..."
                }
                
                do {
                    // Create custom options with user-provided values
                    var customOptions = SigningOptionsManager.shared.options
                    
                    // Apply custom name if provided
                    let customName = appCustomNames[app.objectID] ?? ""
                    if !customName.isEmpty {
                        customOptions.appName = customName
                    }
                    
                    // Apply custom bundle ID if provided
                    let customBundleID = appCustomBundleIDs[app.objectID] ?? ""
                    if !customBundleID.isEmpty {
                        customOptions.appIdentifier = customBundleID
                    }
                    
                    // Apply custom version if provided
                    let customVersion = appCustomVersions[app.objectID] ?? ""
                    if !customVersion.isEmpty {
                        customOptions.appVersion = customVersion
                    }
                    
                    let handler = SigningHandler(
                        sourceApp: app,
                        certificate: certificate,
                        options: customOptions
                    )
                    
                    handler.stepProgressCallback = { step in
                        Task { @MainActor in
                            self.currentAppProgress = step
                        }
                    }
                    
                    try await handler.performFullSigning()
                    
                    await MainActor.run {
                        completedCount += 1
                        overallProgress = Double(completedCount) / Double(selectedApps.count)
                    }
                    
                } catch {
                    await MainActor.run {
                        failedApps.append(app.name ?? "Unknown")
                        completedCount += 1
                        overallProgress = Double(completedCount) / Double(selectedApps.count)
                    }
                }
            }
            
            await MainActor.run {
                isSigning = false
            }
        }
    }
}
