//
//  CertificatesManagementView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import Zip

struct CertificatesManagementView: View {
    @StateObject private var storage = Storage.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .default
    )
    private var certificates: FetchedResults<CertificatePair>
    
    @State private var showAddCert = false
    @State private var isCheckingRevoked = false
    @State private var shareURL: URL?
    @State private var selectedCertificate: CertificatePair?
    @State private var showActionSheet = false
    @State private var showDetailView = false
    @State private var isExporting = false
    
    var body: some View {
        ZStack {
            List {
                ForEach(certificates) { cert in
                    CertificateRowContent(
                        certificate: cert,
                        isDefault: cert.isDefault
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCertificate = cert
                        showActionSheet = true
                    }
                }
            }
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddCert = true
                    }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCert) {
                AddCertificateView()
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(isPresented: $showDetailView) {
                if let cert = selectedCertificate {
                    NavigationView {
                        CertificateDetailView(certificate: cert)
                    }
                }
            }
            .confirmationDialog("Certificate Options", isPresented: $showActionSheet, presenting: selectedCertificate) { cert in
                Button("View Details") {
                    showDetailView = true
                }
                
                if !cert.isDefault {
                    Button("Set as Default") {
                        setDefaultCertificate(cert)
                    }
                }
                
                Button("Share Certificate") {
                    shareCertificate(cert)
                }
                
                Button("Delete", role: .destructive) {
                    deleteCertificate(cert)
                }
                
                Button("Cancel", role: .cancel) {}
            } message: { cert in
                Text(cert.nickname ?? L("Certificate"))
            }
            .overlay {
                if certificates.isEmpty {
                    EmptyStateView(
                        title: "No Certificates",
                        systemImage: "key.fill",
                        message: "Add a certificate to sign apps"
                    )
                }
            }
            .onAppear {
                checkAllCertificatesRevoked()
                // Clean up old exported certificate files
                ZSignCertificateHandler.cleanupOldExports()
            }
            
            // Loading overlay when checking revoked status
            if isCheckingRevoked {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Checking certificates...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
            
            // Loading overlay when exporting certificate
            if isExporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Preparing certificate...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
        }
    }
    
    private func checkAllCertificatesRevoked() {
        guard !certificates.isEmpty else { return }
        
        isCheckingRevoked = true
        
        storage.checkAllRevokedCertificates {
            isCheckingRevoked = false
        }
    }
    
    private func setDefaultCertificate(_ certificate: CertificatePair) {
        withAnimation {
            // Set all certificates to non-default
            for cert in certificates {
                cert.isDefault = false
            }
            
            // Set selected certificate as default
            certificate.isDefault = true
            
            // Save changes
            storage.saveContext()
        }
    }
    
    private func deleteCertificate(_ certificate: CertificatePair) {
        withAnimation {
            storage.deleteCertificate(certificate)
            selectedCertificate = nil
        }
    }
    
    private func shareCertificate(_ certificate: CertificatePair) {
        isExporting = true
        Task {
            do {
                let url = try await ZSignCertificateHandler.export(certificate: certificate)
                await MainActor.run {
                    self.isExporting = false
                    self.shareURL = url
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    print("Error exporting certificate: \(error)")
                }
            }
        }
    }
}

// MARK: - URL Extension
extension URL: Identifiable {
    public var id: String {
        self.absoluteString
    }
}

// MARK: - Certificate Row Content
struct CertificateRowContent: View {
    let certificate: CertificatePair
    let isDefault: Bool
    
    private var provision: Certificate? {
        Storage.shared.getProvisionDecoded(for: certificate)
    }
    
