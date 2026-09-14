//
//  SettingsView.swift
//  zsignapp
//  FIXED: Storage moved to separate view for better performance

import SwiftUI
import Zip

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var showResetAlert = false
    @State private var certificates: [CertificatePair] = []
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - UDID (trên cùng) — chạm để copy
                Section {
                    UDIDRow()
                    DeviceInfoRow()
                }

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

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Text("Appearance")
                    }
                } header: {
                    Text("Management")
                } footer: {
                    Text("Manage certificates and configure advanced signing options")
                        .font(.caption)
                }

                // MARK: - Nâng cao (Advanced)
                Section {
                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        Text("Advanced")
                    }
                } footer: {
                    Text("Workspace (keeps the source IPA + tweaks and updates over the installed build) and background processing.")
                        .font(.caption)
                }
                
               
                
                // MARK: - Storage Section (NavigationLink to separate view)
                Section {
                    NavigationLink {
                        StorageManagementView()
                    } label: {
                        Label("Storage & Cleanup", systemImage: "externaldrive")
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Manage app storage, view usage statistics, and clean up files")
                        .font(.caption)
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
            .onAppear {
                loadCertificates()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CertificatesDidChange"))) { _ in
                loadCertificates()
            }
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
        }
        .navigationViewStyle(.stack) // FIX: Force stack style cho iPad
    }
    
    // MARK: - Load Certificates
    private func loadCertificates() {
        certificates = Storage.shared.fetchCertificates()
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Advanced Settings (Nâng cao)

struct AdvancedSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @AppStorage("zsign.workspaceEnabled") private var workspaceEnabled = false
    @AppStorage("zsign.loggingEnabled") private var loggingEnabled = false
    @State private var showBackgroundInfoAlert = false
    
    var body: some View {
        Form {
            // MARK: - Workspace
            Section {
                Toggle(isOn: $workspaceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Updates (Workspace)")
                        Text("Save apps as projects · edit tweaks · re-sign and install over")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                if workspaceEnabled {
                    NavigationLink {
                        ProjectsListView()
                    } label: {
                        Text("Projects")
                    }
                }
            } header: {
                Text("Workspace")
            } footer: {
                Text("Keeps the source IPA + tweaks, re-signs and updates over the installed build.")
                    .font(.caption)
            }
            
            // MARK: - Nhật ký (Logging)
            Section {
                Toggle(isOn: $loggingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signing Log")
                        Text("Records the signing process for debugging · shows a realtime log while signing")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                if loggingEnabled {
                    NavigationLink {
                        SignLogViewerView()
                    } label: {
                        Text("View latest log")
                    }
                }
            } header: {
                Text("Log")
            } footer: {
                Text("When enabled, the signing screen shows a realtime log panel (can be hidden). Plain text, no emoji.")
                    .font(.caption)
            }
            
            // MARK: - Background Processing
            Section {
                Toggle(isOn: $settings.backgroundAudioEnabled) {
                    HStack {
                        Text("Keep App Active")
                        
                        Button {
                            showBackgroundInfoAlert = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.accentColor)
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
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Auto Sign Section (Simplified - Bỏ certificate info)

struct AutoSignSection: View {
    @ObservedObject var settings: AppSettings
    var certificates: [CertificatePair]
    
    private var hasAnyCertificate: Bool {
        !certificates.isEmpty
    }
    
    private var hasDefaultCertificate: Bool {
        certificates.contains(where: { $0.isDefault })
    }
    
    var body: some View {
        Section {
            Toggle(isOn: $settings.autoSignAfterDownload) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Auto Sign & Install", systemImage: "signature")
                    Text("After Download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!hasDefaultCertificate)
            
            // Chỉ hiện warning khi cần thiết
            if !hasAnyCertificate {
                noCertificateWarning()
            } else if !hasDefaultCertificate {
                noDefaultCertWarning()
            }
            
        } header: {
            Text("AUTO SIGN & INSTALL")
        } footer: {
            footerText()
        }
    }
    
    // MARK: - Warning Views
    
    @ViewBuilder
    private func noDefaultCertWarning() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.subheadline)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No default certificate set")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                NavigationLink(destination: CertificatesManagementView()) {
                    Text("Set default certificate →")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func noCertificateWarning() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.subheadline)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No certificates available")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                NavigationLink(destination: CertificatesManagementView()) {
                    Text("Add certificate →")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func footerText() -> some View {
        if !hasAnyCertificate {
            Text("Add a certificate first to enable auto signing. Go to Management → Certificates.")
                .font(.caption)
                .foregroundColor(.red)
        } else if !hasDefaultCertificate {
            Text("Set a default certificate in Certificates Management to enable this feature.")
                .font(.caption)
                .foregroundColor(.orange)
        } else if settings.autoSignAfterDownload {
            Text("Apps downloaded from Store will be automatically signed with your default certificate and installed. You'll receive notifications for each step.")
                .font(.caption)
                .foregroundColor(.accentColor)
        } else {
            Text("Enable to automatically sign and install downloaded apps using your default certificate. Works with apps from Store (Sources).")
                .font(.caption)
        }
    }
}
