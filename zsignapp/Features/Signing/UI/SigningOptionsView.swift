//
//  SigningOptionsView.swift
//  zsignapp
//
//  Advanced signing options
//
//  Giao diện dạng thẻ (Theme + CardComponents). Mọi tuỳ chọn, mọi điểm gọi
//  optionsManager.saveOptions() giữ nguyên như bản Form cũ.
//

import SwiftUI

struct SigningOptionsView: View {
    @StateObject private var optionsManager = SigningOptionsManager.shared
    @StateObject private var settings = AppSettings.shared
    @State private var certificates: [CertificatePair] = []
    @State private var showResetAlert = false

    var body: some View {
        CardScreen {
            // MARK: - Auto Sign & Install (chuyển từ Cài đặt)
            autoSignGroup

            // MARK: - IPA Compression (chuyển từ Cài đặt)
            compressionGroup

            // MARK: - Appearance & Requirements
            appearanceGroup

            // MARK: - Features
            featuresGroup

            // MARK: - Removal Options
            cleanupGroup

            // MARK: - Advanced Protection
            protectionGroup

            Group {
                // MARK: - Custom File Removal
                removeFilesGroup

                // MARK: - Injection Settings
                injectionGroup

                // MARK: - Experimental Features
                experimentalGroup

                // MARK: - Custom Info.plist Entries
                infoPlistGroup

                // MARK: - Reset
                resetButton
            }
        }
        .screenChrome("Signing Options")
        .alert("Reset Options?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                optionsManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all signing options to their default values.")
        }
        .onChange(of: optionsManager.options) { _ in
            optionsManager.saveOptions()
        }
        .onAppear {
            certificates = Storage.shared.fetchCertificates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CertificatesDidChange"))) { _ in
            certificates = Storage.shared.fetchCertificates()
        }
    }

    // MARK: - Tự động ký & cài

    private var hasAnyCertificate: Bool {
        !certificates.isEmpty
    }

    private var hasDefaultCertificate: Bool {
        certificates.contains(where: { $0.isDefault })
    }

    private var autoSignGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardGroup {
                CardToggleRow(
                    icon: "signature",
                    title: L("Auto Sign & Install"),
                    subtitle: L("After Download"),
                    isOn: $settings.autoSignAfterDownload
                )
                .disabled(!hasDefaultCertificate)
                .opacity(hasDefaultCertificate ? 1 : 0.5)

                // Chỉ hiện cảnh báo khi cần thiết
                if !hasAnyCertificate {
                    CardDivider()
                    noCertificateWarning
                } else if !hasDefaultCertificate {
                    CardDivider()
                    noDefaultCertWarning
                }
            }

            autoSignFootnote
        }
    }

    private var noDefaultCertWarning: some View {
        NavigationLink {
            CertificatesManagementView()
        } label: {
            CardRow(icon: "exclamationmark.triangle.fill",
                    title: L("No default certificate set"),
                    subtitle: L("Set default certificate →"),
                    iconTint: .orange) {
                CardChevron()
            }
        }
        .buttonStyle(.plain)
    }

    private var noCertificateWarning: some View {
        NavigationLink {
            CertificatesManagementView()
        } label: {
            CardRow(icon: "exclamationmark.triangle.fill",
                    title: L("No certificates available"),
                    subtitle: L("Add certificate →"),
                    iconTint: .red) {
                CardChevron()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var autoSignFootnote: some View {
        Group {
            if !hasAnyCertificate {
                Text("Add a certificate first to enable auto signing. Go to Management → Certificates.")
                    .foregroundStyle(.red)
            } else if !hasDefaultCertificate {
                Text("Set a default certificate in Certificates Management to enable this feature.")
                    .foregroundStyle(.orange)
            } else if settings.autoSignAfterDownload {
                Text("Apps downloaded from Store will be automatically signed with your default certificate and installed. You'll receive notifications for each step.")
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("Enable to automatically sign and install downloaded apps using your default certificate. Works with apps from Store (Sources).")
                    .foregroundStyle(Theme.ink3)
            }
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    // MARK: - Nén IPA (chuyển từ SettingsView)

    private var compressionGroup: some View {
        CardGroup(L("IPA Compression"),
                  footnote: L("Choose compression level for IPA creation. For large apps (2-5GB), 'Speed' or 'Default' is recommended.")) {
            CardRow(icon: "archivebox.fill", title: L("Compression Level")) {
                Picker("", selection: $settings.compressionLevel) {
                    ForEach([
                        (0, "None", CompressionLevel.NoCompression),
                        (1, "Speed", CompressionLevel.BestSpeed),
                        (2, "Default", CompressionLevel.DefaultCompression),
                        (3, "Best", CompressionLevel.BestCompression)
                    ], id: \.0) { value, label, _ in
                        Text(L(label)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            CardDivider()

            HStack(spacing: 12) {
                Image(systemName: settings.compressionType.icon)
                    .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                    .foregroundStyle(colorForCompression(settings.compressionType))
                    .frame(width: Theme.Metric.iconBox, alignment: .center)

                Text(L(settings.compressionType.description))
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Hiển thị & yêu cầu

    private var appearanceGroup: some View {
        CardGroup(L("Display & Requirements")) {
            CardRow(icon: "paintbrush.fill", title: L("App Appearance")) {
                Picker("", selection: $optionsManager.options.appAppearance) {
                    ForEach(SigningOptions.appAppearanceValues, id: \.self) { value in
                        Text(L(value)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            CardDivider()

            CardRow(icon: "iphone", title: L("Minimum iOS")) {
                Picker("", selection: $optionsManager.options.minimumAppRequirement) {
                    ForEach(SigningOptions.appMinimumAppRequirementValues, id: \.self) { value in
                        Text(L(value)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Tính năng

    private var featuresGroup: some View {
        CardGroup(L("Features"),
                  footnote: L("Enable additional features for the signed app")) {
            CardToggleRow(icon: "folder.fill",
                          title: L("File Sharing"),
                          isOn: $optionsManager.options.fileSharing)
            CardDivider()
            CardToggleRow(icon: "arrow.up.arrow.down.circle.fill",
                          title: L("iTunes File Sharing"),
                          isOn: $optionsManager.options.itunesFileSharing)
            CardDivider()
            CardToggleRow(icon: "speedometer",
                          title: L("ProMotion (120Hz)"),
                          isOn: $optionsManager.options.proMotion)
            CardDivider()
            CardToggleRow(icon: "gamecontroller.fill",
                          title: L("Game Mode"),
                          isOn: $optionsManager.options.gameMode)
            CardDivider()
            CardToggleRow(icon: "ipad.landscape",
                          title: L("iPad Fullscreen"),
                          isOn: $optionsManager.options.ipadFullscreen)
        }
    }

    // MARK: - Dọn dẹp

    private var cleanupGroup: some View {
        CardGroup(L("Cleanup"),
                  footnote: L("Remove unnecessary components from the app")) {
            CardToggleRow(icon: "iphone.slash",
                          title: L("Remove Supported Devices"),
                          isOn: $optionsManager.options.removeSupportedDevices)
            CardDivider()
            CardToggleRow(icon: "link",
                          title: L("Remove URL Scheme"),
                          isOn: $optionsManager.options.removeURLScheme)
            CardDivider()
            CardToggleRow(icon: "doc.badge.gearshape",
                          title: L("Remove Provisioning"),
                          isOn: $optionsManager.options.removeProvisioning)
            CardDivider()
            CardToggleRow(icon: "applewatch",
                          title: L("Remove Watch Placeholder"),
                          isOn: $optionsManager.options.removeWatchPlaceholder)
        }
    }

    // MARK: - Bảo vệ

    private var protectionGroup: some View {
        CardGroup(L("Protection"),
                  footnote: L("Enable advanced anti-detection features")) {
            CardToggleRow(icon: "lock.shield.fill",
                          title: L("PPQ Protection"),
                          isOn: $optionsManager.options.ppqProtection)

            if optionsManager.options.ppqProtection {
                CardDivider()
                CardRow(icon: "number", title: L("PPQ String")) {
                    HStack(spacing: 10) {
                        Text(optionsManager.options.ppqString)
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            optionsManager.options.ppqString = SigningOptions.randomString()
                            optionsManager.saveOptions()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            CardDivider()

            CardToggleRow(icon: "bolt.shield.fill",
                          title: L("Dynamic Protection"),
                          isOn: $optionsManager.options.dynamicProtection)
        }
    }

    // MARK: - Xoá file tuỳ chọn

    private var removeFilesGroup: some View {
        CardGroup(L("Custom File Removal"),
                  footnote: L("Specify additional files to remove from the app bundle")) {
            NavigationLink {
                RemoveFilesView()
            } label: {
                CardRow(icon: "trash.fill",
                        title: L("Files to Remove"),
                        iconTint: .red) {
                    HStack(spacing: 8) {
                        if !optionsManager.options.removeFiles.isEmpty {
                            Text("\(optionsManager.options.removeFiles.count)")
                                .font(.caption)
                                .foregroundStyle(Theme.ink2)
                        }
                        CardChevron()
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tiêm dylib

    private var injectionGroup: some View {
        CardGroup(L("Injection"),
                  footnote: L("Configure dylib injection paths")) {
            CardRow(icon: "syringe", title: L("Inject Path")) {
                Picker("", selection: $optionsManager.options.injectPath) {
                    ForEach(SigningOptions.injectPathValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            CardDivider()

            CardRow(icon: "folder.badge.gearshape", title: L("Inject Folder")) {
                Picker("", selection: $optionsManager.options.injectFolder) {
                    ForEach(SigningOptions.injectFolderValues, id: \.self) { value in
                        Text(value == "/" ? "Root" : value).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Thử nghiệm

    private var experimentalGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardGroup(L("Experimental")) {
                CardToggleRow(icon: "drop.fill",
                              title: L("Support Liquid Glass"),
                              isOn: $optionsManager.options.experiment_supportLiquidGlass)
                CardDivider()
                CardToggleRow(icon: "arrow.triangle.2.circlepath",
                              title: L("Replace Substrate with ElleKit"),
                              isOn: $optionsManager.options.experiment_replaceSubstrateWithEllekit)
            }

            Text("These features are experimental and may cause issues")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Info.plist

    private var infoPlistGroup: some View {
        CardGroup(L("Info.plist")) {
            NavigationLink {
                CustomInfoPlistView()
            } label: {
                CardRow(icon: "doc.text.fill", title: L("Custom Entries")) {
                    HStack(spacing: 8) {
                        if !optionsManager.options.customInfoPlistEntries.isEmpty {
                            Text("\(optionsManager.options.customInfoPlistEntries.count)")
                                .font(.caption)
                                .foregroundStyle(Theme.ink2)
                        }
                        CardChevron()
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Đặt lại

    private var resetButton: some View {
        FilledButton(title: L("Reset to Defaults"),
                     icon: "arrow.counterclockwise",
                     role: .destructive) {
            showResetAlert = true
        }
        .padding(.top, 4)
    }

    private func colorForCompression(_ level: CompressionLevel) -> Color {
        switch level.color {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .accentColor
        }
    }
}

// MARK: - Ô nhập trong các sheet "thêm mới"

/// Hàng nhập liệu dùng trong sheet Add Entry / Add File của màn này.
private struct SigningOptionsFieldRow: View {
    let icon: String
    let title: String
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var capitalization: UITextAutocapitalizationType = .sentences
    var disableAutocorrection: Bool = false
    var monospaced: Bool = false

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

                TextField(placeholder, text: $text)
                    .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                    .foregroundStyle(Theme.ink)
                    .autocapitalization(capitalization)
                    .autocorrectionDisabled(disableAutocorrection)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Theme.Metric.rowHeight)
    }
}

// MARK: - Custom Info.plist View
struct CustomInfoPlistView: View {
    @StateObject private var optionsManager = SigningOptionsManager.shared
    @State private var showAddEntry = false
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        // Giữ List vì có .onDelete (vuốt để xoá) — chỉ thay lớp trang trí.
        List {
            Section {
                ForEach(Array(optionsManager.options.customInfoPlistEntries.keys.sorted()), id: \.self) { key in
                    CardRow(icon: "doc.text",
                            title: key,
                            subtitle: optionsManager.options.customInfoPlistEntries[key] ?? "")
                    .listRowInsets(EdgeInsets())
                }
                .onDelete { indexSet in
                    let keys = Array(optionsManager.options.customInfoPlistEntries.keys.sorted())
                    for index in indexSet {
                        optionsManager.options.customInfoPlistEntries.removeValue(forKey: keys[index])
                    }
                    optionsManager.saveOptions()
                }
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .screenChrome("Custom Entries")
        .navigationBarItems(trailing: Button(action: {
            showAddEntry = true
        }) {
            Image(systemName: "plus")
        })
        .sheet(isPresented: $showAddEntry) {
            NavigationView {
                CardScreen {
                    CardGroup {
                        SigningOptionsFieldRow(icon: "textformat",
                                               title: L("Key"),
                                               placeholder: "Key",
                                               text: $newKey,
                                               capitalization: .none)
                        CardDivider()
                        SigningOptionsFieldRow(icon: "text.alignleft",
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
                        optionsManager.options.customInfoPlistEntries[newKey] = newValue
                        optionsManager.saveOptions()
                        showAddEntry = false
                        newKey = ""
                        newValue = ""
                    }
                    .disabled(newKey.isEmpty || newValue.isEmpty)
                )
            }
        }
        .overlay {
            if optionsManager.options.customInfoPlistEntries.isEmpty {
                EmptyStateView(
                    title: "No Custom Entries",
                    systemImage: "doc.text",
                    message: "Add custom Info.plist entries",
                    style: .compact
                )
            }
        }
    }
}

// MARK: - Remove Files View
struct RemoveFilesView: View {
    @StateObject private var optionsManager = SigningOptionsManager.shared
    @State private var showAddFile = false
    @State private var newFilePath = ""

    var body: some View {
        // Giữ List vì có .onDelete (vuốt để xoá) — chỉ thay lớp trang trí.
        List {
            Section {
                ForEach(optionsManager.options.removeFiles, id: \.self) { file in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                            .foregroundStyle(Theme.ink3)
                            .frame(width: Theme.Metric.iconBox, alignment: .center)

                        Text(file)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Theme.ink)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, Theme.Metric.cardPadding)
                    .padding(.vertical, 12)
                    .listRowInsets(EdgeInsets())
                }
                .onDelete { indexSet in
                    optionsManager.options.removeFiles.remove(atOffsets: indexSet)
                    optionsManager.saveOptions()
                }
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .screenChrome("Remove Files")
        .navigationBarItems(trailing: Button(action: {
            showAddFile = true
        }) {
            Image(systemName: "plus")
        })
        .sheet(isPresented: $showAddFile) {
            NavigationView {
                CardScreen {
                    CardGroup(footnote: L("Example: PlugIns/Widget.appex")) {
                        SigningOptionsFieldRow(icon: "folder.fill",
                                               title: L("File Path"),
                                               placeholder: "File Path",
                                               text: $newFilePath,
                                               capitalization: .none,
                                               disableAutocorrection: true,
                                               monospaced: true)
                    }
                }
                .screenChrome("Add File")
                .navigationBarItems(
                    leading: Button("Cancel") {
                        showAddFile = false
                        newFilePath = ""
                    },
                    trailing: Button("Add") {
                        optionsManager.options.removeFiles.append(newFilePath)
                        optionsManager.saveOptions()
                        showAddFile = false
                        newFilePath = ""
                    }
                    .disabled(newFilePath.isEmpty)
                )
            }
        }
        .overlay {
            if optionsManager.options.removeFiles.isEmpty {
                EmptyStateView(
                    title: "No Files to Remove",
                    systemImage: "trash",
                    message: "Add file paths to remove from app bundle",
                    style: .compact
                )
            }
        }
    }
}
