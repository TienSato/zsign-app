//
//  SignAppView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//
//  Giao diện dạng thẻ (Theme + CardComponents). Toàn bộ luồng ký
//  (signApp / findRecentlySignedApp / InstallHandler / tiến trình) giữ nguyên.
//  Phần tiến trình vẫn là MỘT THẺ nằm trong dòng chảy nội dung, không phải
//  lớp phủ che màn hình.
//

import SwiftUI
import PhotosUI

struct SignAppView: View {
    let app: ImportedApp
    @Environment(\.dismiss) var dismiss

    @State private var selectedCertificate: CertificatePair?
    @AppStorage("zsign.loggingEnabled") private var loggingEnabled = false
    @State private var showLogPanel = false
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
        CardScreen {
            appInfoGroup
            certificateGroup
            tweaksGroup
            quickSettingsGroup
            advancedOptionsGroup

            if isSigning {
                progressGroup
                backgroundNoteGroup
            }

            signButton
        }
        .screenChrome("Sign \(app.name ?? "App")")
        .overlay {
            if loggingEnabled && showLogPanel {
                SignLogOverlay(present: $showLogPanel)
            }
        }
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

    // MARK: - Thông tin app

    private var appInfoGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardGroup(L("App Information")) {
                iconRow

                CardDivider()

                cloneRows

                CardDivider()

                editableFieldRows
            }