    private var isExpired: Bool {
        guard let expiration = certificate.expiration else { return false }
        return expiration < Date()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(certificate.nickname ?? L("Certificate"))
                        .font(.headline)
                    
                    if isDefault {
                        Text("DEFAULT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .cornerRadius(4)
                    }
                    
                    if certificate.revoked {
                        Text("REVOKED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                
                if let provision = provision {
                    // App ID Name
                    Text("App ID: \(provision.AppIDName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(provision.Name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Team: \(provision.TeamName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // PPQ Check badge
                    if let ppqCheck = provision.PPQCheck, ppqCheck {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.caption2)
                            Text("PPQ Check")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                
                if let expiration = certificate.expiration {
                    Label {
                        Text("Expires: \(expiration, style: .date)")
                            .font(.caption2)
                    } icon: {
                        Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.caption)
                    }
                    .foregroundColor(isExpired ? .red : .green)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(certificate.revoked || !isDefault ? 0.6 : 1.0)
    }
}

// MARK: - Add Certificate View
struct AddCertificateView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Import Type", selection: $selectedTab) {
                    Text("Manual").tag(0)
                    Text("ZSign Cert").tag(1)
                    Text("ZIP File").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    ManualAddCertificateView(parentDismiss: dismiss)
                } else if selectedTab == 1 {
                    ZSignCertImportView(parentDismiss: dismiss)
                } else {
                    ZipCertImportView(parentDismiss: dismiss)
                }
            }
            .navigationTitle("Add Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Manual Add Certificate View
struct ManualAddCertificateView: View {
    var parentDismiss: DismissAction? = nil
    @Environment(\.dismiss) var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .default
    )
    private var certificates: FetchedResults<CertificatePair>
    
    @State private var p12URL: URL?
    @State private var provisionURL: URL?
    @State private var password: String = ""
    @State private var nickname: String = ""
    @State private var isDefault: Bool = false
    
    @State private var showP12Picker = false
    @State private var showProvisionPicker = false
    @State private var isValidating = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                FilePickerButton(
                    title: "Certificate (.p12)",
                    selectedFile: p12URL,
                    action: { showP12Picker = true }
                )
                
                FilePickerButton(
                    title: "Provisioning Profile",
                    selectedFile: provisionURL,
                    action: { showProvisionPicker = true }
                )
            } header: {
                Text("Files")
            }
            
            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .autocapitalization(.none)
            } footer: {
                Text("Leave blank if no password required")
                    .font(.caption)
            }
            
            Section {
                TextField("Nickname (Optional)", text: $nickname)
                Toggle("Set as Default", isOn: $isDefault)
            } footer: {
                Text("Default certificate will be automatically selected when signing apps")
                    .font(.caption)
            }
            
            if isValidating {
                Section {
                    HStack {
                        ProgressView()
                        Text("Validating...")
                    }
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Section {
                Button("Save Certificate") {
                    saveCertificate()
                }
                .frame(maxWidth: .infinity)
                .disabled(p12URL == nil || provisionURL == nil || isValidating)
            }
        }
        .sheet(isPresented: $showP12Picker) {
            FileImporterRepresentableView(
                allowedContentTypes: [.p12],
                onDocumentsPicked: { urls in
                    p12URL = urls.first
                }
            )
        }
        .sheet(isPresented: $showProvisionPicker) {
            FileImporterRepresentableView(
                allowedContentTypes: [.mobileProvision],
                onDocumentsPicked: { urls in
                    provisionURL = urls.first
                }
            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func saveCertificate() {
        guard let p12 = p12URL, let provision = provisionURL else { return }
        
        // Nếu chưa có chứng chỉ nào, tự động set làm default
        let shouldBeDefault = certificates.isEmpty || isDefault
        
        isValidating = true
        errorMessage = nil
        
        Task {
            do {
                let handler = CertificateHandler(
                    p12URL: p12,
                    provisionURL: provision,
                    password: password,
                    nickname: nickname.isEmpty ? nil : nickname,
                    isDefault: shouldBeDefault
                )
                
                guard handler.validate() else {
                    await MainActor.run {
                        isValidating = false
                        errorMessage = "Invalid certificate or password"
                    }
                    return
                }
                
                try await handler.copy()
                try await handler.addToDatabase()
                
                await MainActor.run {
                    isValidating = false
                    // Dismiss parent sheet (AddCertificateView)
                    if let parentDismiss = parentDismiss {
                        parentDismiss()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - ZSign Certificate Import View
struct ZSignCertImportView: View {
    var parentDismiss: DismissAction? = nil
    @Environment(\.dismiss) var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .default
    )
    private var certificates: FetchedResults<CertificatePair>
    
    @State private var zsignCertURL: URL?
    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var nickname: String = ""
    @State private var isDefault: Bool = false
    
    var body: some View {
        Form {
            Section {
                Button(action: { showFilePicker = true }) {
                    HStack {
                        Text(zsignCertURL == nil ? "Select .zsigncert file" : "Selected file")
                            .foregroundColor(zsignCertURL == nil ? .accentColor : .secondary)
                        Spacer()
                        if let file = zsignCertURL {
                            Text(file.lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } header: {
                Text("ZSign Certificate File")
            } footer: {
                Text("Import a certificate package shared from another device")
                    .font(.caption)
            }
            
            if zsignCertURL != nil {
                Section {
                    TextField("Nickname (Optional)", text: $nickname)
                    Toggle("Set as Default", isOn: $isDefault)
                }
                
                if isImporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Importing...")
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button("Import Certificate") {
                        importZSignCertificate()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(zsignCertURL == nil || isImporting)
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            FileImporterRepresentableView(
                allowedContentTypes: [.zsignCert],
                onDocumentsPicked: { urls in
                    zsignCertURL = urls.first
                }
            )
        }
    }
    
    private func importZSignCertificate() {
        guard let url = zsignCertURL else { return }
        
        // Nếu chưa có chứng chỉ nào, tự động set làm default
        let shouldBeDefault = certificates.isEmpty || isDefault
        
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                try await ZSignCertificateHandler.import(
                    from: url,
                    nickname: nickname.isEmpty ? nil : nickname,
                    isDefault: shouldBeDefault
                )
                
                await MainActor.run {
                    isImporting = false
                    // Dismiss parent sheet (AddCertificateView)
                    if let parentDismiss = parentDismiss {
                        parentDismiss()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - ZIP Certificate Import View
struct ZipCertImportView: View {
    var parentDismiss: DismissAction? = nil
    @Environment(\.dismiss) var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .default
    )
    private var certificates: FetchedResults<CertificatePair>
    
    @State private var zipURL: URL?
    @State private var password: String = ""
    @State private var nickname: String = ""
    @State private var isDefault: Bool = false
    
    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                Button(action: { showFilePicker = true }) {
                    HStack {
                        Text(zipURL == nil ? "Select ZIP file" : "Selected file")
                            .foregroundColor(zipURL == nil ? .accentColor : .secondary)
                        Spacer()
                        if let file = zipURL {
                            Text(file.lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } header: {
                Text("ZIP File")
            } footer: {
                Text("Select a ZIP file containing .p12 and .mobileprovision files")
                    .font(.caption)
            }
            
            if zipURL != nil {
                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .autocapitalization(.none)
                } header: {
                    Text("Certificate Password")
                } footer: {
                    Text("Enter the password for the .p12 certificate file")
                        .font(.caption)
                }
                
                Section {
                    TextField("Nickname (Optional)", text: $nickname)
                    Toggle("Set as Default", isOn: $isDefault)
                } footer: {
                    Text("If nickname is not provided, the P12 filename will be used")
                        .font(.caption)
                }
                
                if isImporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Importing...")
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button("Import Certificate") {
                        importZipCertificate()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(zipURL == nil || isImporting)
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            FileImporterRepresentableView(
                allowedContentTypes: [.zip],
                onDocumentsPicked: { urls in
                    zipURL = urls.first
                }
            )
        }
    }
    
    private func importZipCertificate() {
        guard let url = zipURL else { return }
        
        // Nếu chưa có chứng chỉ nào, tự động set làm default
        let shouldBeDefault = certificates.isEmpty || isDefault
        
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                try await ZipCertificateHandler.import(
                    from: url,
                    password: password,
                    nickname: nickname.isEmpty ? nil : nickname,
                    isDefault: shouldBeDefault
                )
                
                await MainActor.run {
                    isImporting = false
                    // Dismiss parent sheet (AddCertificateView)
                    if let parentDismiss = parentDismiss {
                        parentDismiss()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - File Picker Button
struct FilePickerButton: View {
    let title: String
    let selectedFile: URL?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(selectedFile == nil ? .accentColor : .secondary)
                Spacer()
                if let file = selectedFile {
                    Text(file.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .disabled(selectedFile != nil)
    }
}
