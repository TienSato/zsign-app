//
//  SigningOptionsView.swift
//  zsignapp
//
//  Advanced signing options
//

import SwiftUI

struct SigningOptionsView: View {
    @StateObject private var optionsManager = SigningOptionsManager.shared
    @StateObject private var settings = AppSettings.shared
    @State private var certificates: [CertificatePair] = []
    @State private var showResetAlert = false
    
    var body: some View {
        Form {
            // MARK: - Auto Sign & Install (chuyển từ Cài đặt)
            AutoSignSection(
                settings: settings,
                certificates: certificates
            )

            // MARK: - IPA Compression (chuyển từ Cài đặt)
            compressionSection

            // MARK: - Appearance & Requirements
            Section {
                Picker("App Appearance", selection: $optionsManager.options.appAppearance) {
                    ForEach(SigningOptions.appAppearanceValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                
                Picker("Minimum iOS", selection: $optionsManager.options.minimumAppRequirement) {
                    ForEach(SigningOptions.appMinimumAppRequirementValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
            } header: {
                Label("Display & Requirements", systemImage: "paintbrush")
            }
            
            // MARK: - Features
            Section {
                Toggle("File Sharing", isOn: $optionsManager.options.fileSharing)
                Toggle("iTunes File Sharing", isOn: $optionsManager.options.itunesFileSharing)
                Toggle("ProMotion (120Hz)", isOn: $optionsManager.options.proMotion)
                Toggle("Game Mode", isOn: $optionsManager.options.gameMode)
                Toggle("iPad Fullscreen", isOn: $optionsManager.options.ipadFullscreen)
            } header: {
                Label("Features", systemImage: "flask")
            } footer: {
                Text("Enable additional features for the signed app")
                    .font(.caption)
            }
            
            // MARK: - Removal Options
            Section {
                Toggle("Remove Supported Devices", isOn: $optionsManager.options.removeSupportedDevices)
                Toggle("Remove URL Scheme", isOn: $optionsManager.options.removeURLScheme)
                Toggle("Remove Provisioning", isOn: $optionsManager.options.removeProvisioning)
                Toggle("Remove Watch Placeholder", isOn: $optionsManager.options.removeWatchPlaceholder)
            } header: {
                Label("Cleanup", systemImage: "trash")
            } footer: {
                Text("Remove unnecessary components from the app")
                    .font(.caption)
            }
            
            // MARK: - Advanced Protection
            Section {
                Toggle("PPQ Protection", isOn: $optionsManager.options.ppqProtection)
                
                if optionsManager.options.ppqProtection {
                    HStack {
                        Text("PPQ String")
                        Spacer()
                        Text(optionsManager.options.ppqString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            optionsManager.options.ppqString = SigningOptions.randomString()
                            optionsManager.saveOptions()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                }
                
                Toggle("Dynamic Protection", isOn: $optionsManager.options.dynamicProtection)
            } header: {
                Label("Protection", systemImage: "lock.shield")
            } footer: {
                Text("Enable advanced anti-detection features")
                    .font(.caption)
            }
            
            // Thêm section này vào SigningOptionsView
            Section {
                NavigationLink {
                    RemoveFilesView()
                } label: {
                    HStack {
                        Text("Files to Remove")
                        Spacer()
                        if !optionsManager.options.removeFiles.isEmpty {
                            Text("\(optionsManager.options.removeFiles.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Label("Custom File Removal", systemImage: "trash.fill")
            } footer: {
                Text("Specify additional files to remove from the app bundle")
                    .font(.caption)
            }
            // MARK: - Injection Settings
            Section {
                Picker("Inject Path", selection: $optionsManager.options.injectPath) {
                    ForEach(SigningOptions.injectPathValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                
                Picker("Inject Folder", selection: $optionsManager.options.injectFolder) {
                    ForEach(SigningOptions.injectFolderValues, id: \.self) { value in
                        Text(value == "/" ? "Root" : value).tag(value)
                    }
                }
            } header: {
                Label("Injection", systemImage: "syringe")
            } footer: {
                Text("Configure dylib injection paths")
                    .font(.caption)
            }
            
            // MARK: - Experimental Features
            Section {
                Toggle("Support Liquid Glass", isOn: $optionsManager.options.experiment_supportLiquidGlass)
                Toggle("Replace Substrate with ElleKit", isOn: $optionsManager.options.experiment_replaceSubstrateWithEllekit)
            } header: {
                Label("Experimental", systemImage: "flask")
            } footer: {
                Text("These features are experimental and may cause issues")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            // MARK: - Custom Info.plist Entries
            Section {
                NavigationLink {
                    CustomInfoPlistView()
                } label: {
                    HStack {
                        Text("Custom Entries")
                        Spacer()
                        if !optionsManager.options.customInfoPlistEntries.isEmpty {
                            Text("\(optionsManager.options.customInfoPlistEntries.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Label("Info.plist", systemImage: "doc.text")
            }
            
            // MARK: - Reset
            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Signing Options")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Compression Section (chuyển từ SettingsView)
    @ViewBuilder
    private var compressionSection: some View {
        Section {
            Picker("Compression Level", selection: $settings.compressionLevel) {
                ForEach([
                    (0, "None", CompressionLevel.NoCompression),
                    (1, "Speed", CompressionLevel.BestSpeed),
                    (2, "Default", CompressionLevel.DefaultCompression),
                    (3, "Best", CompressionLevel.BestCompression)
                ], id: \.0) { value, label, _ in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Image(systemName: settings.compressionType.icon)
                    .foregroundColor(colorForCompression(settings.compressionType))
                Text(settings.compressionType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Label("IPA Compression", systemImage: "archivebox")
        } footer: {
            Text("Choose compression level for IPA creation. For large apps (2-5GB), 'Speed' or 'Default' is recommended.")
                .font(.caption)
        }
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

// MARK: - Custom Info.plist View
struct CustomInfoPlistView: View {
    @StateObject private var optionsManager = SigningOptionsManager.shared
    @State private var showAddEntry = false
    @State private var newKey = ""
    @State private var newValue = ""
    
    var body: some View {
        List {
            ForEach(Array(optionsManager.options.customInfoPlistEntries.keys.sorted()), id: \.self) { key in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key)
                            .font(.headline)
                        Text(optionsManager.options.customInfoPlistEntries[key] ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .onDelete { indexSet in
                let keys = Array(optionsManager.options.customInfoPlistEntries.keys.sorted())
                for index in indexSet {
                    optionsManager.options.customInfoPlistEntries.removeValue(forKey: keys[index])
                }
                optionsManager.saveOptions()
            }
        }
        .navigationTitle("Custom Entries")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: Button(action: {
            showAddEntry = true
        }) {
            Image(systemName: "plus")
        })
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
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No Custom Entries")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Add custom Info.plist entries")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
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
        List {
            ForEach(optionsManager.options.removeFiles, id: \.self) { file in
                Text(file)
                    .font(.system(.body, design: .monospaced))
            }
            .onDelete { indexSet in
                optionsManager.options.removeFiles.remove(atOffsets: indexSet)
                optionsManager.saveOptions()
            }
        }
        .navigationTitle("Remove Files")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: Button(action: {
            showAddFile = true
        }) {
            Image(systemName: "plus")
        })
        .sheet(isPresented: $showAddFile) {
            NavigationView {
                Form {
                    Section {
                        TextField("File Path", text: $newFilePath)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } header: {
                        Text("File Path")
                    } footer: {
                        Text("Example: PlugIns/Widget.appex")
                            .font(.caption)
                    }
                }
                .navigationTitle("Add File")
                .navigationBarTitleDisplayMode(.inline)
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
                VStack(spacing: 16) {
                    Image(systemName: "trash")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No Files to Remove")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Add file paths to remove from app bundle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}
