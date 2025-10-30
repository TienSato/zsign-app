//
//  SignAppView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import SwiftUI
import PhotosUI

struct SignAppView: View {
    let app: ImportedApp
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedCertificate: CertificatePair?
    @State private var showCertificatePicker = false
    @State private var showAlternativeIcons = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    @State private var isSigning = false
    @State private var signingProgress: String = ""
    @State private var compressionProgress: Double = 0.0
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showRevokedWarning = false
    
    // Local copy of options for THIS sign session
    @State private var customName: String = ""
    @State private var customBundleID: String = ""
    @State private var customVersion: String = ""
    @State private var appIcon: UIImage?
    @State private var hasInitialized = false
    
    // Clone App feature
    @State private var isCloneMode: Bool = false
    @State private var cloneSuffix: String = ""
    
    // Auto Install feature
    @State private var autoInstall: Bool = false
    @State private var sessionDisabledTweaks: [String] = []
    
    // Quick Settings
    @State private var quickInjectPath: String = SigningOptions.injectPathValues[0]
    @State private var quickInjectFolder: String = SigningOptions.injectFolderValues[1]
    @State private var quickFileSharing: Bool = false
    @State private var quickGameMode: Bool = false
    @State private var quickRemoveProvisionAfterSigning: Bool = false
    @State private var showCustomInfoPlistEditor = false
    @State private var quickCustomInfoPlist: [String: String] = [:]
    @State private var sessionInjectionFiles: [URL] = []
    
    private var certificates: [CertificatePair] {
        Storage.shared.fetchCertificates()
    }
    
    private var defaultCertificate: CertificatePair? {
        certificates.first(where: { $0.isDefault })
    }
    
    private var provision: Certificate? {
        guard let cert = selectedCertificate else { return nil }
        return Storage.shared.getProvisionDecoded(for: cert)
    }
    
