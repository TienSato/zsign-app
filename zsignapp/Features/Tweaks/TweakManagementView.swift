//
//  TweakManagementView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct TweakManagementView: View {
    @Binding var injectionFiles: [URL]
    @State private var showFilePicker = false
    
    var body: some View {
        List {
            ForEach(injectionFiles, id: \.absoluteString) { url in
                HStack {
                    Image(systemName: iconForFileType(url.pathExtension))
                        .foregroundColor(colorForFileType(url.pathExtension))
                        .font(.title3)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 15, weight: .semibold))
                        
                        Text(url.pathExtension.uppercased())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        removeFile(url)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .onDelete(perform: deleteFiles)
        }
        .navigationTitle("Inject Tweaks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: Button(action: {
            showFilePicker = true
        }) {
            Image(systemName: "plus")
        })
        .sheet(isPresented: $showFilePicker) {
            FileImporterRepresentableView(
                allowedContentTypes: [.data, .item],
                onDocumentsPicked: { urls in
                    guard let url = urls.first else { return }
                    addFile(url)
                }
            )
        }
        .overlay {
            if injectionFiles.isEmpty {
                EmptyStateView(
                    title: "No Tweaks",
                    systemImage: "syringe",
                    message: "Tap + to add .dylib, .deb, or .bundle files",
                    style: .compact
                )
            }
        }
    }
    
    private func addFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["dylib", "deb", "bundle", "framework"].contains(ext) else {
            return
        }
        // Copy to app storage
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent("Tweaks")
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent(url.lastPathComponent)
        // Remove existing file if exists
        try? FileManager.default.removeItem(at: destURL)
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            if ext == "bundle" || ext == "framework" {
                // Copy directory recursively
                try FileManager.default.copyItem(at: url, to: destURL)
            } else {
                // Copy single file
                try FileManager.default.copyItem(at: url, to: destURL)
            }
            injectionFiles.append(destURL)
        } catch {
        }
    }
    private func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        injectionFiles.removeAll { $0 == url }
    }
    
    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets {
            let url = injectionFiles[index]
            try? FileManager.default.removeItem(at: url)
        }
        injectionFiles.remove(atOffsets: offsets)
    }
    private func iconForFileType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "dylib":
            return "cube.fill"
        case "deb":
            return "shippingbox.fill"
        case "bundle":
            return "folder.fill"
        case "framework":
            return "building.columns.fill"
        default:
            return "doc.fill"
        }
    }
    
    private func colorForFileType(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "dylib":
            return .accentColor
        case "deb":
            return .orange
        case "bundle":
            return .purple
        case "framework":
            return .green
        default:
            return .gray
        }
    }
}
