//
//  SettingsView.swift
//  zsignapp
//  FIXED: Use Zip library instead of SwiftMiniZip

import SwiftUI
import Zip  // ← Đổi từ SwiftMiniZip sang Zip

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var showResetAlert = false
    @State private var showBackgroundInfoAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Management Section
                Section {
                    NavigationLink {
                        CertificatesManagementView()
                    } label: {
                        Text("Certificates")
                    }
                    
                    NavigationLink {
                        SigningOptionsView()
                    } label: {
                        Text("Signing Options")
                    }
                } header: {
                    Text("Management")
                } footer: {
                    Text("Manage certificates and configure advanced signing options")
                        .font(.caption)
                }
                
                // MARK: - IPA Compression Section
                compressionSection
                
                // MARK: - Background Processing Section
                backgroundSection
                
                // MARK: - General Section
                Section {
                    Toggle(isOn: $settings.autoCleanTemp) {
                        Text("Auto Clean Temp Files")
                    }
                    
                    Toggle(isOn: $settings.showDebugLog) {
                        Text("Show Debug Logs")
                    }
                } header: {
                    Text("General")
                } footer: {
                    Text("Automatically clean temporary files after operations complete. Enable debug logs to see detailed information in console.")
                        .font(.caption)
                }
                
                // MARK: - Storage Info Section
                Section {
                    StorageInfoRow()
                } header: {
                    Text("Storage")
                }
                
                // MARK: - About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(appBuild)
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://t.me/zsignapp")!) {
                        HStack {
                            Text("Support & Feedback")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } header: {
                    Text("About")
                } footer: {
                    Text("Report bugs or suggestions at Zsign.app Telegram Channel")
                        .font(.caption)
                }
                
                // MARK: - Open Source Packages Section
                Section {
                    Link(destination: URL(string: "https://github.com/khcrysalis/Zsign-Package.git")!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Zsign")
                                    .font(.body)
                                Text("by khcrysalis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://github.com/khcrysalis/Feather/tree/main/AltSourceKit")!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AltSourceKit")
                                    .font(.body)
                                Text("by khcrysalis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // ✅ CẬP NHẬT: Thay SwiftMiniZip bằng Zip
                    Link(destination: URL(string: "https://github.com/marmelroy/Zip")!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Zip")
                                    .font(.body)
                                Text("by marmelroy")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } header: {
                    Text("Open Source Packages")
                } footer: {
                    Text("This app uses open source packages. Tap to view on GitHub.")
                        .font(.caption)
                }
                
                // MARK: - Reset Section
                Section {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset to Defaults")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Reset all settings to default values")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Settings?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    withAnimation {
                        settings.resetToDefaults()
                    }
                }
            } message: {
                Text("This will reset all settings to their default values.")
            }
            .alert("Background Mode", isPresented: $showBackgroundInfoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("""
                When enabled, the app plays silent audio to prevent iOS from suspending it during long operations.
                
                This is especially useful when:
                • Installing large apps (2GB+)
                • Signing multiple apps
                • Slow network connections
                
                The app will continue working even when the screen is locked or you switch to another app.
                """)
            }
        }
    }
    
    // MARK: - Compression Section
    
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
            
            // ✅ Hiển thị description từ CompressionLevel
            HStack(spacing: 8) {
                Image(systemName: settings.compressionType.icon)
                    .foregroundColor(colorForCompression(settings.compressionType))
                
                Text(settings.compressionType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            
        } header: {
            Text("IPA Compression")
        } footer: {
            Text("Choose compression level for IPA creation. For large apps (2-5GB), 'Speed' or 'Default' is recommended for best balance between size and time.")
                .font(.caption)
        }
    }
    
    private func colorForCompression(_ level: CompressionLevel) -> Color {
        switch level.color {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .blue
        }
    }
    
    // MARK: - Background Section
    
    @ViewBuilder
    private var backgroundSection: some View {
        Section {
            Toggle(isOn: $settings.backgroundAudioEnabled) {
                HStack {
                    Text("Keep App Active")
                    
                    Button {
                        showBackgroundInfoAlert = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if settings.backgroundAudioEnabled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Background mode active")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    if BackgroundAudioManager.shared.isAudioPlaying {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 4)
            }
            
        } header: {
            Text("Background Processing")
        } footer: {
            Text("Prevents iOS from killing the app during large file transfers. Recommended for installing apps larger than 2GB.")
                .font(.caption)
        }
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Storage Info Row

struct StorageInfoRow: View {
    @State private var storageInfo: StorageInfo?
    
    var body: some View {
        VStack(spacing: 12) {
            if let info = storageInfo {
                StorageBar(used: info.usedSpace, total: info.totalSpace)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Used")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(info.usedSpaceFormatted)
                            .font(.caption)
                            .bold()
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(info.availableSpaceFormatted)
                            .font(.caption)
                            .bold()
                    }
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Calculating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            calculateStorage()
        }
    }
    
    private func calculateStorage() {
        Task {
            let info = StorageCalculator.getStorageInfo()
            await MainActor.run {
                self.storageInfo = info
            }
        }
    }
}

struct StorageBar: View {
    let used: Int64
    let total: Int64
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: percentage > 0.9 ? [.red, .orange] : [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * percentage)
            }
        }
        .frame(height: 8)
    }
}

struct StorageInfo {
    let usedSpace: Int64
    let availableSpace: Int64
    let totalSpace: Int64
    
    var usedSpaceFormatted: String {
        ByteCountFormatter.string(fromByteCount: usedSpace, countStyle: .file)
    }
    
    var availableSpaceFormatted: String {
        ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
    }
    
    var totalSpaceFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file)
    }
}

struct StorageCalculator {
    static func getStorageInfo() -> StorageInfo {
        let fileManager = FileManager.default
        let documentsURL = fileManager.documentsDirectory
        let usedSpace = calculateDirectorySize(at: documentsURL)
        
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            let freeSpace = (systemAttributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let totalSpace = usedSpace + freeSpace
            
            return StorageInfo(
                usedSpace: usedSpace,
                availableSpace: freeSpace,
                totalSpace: totalSpace
            )
        } catch {
            return StorageInfo(usedSpace: usedSpace, availableSpace: 0, totalSpace: usedSpace)
        }
    }
    
    static func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            } catch {
                continue
            }
        }
        
        return totalSize
    }
}