    private var daysUntilExpiration: Int? {
        guard let expiration = selectedCertificate?.expiration else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiration)
        return components.day
    }
    
    private var isExpired: Bool {
        guard let expiration = selectedCertificate?.expiration else { return false }
        return expiration < Date()
    }
    
    var body: some View {
        Form {
            // App Information Section
            Section {
                // Icon Picker Menu
                Menu {
                    Button {
                        showAlternativeIcons = true
                    } label: {
                        Label("Select Alternative Icon", systemImage: "app.dashed")
                    }
                    
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }
                    
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose from Photos", systemImage: "photo")
                    }
                    
                    if appIcon != nil {
                        Divider()
                        Button(role: .destructive) {
                            appIcon = nil
                        } label: {
                            Label("Reset to Original", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        if let icon = appIcon {
                            Image(uiImage: icon)
                                .appIconStyle(size: 60)
                        } else {
                            AppIconView(app: app, size: 60)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Icon")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(appIcon == nil ? "Tap to customize" : "Custom icon selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                // Clone App Toggle
                Toggle(isOn: $isCloneMode) {
                    HStack {
                        Label("Clone App", systemImage: "doc.on.doc.fill")
                        Spacer()
                    }
                }
                .onChange(of: isCloneMode) { newValue in
                    if newValue {
                        applyCloneMode()
                    } else {
                        removeCloneMode()
                    }
                }
                
                if isCloneMode {
                    HStack {
                        Text("Clone Suffix:")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Spacer()
                        Text(cloneSuffix)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 4)
                }
                
                TextField("App Name", text: $customName)
                    .autocapitalization(.words)
                    .disabled(isCloneMode)
                
                TextField("Bundle ID", text: $customBundleID)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .disabled(isCloneMode)
                
                TextField("Version", text: $customVersion)
                    
            } header: {
                Text("App Information")
            } footer: {
                if isCloneMode {
                    Text("Clone mode enabled. App name and bundle ID will be automatically modified with suffix '\(cloneSuffix)'")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("Leave fields as-is to keep original values, or modify to customize")
                        .font(.caption)
                }
            }
        
            // Certificate Section
            Section {
                if certificates.isEmpty {
                    Text("No certificates available")
                        .foregroundColor(.secondary)
                } else if let cert = selectedCertificate {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cert.nickname ?? "Certificate")
                                    .font(.headline)
                                
                                if let provision = provision {
                                    Text(provision.Name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Team: \(provision.TeamName)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button {
                                showCertificatePicker = true
                            } label: {
                                Text("Change")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "calendar")
                                    .foregroundColor(isExpired ? .red : .green)
                                    .font(.caption)
                                
                                if let days = daysUntilExpiration {
                                    if isExpired {
                                        Text("Expired")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    } else {
                                        Text("Expires in \(days) days")
                                            .font(.caption)
                                            .foregroundColor(days < 7 ? .orange : .green)
                                    }
                                }
                            }
                            
                            HStack(spacing: 8) {
                                Image(systemName: cert.ppqCheck ? "checkmark.shield.fill" : "xmark.shield")
                                    .foregroundColor(cert.ppqCheck ? .blue : .gray)
                                    .font(.caption)
                                
                                Text("PPQ Check: \(cert.ppqCheck ? "Enabled" : "Disabled")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if cert.revoked {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    
                                    Text("Certificate Revoked")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        showCertificatePicker = true
                    } label: {
                        HStack {
                            Text("Select Certificate")
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Certificate")
            } footer: {
                if let cert = selectedCertificate, cert.revoked {
                    Text("This certificate has been revoked. Signing may fail or the app may not install properly.")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        
            Section {
                NavigationLink {
                    AppTweaksManagerView(app: app, disabledTweaks: $sessionDisabledTweaks)
                } label: {
                    HStack {
                        Label("Manage App Tweaks", systemImage: "slider.horizontal.3")
                        Spacer()
                        
                        // Show disabled count
                        if !sessionDisabledTweaks.isEmpty {
                            Text("\(sessionDisabledTweaks.count) disabled")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Inject additional external tweaks
                NavigationLink {
                    TweakManagementView(injectionFiles: $sessionInjectionFiles)
                } label: {
                    HStack {
                        Label("Inject Additional Tweaks", systemImage: "syringe")
                        Spacer()
                        Text("(\(sessionInjectionFiles.count))")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                Picker("Inject Path", selection: $quickInjectPath) {
                    ForEach(SigningOptions.injectPathValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                
                Picker("Inject Folder", selection: $quickInjectFolder) {
                    ForEach(SigningOptions.injectFolderValues, id: \.self) { value in
                        Text(value == "/" ? "Root" : value).tag(value)
                    }
                }
            } header: {
                Text("Tweaks")
            } footer: {
                Text("Manage tweaks inside the app or inject new ones. Disabled tweaks won't be injected when signing.")
            }
        
            // Quick Settings Section
            Section {
                Toggle(isOn: $autoInstall) {
                    HStack {
                        Label("Auto Install After Signing", systemImage: "arrow.down.circle.fill")
                        Spacer()
                    }
                }
                .tint(.green)
                
                Toggle("File Sharing", isOn: $quickFileSharing)
                
                Toggle("Game Mode", isOn: $quickGameMode)
                
                Toggle("Remove Provision After Signing", isOn: $quickRemoveProvisionAfterSigning)
                
                Button {
                    showCustomInfoPlistEditor = true
                } label: {
                    HStack {
                        Text("Custom Info.plist Entries")
                        Spacer()
                        if !quickCustomInfoPlist.isEmpty {
                            Text("\(quickCustomInfoPlist.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("Quick Settings", systemImage: "")
            } footer: {
                if autoInstall {
                    Text("Auto-install is enabled. The app will be installed automatically after signing completes.")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("These settings apply only to this signing session and won't be saved as defaults")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        
            // Signing Options Link
            Section {
                NavigationLink {
                    SigningOptionsView()
                } label: {
                    Label("Advanced Signing Options", systemImage: "signature")
                }
            }
        
            // Progress
            if isSigning {
                Section("Progress") {
                    VStack(spacing: 12) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(signingProgress)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if signingProgress.contains("Creating IPA") && compressionProgress > 0 {
                            VStack(spacing: 4) {
                                ProgressView(value: compressionProgress)
                                Text("\(Int(compressionProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("App will continue running in background")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        
            // Sign Button
            Section {
                Button {
                    if selectedCertificate?.revoked == true {
                        showRevokedWarning = true
                    } else {
                        signApp()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign App")
                        Spacer()
                    }
                }
                .disabled(selectedCertificate == nil || isSigning)
            }
        }
        .navigationTitle("Sign \(app.name ?? "App")")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasInitialized {
                customName = app.name ?? ""
                customBundleID = app.identifier ?? ""
                customVersion = app.version ?? ""
                hasInitialized = true
            }
            
            if selectedCertificate == nil {
                selectedCertificate = defaultCertificate ?? certificates.first
            }
        }
        .sheet(isPresented: $showCertificatePicker) {
            CertificatePickerView(selectedCertificate: $selectedCertificate)
        }
        .sheet(isPresented: $showAlternativeIcons) {
            NavigationView {
                SigningAppAlternativeIconView(app: app, appIcon: $appIcon)
            }
        }
        .sheet(isPresented: $showFilePicker) {
            FileImporterRepresentableView(
                allowedContentTypes: [.image],
                onDocumentsPicked: { urls in
                    guard let url = urls.first else { return }
                    loadImageFromFile(url: url)
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    appIcon = image.resizeToSquare()
                }
            }
        }
        .sheet(isPresented: $showCustomInfoPlistEditor) {
            QuickCustomInfoPlistView(entries: $quickCustomInfoPlist)
        }
        .alert("Certificate Revoked", isPresented: $showRevokedWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Anyway", role: .destructive) {
                signApp()
            }
        } message: {
            Text("This certificate has been revoked. The signed app may not install or run properly. Do you want to continue?")
        }
        .alert("Signing Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func loadImageFromFile(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        if let image = UIImage(contentsOfFile: url.path) {
            appIcon = image.resizeToSquare()
        }
    }
    
    private func applyCloneMode() {
        cloneSuffix = String(format: "%04d", Int.random(in: 1000...9999))
        let originalName = app.name ?? ""
        customName = "\(originalName) \(cloneSuffix)"
        let originalBundle = app.identifier ?? ""
        customBundleID = "\(originalBundle).\(cloneSuffix)"
    }
    
    private func removeCloneMode() {
        customName = app.name ?? ""
        customBundleID = app.identifier ?? ""
        cloneSuffix = ""
    }
    
    private func findRecentlySignedApp(bundleID: String) -> SignedApp? {
        let context = Storage.shared.container.viewContext
        let fetchRequest = SignedApp.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SignedApp.date, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        if let results = try? context.fetch(fetchRequest),
           let signedApp = results.first,
           signedApp.identifier == bundleID {
            return signedApp
        }
        
        return nil
    }
    
    private func signApp() {
        guard let certificate = selectedCertificate else { return }
        
        isSigning = true
        signingProgress = "Starting..."
        compressionProgress = 0.0
        
        Task {
            do {
                var options = SigningOptionsManager.shared.options
                
                if customName != (app.name ?? "") && !customName.isEmpty {
                    options.appName = customName
                }
                
                if customBundleID != (app.identifier ?? "") && !customBundleID.isEmpty {
                    options.appIdentifier = customBundleID
                }
                
                if customVersion != (app.version ?? "") && !customVersion.isEmpty {
                    options.appVersion = customVersion
                }
                
                options.injectPath = quickInjectPath
                options.injectFolder = quickInjectFolder
                options.fileSharing = quickFileSharing
                options.gameMode = quickGameMode
                options.removeProvisionAfterSigning = quickRemoveProvisionAfterSigning
                
                options.injectionFiles = sessionInjectionFiles
                
                for (key, value) in quickCustomInfoPlist {
                    options.customInfoPlistEntries[key] = value
                }
                
                let handler = SigningHandler(
                    sourceApp: app,
                    certificate: certificate,
                    options: options,
                    customIcon: appIcon,
                    disabledTweaks: sessionDisabledTweaks
                )
                
                handler.progressCallback = { progress in
                    Task { @MainActor in
                        self.compressionProgress = progress
                    }
                }
                
                handler.stepProgressCallback = { step in
                    Task { @MainActor in
                        self.signingProgress = step
                    }
                }
                
                try await handler.performFullSigning()
                
                if autoInstall {
                    await MainActor.run {
                        self.signingProgress = "Opening installation..."
                    }
                    
                    if let signedApp = findRecentlySignedApp(bundleID: customBundleID) {
                        let installHandler = InstallHandler(signedApp: signedApp)
                        
                        Task.detached {
                            try? await installHandler.install()
                        }
                        
                        await MainActor.run {
                            self.signingProgress = "Installing app..."
                        }
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        
                    }
                }
                await MainActor.run {
                    isSigning = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSigning = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Certificate Picker View
struct CertificatePickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedCertificate: CertificatePair?
    
    private var certificates: [CertificatePair] {
        Storage.shared.fetchCertificates()
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(certificates) { cert in
                    Button {
                        selectedCertificate = cert
                        dismiss()
                    } label: {
                        CertificatePickerRow(
                            certificate: cert,
                            isSelected: selectedCertificate?.uuid == cert.uuid
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Certificate Picker Row
struct CertificatePickerRow: View {
    let certificate: CertificatePair
    let isSelected: Bool
    
    private var provision: Certificate? {
        Storage.shared.getProvisionDecoded(for: certificate)
    }
    
    private var isExpired: Bool {
        guard let expiration = certificate.expiration else { return false }
        return expiration < Date()
    }
    
    private var daysUntilExpiration: Int? {
        guard let expiration = certificate.expiration else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiration)
        return components.day
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(certificate.nickname ?? "Certificate")
                        .font(.headline)
                    
                    if certificate.isDefault {
                        Text("DEFAULT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    
                    if certificate.revoked {
                        Text("REVOKED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                
                if let provision = provision {
                    Text(provision.Name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Team: \(provision.TeamName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    if let days = daysUntilExpiration {
                        Label {
                            if isExpired {
                                Text("Expired")
                                    .font(.caption2)
                            } else {
                                Text("\(days)d left")
                                    .font(.caption2)
                            }
                        } icon: {
                            Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "calendar")
                                .font(.caption2)
                        }
                        .foregroundColor(isExpired ? .red : (days < 7 ? .orange : .green))
                    }
                    
                    Label {
                        Text("PPQ")
                            .font(.caption2)
                    } icon: {
                        Image(systemName: certificate.ppqCheck ? "checkmark.shield.fill" : "xmark.shield")
                            .font(.caption2)
                    }
                    .foregroundColor(certificate.ppqCheck ? .blue : .gray)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(certificate.revoked ? 0.7 : 1.0)
    }
}

// MARK: - Quick Custom Info.plist Editor
struct QuickCustomInfoPlistView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var entries: [String: String]
    
    @State private var showAddEntry = false
    @State private var newKey = ""
    @State private var newValue = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(entries.keys.sorted()), id: \.self) { key in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.headline)
                            Text(entries[key] ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .onDelete { indexSet in
                    let keys = Array(entries.keys.sorted())
                    for index in indexSet {
                        entries.removeValue(forKey: keys[index])
                    }
                }
            }
            .navigationTitle("Custom Entries")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") {
                    dismiss()
                },
                trailing: Button(action: {
                    showAddEntry = true
                }) {
                    Image(systemName: "plus")
                }
            )
            .sheet(isPresented: $showAddEntry) {
                NavigationView {
                    Form {
                        TextField("Key", text: $newKey)
                            .autocapitalization(.none)
                        TextField("Value", text: $newValue)
                    }
                    .navigationTitle("Add Entry")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showAddEntry = false
                            newKey = ""
                            newValue = ""
                        },
                        trailing: Button("Add") {
                            entries[newKey] = newValue
                            showAddEntry = false
                            newKey = ""
                            newValue = ""
                        }
                        .disabled(newKey.isEmpty || newValue.isEmpty)
                    )
                }
            }
            .overlay {
                if entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Custom Entries")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Add custom Info.plist entries for this signing session")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
    }
}
