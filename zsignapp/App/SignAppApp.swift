//
//  SignAppApp.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import SwiftUI

@main
struct SignAppApp: App {
    let storage = Storage.shared
    
    init() {
        setupAppDirectories()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.managedObjectContext, storage.context)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }
    
    private func setupAppDirectories() {
        FileManager.default.setupAppDirectories()
        
        let fm = FileManager.default
    }
    
    private func handleIncomingURL(_ url: URL) {
        
        // Check if it's an IPA file
        guard url.pathExtension.lowercased() == "ipa" else {
            return
        }
        
        // Post notification to import
        NotificationCenter.default.post(
            name: NSNotification.Name("ImportIPAFromShare"),
            object: url
        )
        
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            AppsView()
                .tabItem {
                    Label("Apps", systemImage: "app.badge.fill")
                }
            
            SourcesView()
                .tabItem {
                    Label("Store", systemImage: "bag.fill")
                }
            
            FilesView()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