            appInfoFootnote
        }
    }

    @ViewBuilder
    private var cloneRows: some View {
        CardToggleRow(icon: "doc.on.doc.fill",
                      title: L("Clone App"),
                      isOn: $isCloneMode)
            .onChange(of: isCloneMode) { newValue in
                if newValue {
                    applyCloneMode()
                } else {
                    removeCloneMode()
                }
            }

        if isCloneMode {
            CardDivider()
            CardRow(icon: "number", title: L("Clone Suffix")) {
                Text(cloneSuffix)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var editableFieldRows: some View {
        SignFieldRow(icon: "textformat",
                     title: L("App Name"),
                     placeholder: "App Name",
                     text: $customName,
                     capitalization: .words,
                     disabled: isCloneMode)

        CardDivider()

        SignFieldRow(icon: "app.badge",
                     title: L("Bundle ID"),
                     placeholder: "Bundle ID",
                     text: $customBundleID,
                     capitalization: .none,
                     disableAutocorrection: true,
                     disabled: isCloneMode)

        CardDivider()

        SignFieldRow(icon: "number.square",
                     title: L("Version"),
                     placeholder: "Version",
                     text: $customVersion)
    }

    private var iconRow: some View {
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

                VStack(alignment: .leading, spacing: 3) {
                    Text("App Icon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    Text(appIcon == nil ? "Tap to customize" : "Custom icon selected")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var appInfoFootnote: some View {
        Group {
            if isCloneMode {
                Text("Clone mode enabled. App name and bundle ID will be automatically modified with suffix '\(cloneSuffix)'")
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("Leave fields as-is to keep original values, or modify to customize")
                    .foregroundStyle(Theme.ink3)
            }
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    // MARK: - Chứng chỉ

    private var certificateGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardGroup(L("Certificate")) {
                if certificates.isEmpty {
                    CardRow(icon: "exclamationmark.triangle.fill",
                            title: L("No certificates available"),
                            iconTint: .orange)
                } else if let cert = selectedCertificate {
                    certificateHeader(cert)
                    CardDivider()
                    certificateStatus(cert)
                } else {
                    Button {
                        showCertificatePicker = true
                    } label: {
                        CardRow(icon: "key.fill", title: L("Select Certificate")) {
                            CardChevron()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if let cert = selectedCertificate, cert.revoked {
                Text("This certificate has been revoked. Signing may fail or the app may not install properly.")
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func certificateHeader(_ cert: CertificatePair) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: Theme.Metric.iconBox, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(cert.nickname ?? L("Certificate"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                if let provision = provision {
                    Text(provision.Name)
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)

                    Text("Team: \(provision.TeamName)")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink3)
                }
            }

            Spacer(minLength: 8)

            Button {
                showCertificatePicker = true
            } label: {
                Text("Change")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 14)
    }

    private func certificateStatus(_ cert: CertificatePair) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "calendar")
                    .foregroundStyle(isExpired ? Color.red : Color.green)
                    .font(.caption)

                if let days = daysUntilExpiration {
                    if isExpired {
                        Text("Expired")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    } else {
                        Text("Expires in \(days) days")
                            .font(.caption)
                            .foregroundStyle(days < 7 ? Color.orange : Color.green)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: cert.ppqCheck ? "checkmark.shield.fill" : "xmark.shield")
                    .foregroundStyle(cert.ppqCheck ? Color.accentColor : Theme.ink3)
                    .font(.caption)

                Text("PPQ Check: \(cert.ppqCheck ? "Enabled" : "Disabled")")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }

            if cert.revoked {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                        .font(.caption)

                    Text("Certificate Revoked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Tweaks

    private var tweaksGroup: some View {
        CardGroup(L("Tweaks"),
                  footnote: L("Manage tweaks inside the app or inject new ones. Disabled tweaks won't be injected when signing.")) {
            NavigationLink {
                AppTweaksManagerView(app: app, disabledTweaks: $sessionDisabledTweaks)
            } label: {
                CardRow(icon: "slider.horizontal.3", title: L("Manage App Tweaks")) {
                    HStack(spacing: 8) {
                        // Show disabled count
                        if !sessionDisabledTweaks.isEmpty {
                            Text("\(sessionDisabledTweaks.count) disabled")
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                        }
                        CardChevron()
                    }
                }
            }
            .buttonStyle(.plain)

            CardDivider()

            // Inject additional external tweaks
            NavigationLink {
                TweakManagementView(injectionFiles: $sessionInjectionFiles)
            } label: {
                CardRow(icon: "syringe", title: L("Inject Additional Tweaks")) {
                    HStack(spacing: 8) {
                        Text("\(sessionInjectionFiles.count)")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                        CardChevron()
                    }
                }
            }
            .buttonStyle(.plain)

            CardDivider()

            CardRow(icon: "arrow.down.to.line", title: L("Inject Path")) {
                Picker("", selection: $quickInjectPath) {
                    ForEach(SigningOptions.injectPathValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            CardDivider()

            CardRow(icon: "folder.badge.gearshape", title: L("Inject Folder")) {
                Picker("", selection: $quickInjectFolder) {
                    ForEach(SigningOptions.injectFolderValues, id: \.self) { value in
                        Text(value == "/" ? "Root" : value).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Tuỳ chọn nhanh

    private var quickSettingsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardGroup(L("Quick Settings")) {
                CardToggleRow(icon: "arrow.down.circle.fill",
                              title: L("Auto Install After Signing"),
                              iconTint: .green,
                              isOn: $autoInstall)
                    .tint(.green)

                CardDivider()

                CardToggleRow(icon: "folder.fill",
                              title: L("File Sharing"),
                              isOn: $quickFileSharing)

                CardDivider()

                CardToggleRow(icon: "gamecontroller.fill",
                              title: L("Game Mode"),
                              isOn: $quickGameMode)

                CardDivider()

                CardToggleRow(icon: "doc.badge.gearshape",
                              title: L("Remove Provision After Signing"),
                              isOn: $quickRemoveProvisionAfterSigning)

                CardDivider()

                Button {
                    showCustomInfoPlistEditor = true
                } label: {
                    CardRow(icon: "doc.text.fill", title: L("Custom Info.plist Entries")) {
                        HStack(spacing: 8) {
                            if !quickCustomInfoPlist.isEmpty {
                                Text("\(quickCustomInfoPlist.count)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink2)
                            }
                            CardChevron()
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            quickSettingsFootnote
        }
    }

    @ViewBuilder
    private var quickSettingsFootnote: some View {
        Group {
            if autoInstall {
                Text("Auto-install is enabled. The app will be installed automatically after signing completes.")
                    .foregroundStyle(Color.green)
            } else {
                Text("These settings apply only to this signing session and won't be saved as defaults")
                    .foregroundStyle(Color.orange)
            }
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    // MARK: - Tuỳ chọn nâng cao

    private var advancedOptionsGroup: some View {
        CardGroup {
            CardNavRow(icon: "signature", title: L("Advanced Signing Options")) {
                SigningOptionsView()
            }
        }
    }

    // MARK: - Tiến trình (là MỘT THẺ trong dòng chảy, không phải lớp phủ)

    private var progressGroup: some View {
        CardGroup(L("Progress")) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)

                    Text(L(signingProgress))
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)

                    Spacer(minLength: 0)
                }

                if signingProgress.contains("Creating IPA") && compressionProgress > 0 {
                    VStack(spacing: 6) {
                        ProgressView(value: compressionProgress)

                        Text("\(Int(compressionProgress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink2)
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 14)
        }
    }

    private var backgroundNoteGroup: some View {
        CardGroup {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)

                Text("App will continue running in background")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Nút ký

    private var signButton: some View {
        FilledButton(title: L("Sign App"), icon: "signature") {
            if selectedCertificate?.revoked == true {
                showRevokedWarning = true
            } else {
                signApp()
            }
        }
        .disabled(selectedCertificate == nil || isSigning)
        .opacity(selectedCertificate == nil || isSigning ? 0.5 : 1)
        .padding(.top, 4)
    }

    // MARK: -

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
        if loggingEnabled { showLogPanel = true }

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

// MARK: - Ô nhập liệu dùng trong màn ký

/// Hàng nhập liệu: nhãn nhỏ phía trên, ô nhập phía dưới, thẳng cột với các hàng khác.
private struct SignFieldRow: View {
    let icon: String
    let title: String
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var capitalization: UITextAutocapitalizationType = .sentences
    var disableAutocorrection: Bool = false
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                .foregroundStyle(disabled ? Theme.ink3 : Color.accentColor)
                .frame(width: Theme.Metric.iconBox, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)

                TextField(placeholder, text: $text)
                    .font(.subheadline)
                    .foregroundStyle(disabled ? Theme.ink3 : Theme.ink)
                    .autocapitalization(capitalization)
                    .autocorrectionDisabled(disableAutocorrection)
                    .disabled(disabled)
            }

            Spacer(minLength: 8)

            if disabled {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Theme.Metric.rowHeight)
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
        let certs = certificates

        return NavigationView {
            Group {
                if certs.isEmpty {
                    EmptyStateView(
                        title: "No Certificates",
                        systemImage: "key.slash",
                        message: "Add a certificate to sign apps"
                    )
                } else {
                    CardScreen {
                        CardGroup {
                            ForEach(certs) { cert in
                                if certs.firstIndex(of: cert) != 0 {
                                    CardDivider()
                                }
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
                    }
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .screenChrome("Select Certificate")
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Theme.ink3)
                .frame(width: Theme.Metric.iconBox, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(certificate.nickname ?? L("Certificate"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    if certificate.isDefault {
                        badge("DEFAULT", tint: Color.accentColor)
                    }

                    if certificate.revoked {
                        badge("REVOKED", tint: Color.red)
                    }
                }

                if let provision = provision {
                    Text(provision.Name)
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)

                    Text("Team: \(provision.TeamName)")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink3)
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
                        .foregroundStyle(isExpired ? Color.red : (days < 7 ? Color.orange : Color.green))
                    }

                    Label {
                        Text("PPQ")
                            .font(.caption2)
                    } icon: {
                        Image(systemName: certificate.ppqCheck ? "checkmark.shield.fill" : "xmark.shield")
                            .font(.caption2)
                    }
                    .foregroundStyle(certificate.ppqCheck ? Color.accentColor : Theme.ink3)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .opacity(certificate.revoked ? 0.7 : 1.0)
    }

    private func badge(_ text: LocalizedStringKey, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.14))
            )
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
            // Giữ List vì có .onDelete (vuốt để xoá) — chỉ thay lớp trang trí.
            List {
                Section {
                    ForEach(Array(entries.keys.sorted()), id: \.self) { key in
                        CardRow(icon: "doc.text",
                                title: key,
                                subtitle: entries[key] ?? "")
                        .listRowInsets(EdgeInsets())
                    }
                    .onDelete { indexSet in
                        let keys = Array(entries.keys.sorted())
                        for index in indexSet {
                            entries.removeValue(forKey: keys[index])
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .screenChrome("Custom Entries")
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
                    CardScreen {
                        CardGroup {
                            SignFieldRow(icon: "textformat",
                                         title: L("Key"),
                                         placeholder: "Key",
                                         text: $newKey,
                                         capitalization: .none)

                            CardDivider()

                            SignFieldRow(icon: "text.alignleft",
                                         title: L("Value"),
                                         placeholder: "Value",
                                         text: $newValue)
                        }
                    }
                    .screenChrome("Add Entry")
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
                    EmptyStateView(
                        title: "No Custom Entries",
                        systemImage: "doc.text",
                        message: "Add custom Info.plist entries for this signing session",
                        style: .compact
                    )
                }
            }
        }
    }
}
