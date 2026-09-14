//
//  CertificatesManagementView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//
//  Dựng bằng bộ thẻ dùng chung (Theme + CardComponents) thay cho List/Form,
//  để nền và thẻ theo đúng tông của app. Mỗi chứng chỉ là MỘT thẻ riêng vì
//  nội dung một hàng khá dài (tên, App ID, hồ sơ, đội, hạn dùng).
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

    /// uuid của những chứng chỉ có chứa UDID của CHÍNH máy này.
    /// Quét một lần khi mở màn, không quét lại mỗi lần vẽ.
    @State private var deviceCertUUIDs: Set<String> = []

    var body: some View {
        ZStack {
            content
            .screenChrome("Certificates")
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
            .onAppear {
                checkAllCertificatesRevoked()
                // Clean up old exported certificate files
                ZSignCertificateHandler.cleanupOldExports()
            }
            .task(id: certificates.count) {
                await scanDeviceCertificates()
            }

            if isCheckingRevoked {
                ProgressOverlay(title: "Checking certificates...")
            }

            if isExporting {
                ProgressOverlay(title: "Preparing certificate...")
            }
        }
    }
    
    /// Danh sách chứng chỉ, hoặc màn trống khi chưa có cái nào.
    ///
    /// Trước đây màn trống được gắn bằng `.overlay { EmptyStateView }` chồng
    /// lên một ScrollView RỖNG. ContentUnavailableView bên trong overlay không
    /// nhận được kích thước nên tự vẽ nền trắng của hệ thống, để lộ hai mảng
    /// trắng cùng một vệt nền ở giữa.
    @ViewBuilder
    private var content: some View {
        if certificates.isEmpty {
            EmptyStateView(
                title: "No Certificates",
                systemImage: "key.fill",
                message: "Add a certificate to sign apps"
            ) {
                Button { showAddCert = true } label: {
                    Label("Add Certificate", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
        } else {
            CardScreen {
                ForEach(certificates) { cert in
                    CertificateRowContent(
                        certificate: cert,
                        isDefault: cert.isDefault,
                        isForThisDevice: deviceCertUUIDs.contains(cert.uuid ?? "")
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCertificate = cert
                        showActionSheet = true
                    }
                }
            }
        }
    }

    /// Đọc UDID của máy (từ embedded.mobileprovision của chính app này), rồi
    /// dò xem hồ sơ cấp quyền của từng chứng chỉ có chứa UDID đó không.
    ///
    /// Đường dẫn tệp lấy trên main thread vì CertificatePair là NSManagedObject;
    /// phần đọc tệp và giải mã plist chạy ngoài main thread.
    private func scanDeviceCertificates() async {
        guard let udid = UDIDReader.deviceUDID()?.lowercased(), !udid.isEmpty else {
            deviceCertUUIDs = []
            return
        }

        let pairs: [(String, URL)] = certificates.compactMap { cert in
            guard let uuid = cert.uuid,
                  let url = Storage.shared.getCertificateFile(.mobileprovision, from: cert)
            else { return nil }
            return (uuid, url)
        }
        guard !pairs.isEmpty else {
            deviceCertUUIDs = []
            return
        }

        let matched = await Task.detached(priority: .userInitiated) { () -> Set<String> in
            var found: Set<String> = []
            for (uuid, url) in pairs {
                guard let devices = CertificateReader(url).decoded?.ProvisionedDevices else { continue }
                if devices.contains(where: { $0.lowercased() == udid }) {
                    found.insert(uuid)
                }
            }
            return found
        }.value

        guard !Task.isCancelled else { return }
        deviceCertUUIDs = matched
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
    /// Hồ sơ của chứng chỉ này có chứa UDID của chính máy đang chạy.
    var isForThisDevice: Bool = false

    /// Giải mã mobileprovision MỘT lần rồi giữ lại.
    /// Trước đây đây là computed property -> mỗi lần SwiftUI vẽ lại là một lần
    /// đọc tệp từ đĩa và giải mã plist, cho TỪNG chứng chỉ.
    @State private var provision: Certificate?

    private var isExpired: Bool {
        guard let expiration = certificate.expiration else { return false }
        return expiration < Date()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isForThisDevice {
                deviceMatchRow
            }

            if let provision = provision {
                details(provision)
            }
            
            if let expiration = certificate.expiration {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                expiryRow(expiration)
            }
        }
        .cardStyle()
        .opacity(certificate.revoked || !isDefault ? 0.6 : 1.0)
        .task(id: certificate.uuid) {
            guard provision == nil else { return }
            provision = Storage.shared.getProvisionDecoded(for: certificate)
        }
    }

    /// Dòng đỏ báo chứng chỉ này ký được cho chính máy đang cầm.
    private var deviceMatchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.gen3")
                .font(.caption)
            Text("Certificate for this device")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.red)
        .padding(.leading, Theme.Metric.iconBox + 12)
    }
    
    // MARK: - Tên + nhãn trạng thái
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                .foregroundStyle(certificate.revoked ? Color.red : Color.accentColor)
                .frame(width: Theme.Metric.iconBox, alignment: .center)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(certificate.nickname ?? L("Certificate"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                
                if isDefault || certificate.revoked {
                    HStack(spacing: 6) {
                        if isDefault {
                            badge("DEFAULT", color: .accentColor)
                        }
                        
                        if certificate.revoked {
                            badge("REVOKED", color: .red)
                        }
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            CardChevron()
        }
    }
    
    private func badge(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
    
    // MARK: - Thông tin hồ sơ cấp quyền
    
    private func details(_ provision: Certificate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // App ID Name
            Text("App ID: \(provision.AppIDName)")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
            
            Text(provision.Name)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
            
            Text("Team: \(provision.TeamName)")
                .font(.caption2)
                .foregroundStyle(Theme.ink3)
            
            // PPQ Check badge
            if let ppqCheck = provision.PPQCheck, ppqCheck {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption2)
                    Text("PPQ Check")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.green.opacity(0.12)))
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Theme.Metric.iconBox + 12)
    }
    
    // MARK: - Hạn dùng
    
    private func expiryRow(_ expiration: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption)
            Text("Expires: \(expiration, style: .date)")
                .font(.caption2)
            Spacer(minLength: 8)
        }
        .foregroundStyle(isExpired ? Color.red : Color.green)
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
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.vertical, 12)
                
                if selectedTab == 0 {
                    ManualAddCertificateView(parentDismiss: dismiss)
                } else if selectedTab == 1 {
                    ZSignCertImportView(parentDismiss: dismiss)
                } else {
                    ZipCertImportView(parentDismiss: dismiss)
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .screenChrome("Add Certificate")
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
    
    private var canSave: Bool {
        p12URL != nil && provisionURL != nil && !isValidating
    }
    
    var body: some View {
        CardScreen {
            CardGroup(L("Files")) {
                FilePickerButton(
                    title: L("Certificate (.p12)"),
                    selectedFile: p12URL,
                    action: { showP12Picker = true }
                )
                
                CardDivider()
                
                FilePickerButton(
                    title: L("Provisioning Profile"),
                    selectedFile: provisionURL,
                    action: { showProvisionPicker = true }
                )
            }
            
            CardGroup(footnote: L("Leave blank if no password required")) {
                CertInputRow(icon: "lock.fill",
                             title: L("Password"),
                             text: $password,
                             secure: true)
            }
            
            CardGroup(footnote: L("Default certificate will be automatically selected when signing apps")) {
                CertInputRow(icon: "tag.fill",
                             title: L("Nickname (Optional)"),
                             text: $nickname)
                
                CardDivider()
                
                CardToggleRow(icon: "star.fill",
                              title: L("Set as Default"),
                              isOn: $isDefault)
            }
            
            if isValidating {
                CardGroup {
                    CertStatusRow(title: "Validating...")
                }
            }
            
            if let error = errorMessage {
                CardGroup {
                    CertErrorRow(message: error)
                }
            }
            
            FilledButton(title: L("Save Certificate"),
                         icon: "checkmark.circle.fill") {
                saveCertificate()
            }
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
            .padding(.top, 4)
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
        CardScreen {
            CardGroup(L("ZSign Certificate File"),
                      footnote: L("Import a certificate package shared from another device")) {
                FilePickerButton(
                    title: zsignCertURL == nil ? L("Select .zsigncert file") : L("Selected file"),
                    selectedFile: zsignCertURL,
                    action: { showFilePicker = true }
                )
            }
            
            if zsignCertURL != nil {
                CardGroup {
                    CertInputRow(icon: "tag.fill",
                                 title: L("Nickname (Optional)"),
                                 text: $nickname)
                    
                    CardDivider()
                    
                    CardToggleRow(icon: "star.fill",
                                  title: L("Set as Default"),
                                  isOn: $isDefault)
                }
                
                if isImporting {
                    CardGroup {
                        CertStatusRow(title: "Importing...")
                    }
                }
                
                if let error = errorMessage {
                    CardGroup {
                        CertErrorRow(message: error)
                    }
                }
                
                FilledButton(title: L("Import Certificate"),
                             icon: "square.and.arrow.down.fill") {
                    importZSignCertificate()
                }
                .disabled(zsignCertURL == nil || isImporting)
                .opacity(isImporting ? 0.5 : 1)
                .padding(.top, 4)
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
        CardScreen {
            CardGroup(L("ZIP File"),
                      footnote: L("Select a ZIP file containing .p12 and .mobileprovision files")) {
                FilePickerButton(
                    title: zipURL == nil ? L("Select ZIP file") : L("Selected file"),
                    selectedFile: zipURL,
                    action: { showFilePicker = true }
                )
            }
            
            if zipURL != nil {
                CardGroup(L("Certificate Password"),
                          footnote: L("Enter the password for the .p12 certificate file")) {
                    CertInputRow(icon: "lock.fill",
                                 title: L("Password"),
                                 text: $password,
                                 secure: true)
                }
                
                CardGroup(footnote: L("If nickname is not provided, the P12 filename will be used")) {
                    CertInputRow(icon: "tag.fill",
                                 title: L("Nickname (Optional)"),
                                 text: $nickname)
                    
                    CardDivider()
                    
                    CardToggleRow(icon: "star.fill",
                                  title: L("Set as Default"),
                                  isOn: $isDefault)
                }
                
                if isImporting {
                    CardGroup {
                        CertStatusRow(title: "Importing...")
                    }
                }
                
                if let error = errorMessage {
                    CardGroup {
                        CertErrorRow(message: error)
                    }
                }
                
                FilledButton(title: L("Import Certificate"),
                             icon: "square.and.arrow.down.fill") {
                    importZipCertificate()
                }
                .disabled(zipURL == nil || isImporting)
                .opacity(isImporting ? 0.5 : 1)
                .padding(.top, 4)
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
            CardRow(icon: selectedFile == nil ? "doc.badge.plus" : "checkmark.circle.fill",
                    title: title,
                    subtitle: selectedFile?.lastPathComponent,
                    iconTint: selectedFile == nil ? Color.accentColor : .green) {
                if selectedFile == nil {
                    CardChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(selectedFile != nil)
    }
}

// MARK: - Ô nhập dùng trong các màn nhập chứng chỉ

/// Hàng nhập liệu trong thẻ: nhãn nhỏ phía trên, ô nhập phía dưới.
private struct CertInputRow: View {
    let icon: String
    let title: String
    @Binding var text: String
    var secure: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: Theme.Metric.iconBox, alignment: .center)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                
                if secure {
                    SecureField("", text: $text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .textContentType(.password)
                        .autocapitalization(.none)
                } else {
                    TextField("", text: $text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
            }
            
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Theme.Metric.rowHeight)
    }
}

/// Hàng "đang xử lý" bên trong thẻ (khác với ProgressOverlay phủ toàn màn hình).
private struct CertStatusRow: View {
    let title: LocalizedStringKey
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .frame(width: Theme.Metric.iconBox, alignment: .center)
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
            
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.Metric.rowHeight)
    }
}

/// Hàng báo lỗi bên trong thẻ.
private struct CertErrorRow: View {
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: Theme.Metric.iconBox, alignment: .center)
            
            Text(L(message))
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.Metric.rowHeight)
    }
}
