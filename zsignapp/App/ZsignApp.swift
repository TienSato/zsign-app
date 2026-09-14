//
//  ZsignApp.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import SwiftUI

@main
struct ZsignApp: App {
    let storage = Storage.shared
    @StateObject private var certAutoImporter = CertificateAutoImporter.shared
    @StateObject private var sourceAutoImporter = SourceAutoImporter.shared
    @StateObject private var deviceTheme = DeviceThemeManager.shared
    @StateObject private var appearance = AppearanceManager.shared
    @StateObject private var localization = LocalizationManager.shared
    @State private var showLanguageSetup = false
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        setupAppDirectories()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .id(localization.language)
                .environment(\.locale, localization.locale)
                .environment(\.managedObjectContext, storage.context)
                .tint(appearance.effectiveAccent(deviceAccent: deviceTheme.accent))
                .accentColor(appearance.effectiveAccent(deviceAccent: deviceTheme.accent))
                .preferredColorScheme(appearance.appScheme.scheme)
                .environmentObject(deviceTheme)
                .environmentObject(appearance)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onAppear {
                    if !localization.hasChosen { showLanguageSetup = true }
                    deviceTheme.bootstrap()
                    IslandBadgeController.shared.apply(enabled: true)
                    SharedImportScanner.shared.scanAndImport()
                    Task {
                        await certAutoImporter.autoImportCertificate()
                        await sourceAutoImporter.autoImportSources()
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        SharedImportScanner.shared.scanAndImport()
                        IslandBadgeController.shared.apply(enabled: true)
                    }
                }
                .onChange(of: deviceTheme.accent) { _ in
                    IslandBadgeController.shared.apply(enabled: true)
                }
                .onChange(of: appearance.mode) { _ in
                    IslandBadgeController.shared.apply(enabled: true)
                }
                .onChange(of: appearance.presetIndex) { _ in
                    IslandBadgeController.shared.apply(enabled: true)
                }
                .onChange(of: appearance.customColor) { _ in
                    IslandBadgeController.shared.apply(enabled: true)
                }
                .fullScreenCover(isPresented: $showLanguageSetup) {
                    FirstLaunchLanguageView { showLanguageSetup = false }
                }
        }
    }
    
    private func setupAppDirectories() {
        FileManager.default.setupAppDirectories()
    }
    
    private func handleIncomingURL(_ url: URL) {
        print("📥 Received URL: \(url)")
        
        // Share Extension mở app qua scheme zsignapp:// -> quét Inbox
        if url.scheme == "zsignapp" {
            SharedImportScanner.shared.scanAndImport()
            return
        }
        
        guard url.pathExtension.lowercased() == "ipa" else {
            print("⚠️ Not an IPA file")
            return
        }
        
        // Copy file vào temp directory
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ipa")
        
        do {
            try? FileManager.default.removeItem(at: tempURL)
            
            // Access security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            try FileManager.default.copyItem(at: url, to: tempURL)
            print("✅ File copied to temp: \(tempURL.path)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ImportIPAFromShare"),
                    object: tempURL
                )
                print("📤 Notification posted")
            }
            
        } catch {
            print("❌ Error copying file: \(error)")
        }
    }
}

struct MainTabView: View {
    @StateObject private var autoSignProgress = AutoSignProgressManager.shared
    
    var body: some View {
        ZStack {
            TabView {
                AppsView()
                    .tabItem {
                        Label("Apps", systemImage: "app.badge.fill")
                    }
                
                SourcesView()
                    .tabItem {
                        Label("Store", systemImage: "bag.fill")
                    }
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            
            // Auto Sign Progress Overlay
            if autoSignProgress.isProcessing {
                VStack(spacing: 12) {
                    Text("Auto Sign & Install")
                        .font(.headline)
                    
                    Text(autoSignProgress.currentAppName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(L(autoSignProgress.currentStep))
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 6) {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray4))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(width: 200 * autoSignProgress.progress, height: 8)
                                .animation(.linear(duration: 0.3), value: autoSignProgress.progress)
                        }
                        .frame(width: 200)
                        
                        Text("\(Int(autoSignProgress.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(24)
                .adaptiveGlass(cornerRadius: 16)
                .shadow(color: .black.opacity(0.25), radius: 20)
            }
        }
    }
}
