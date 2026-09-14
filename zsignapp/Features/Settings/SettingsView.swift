//
//  SettingsView.swift
//  zsignapp
//
//  Màn hình Cài đặt — dựng bằng bộ thẻ dùng chung (Theme + CardComponents)
//  thay cho Form, để nền và thẻ theo đúng tông của app thay vì tông mặc định
//  của hệ thống.
//

import SwiftUI
import Zip

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var showResetAlert = false
    @State private var certificates: [CertificatePair] = []

    var body: some View {
        NavigationStack {
            CardScreen {
                deviceCard
                managementGroup
                systemGroup
                aboutGroup
                resetButton
            }
            .screenChrome("Settings")
            .onAppear(perform: loadCertificates)
            .onReceive(NotificationCenter.default.publisher(
                for: NSNotification.Name("CertificatesDidChange"))) { _ in
                loadCertificates()
            }
            .alert("Reset Settings?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    withAnimation { settings.resetToDefaults() }
                }
            } message: {
                Text("This will reset all settings to their default values.")
            }
        }
    }

    // MARK: - Thiết bị

    private var deviceCard: some View {
        CardGroup {
            UDIDRow()
            CardDivider()
            DeviceInfoRow()
        }
    }

    // MARK: - Quản lý

    private var managementGroup: some View {
        CardGroup(L("Management"),
                  footnote: L("Manage certificates and configure advanced signing options")) {
            CardNavRow(icon: "key.fill",
                       title: L("Certificates"),
                       subtitle: certificateSummary) {
                CertificatesManagementView()
            }
            CardDivider()
            CardNavRow(icon: "slider.horizontal.3",
                       title: L("Signing Options"),
                       subtitle: L("Name, bundle ID, entitlements and tweaks")) {
                SigningOptionsView()
            }
            CardDivider()
            CardNavRow(icon: "paintpalette.fill",
                       title: L("Appearance"),
                       subtitle: L("Accent color, app icon and language")) {
                AppearanceSettingsView()
            }
        }
    }

    private var certificateSummary: String {
        if certificates.isEmpty { return L("No certificates yet") }
        let valid = certificates.filter { !$0.revoked }.count
        return "\(valid)/\(certificates.count) " + L("usable")
    }

    // MARK: - Hệ thống

    private var systemGroup: some View {
        CardGroup(L("System")) {
            CardNavRow(icon: "gearshape.2.fill",
                       title: L("Advanced"),
                       subtitle: L("Workspace, signing log and background processing")) {
                AdvancedSettingsView()
            }
            CardDivider()
            CardNavRow(icon: "externaldrive.fill",
                       title: L("Storage & Cleanup"),
                       subtitle: L("Usage breakdown and cleanup tools")) {
                StorageManagementView()
            }
        }
    }

    // MARK: - Giới thiệu

    private var aboutGroup: some View {
        CardGroup(L("About"),
                  footnote: L("Report bugs or suggestions at Zsign.app Telegram Channel")) {
            CardValueRow(icon: "number", title: L("Version"), value: appVersion)
            CardDivider()
            CardValueRow(icon: "hammer.fill", title: L("Build"), value: appBuild)
            CardDivider()
            Link(destination: URL(string: "https://t.me/zsignapp")!) {
                CardRow(icon: "paperplane.fill",
                        title: L("Support & Feedback"),
                        subtitle: "t.me/zsignapp") {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Đặt lại

    private var resetButton: some View {
        VStack(spacing: 8) {
            FilledButton(title: L("Reset to Defaults"),
                         icon: "arrow.counterclockwise",
                         role: .destructive) {
                showResetAlert = true
            }
            Text("Reset all settings to default values")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
        }
        .padding(.top, 4)
    }

    // MARK: -

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
        CardScreen {
            workspaceGroup
            logGroup
            backgroundGroup
        }
        .screenChrome("Advanced")
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

    // MARK: - Vùng làm việc

    private var workspaceGroup: some View {
        CardGroup(L("Workspace"),
                  footnote: L("Keeps the source IPA + tweaks, re-signs and updates over the installed build.")) {
            CardToggleRow(
                icon: "shippingbox.fill",
                title: L("App Updates (Workspace)"),
                subtitle: L("Save apps as projects · edit tweaks · re-sign and install over"),
                isOn: $workspaceEnabled
            )
            if workspaceEnabled {
                CardDivider()
                CardNavRow(icon: "square.stack.3d.up.fill", title: L("Projects")) {
                    ProjectsListView()
                }
            }
        }
    }

    // MARK: - Nhật ký

    private var logGroup: some View {
        CardGroup(L("Log"),
                  footnote: L("When enabled, the signing screen shows a realtime log panel (can be hidden). Plain text, no emoji.")) {
            CardToggleRow(
                icon: "text.alignleft",
                title: L("Signing Log"),
                subtitle: L("Records the signing process for debugging · shows a realtime log while signing"),
                isOn: $loggingEnabled
            )
            if loggingEnabled {
                CardDivider()
                CardNavRow(icon: "doc.text.magnifyingglass", title: L("View latest log")) {
                    SignLogViewerView()
                }
            }
        }
    }

    // MARK: - Chạy nền

    private var backgroundGroup: some View {
        CardGroup(L("Background Processing"),
                  footnote: L("Prevents iOS from killing the app during large file transfers. Recommended for installing apps larger than 2GB.")) {
            CardRow(icon: "bolt.fill",
                    title: L("Keep App Active"),
                    subtitle: L("Plays silent audio so iOS does not suspend the app")) {
                HStack(spacing: 10) {
                    Button {
                        showBackgroundInfoAlert = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink3)
                    }
                    .buttonStyle(.plain)

                    Toggle("", isOn: $settings.backgroundAudioEnabled)
                        .labelsHidden()
                }
            }

            if settings.backgroundAudioEnabled {
                CardDivider()
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("Background mode active")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    if BackgroundAudioManager.shared.isAudioPlaying {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, Theme.Metric.cardPadding)
                .padding(.vertical, 11)
            }
        }
    }
}
