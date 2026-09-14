//
//  StorageManagementView.swift
//  zsignapp
//
import SwiftUI

struct StorageManagementView: View {
    @State private var showCleanupAlert = false
    @State private var selectedCleanupType = CleanupType.unsignedApps
    @State private var isCleaningUp = false
    @State private var cleanupMessage = ""
    @State private var storageSize: String = "Calculating..."
    @State private var isCalculating = false
    
    var body: some View {
        Form {
            // MARK: - Storage Overview Section
            Section {
                StorageInfoRow()
            } header: {
                Text("Storage Overview")
            } footer: {
                Text("Total space used by Zsign app data (excluding certificates)")
                    .font(.caption)
            }
            
            // MARK: - Storage Breakdown Section
            Section {
                StorageBreakdownView()
            } header: {
                Text("Storage Breakdown")
            } footer: {
                Text("Detailed view of storage usage by category")
                    .font(.caption)
            }
            
            // MARK: - Cleanup Section
            Section {
                // Picker for cleanup type
                Picker("Cleanup Type", selection: $selectedCleanupType) {
                    ForEach([
                        CleanupType.unsignedApps,
                        CleanupType.signedApps,
                        CleanupType.tempFiles,
                        CleanupType.all
                    ], id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedCleanupType) { _ in
                    updateStorageSize()
                }
                
                // Description & Size
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedCleanupType.description)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        if isCalculating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Calculating...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(storageSize)
                                .font(.headline)
                                .foregroundColor(selectedCleanupType.iconColor)
                                .bold()
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                
                // Clean button
                Button {
                    showCleanupAlert = true
                } label: {
                    HStack {
                        Spacer()
                        if isCleaningUp {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text(cleanupMessage)
                        } else {
                            Text("Clean Now")
                                .bold()
                        }
                        Spacer()
                    }
                }
                .disabled(isCleaningUp || storageSize == "0 bytes" || isCalculating)
                .foregroundColor(isCleaningUp || storageSize == "0 bytes" || isCalculating ? .gray : .red)
                
            } header: {
                Text("Storage Cleanup")
            } footer: {
                Text("Certificates will never be deleted. Only app files and temporary data will be removed.")
                    .font(.caption)
            }
        }
        .navigationTitle("Storage Management")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateStorageSize()
        }
        .alert("Delete \(selectedCleanupType.displayName)?", isPresented: $showCleanupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                performCleanup(type: selectedCleanupType)
            }
        } message: {
            Text(selectedCleanupType.alertMessage)
        }
    }
    
    // MARK: - Functions
    
    private func updateStorageSize() {
        isCalculating = true
        storageSize = "Calculating..."
        
        Task {
            let size = await calculateSize(for: selectedCleanupType)
            await MainActor.run {
                storageSize = size
                isCalculating = false
            }
        }
    }
    
    private func calculateSize(for type: CleanupType) async -> String {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        switch type {
        case .unsignedApps:
            totalSize = StorageCalculator.calculateDirectorySize(at: fileManager.appsDirectory)
            
        case .signedApps:
            totalSize = StorageCalculator.calculateDirectorySize(at: fileManager.signedAppsDirectory)
            
        case .tempFiles:
            let tempDir = fileManager.temporaryDirectory
            
            if let contents = try? fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.fileSizeKey]
            ) {
                for item in contents {
                    if item.lastPathComponent.hasPrefix("ZsignImport_") ||
                       item.lastPathComponent.hasPrefix("Signing_") ||
                       item.lastPathComponent.hasPrefix("IPACreation_") {
                        totalSize += StorageCalculator.calculateDirectorySize(at: item)
                    }
                }
            }
            
        case .all:
            totalSize += StorageCalculator.calculateDirectorySize(at: fileManager.appsDirectory)
            totalSize += StorageCalculator.calculateDirectorySize(at: fileManager.signedAppsDirectory)
            
            let tempDir = fileManager.temporaryDirectory
            if let contents = try? fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.fileSizeKey]
            ) {
                for item in contents {
                    if item.lastPathComponent.hasPrefix("ZsignImport_") ||
                       item.lastPathComponent.hasPrefix("Signing_") ||
                       item.lastPathComponent.hasPrefix("IPACreation_") {
                        totalSize += StorageCalculator.calculateDirectorySize(at: item)
                    }
                }
            }
        }
        
        guard totalSize > 0 else { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    private func performCleanup(type: CleanupType) {
        isCleaningUp = true
        cleanupMessage = "Cleaning..."
        
        Task {
            do {
                try await StorageCleaner.cleanup(type: type)
                
                await MainActor.run {
                    isCleaningUp = false
                    cleanupMessage = ""
                    updateStorageSize()
                    
                    print("Cleanup completed: \(type.displayName)")
                }
            } catch {
                await MainActor.run {
                    isCleaningUp = false
                    cleanupMessage = ""
                    print("Cleanup failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Storage Breakdown View

struct StorageBreakdownView: View {
    @State private var breakdown: StorageBreakdown?
    @State private var isLoading = true
    @State private var hasLoaded = false  // ✅ Flag để tránh tính lại
    
    var body: some View {
        Group {
            if isLoading {
                // ✅ LOADING STATE - chỉ hiện ProgressView
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let breakdown = breakdown {
                // ✅ LOADED STATE - hiện kết quả
                VStack(spacing: 12) {
                    StorageBreakdownRow(
                        title: "Unsigned Apps",
                        size: breakdown.unsignedAppsSize,
                        color: .orange
                    )
                    
                    Divider()
                    
                    StorageBreakdownRow(
                        title: "Signed Apps",
                        size: breakdown.signedAppsSize,
                        color: .accentColor
                    )
                    
                    Divider()
                    
                    StorageBreakdownRow(
                        title: "Other Files",
                        size: breakdown.filesSize,
                        color: .green
                    )
                    
                    Divider()
                    
                    StorageBreakdownRow(
                        title: "Temp Files",
                        size: breakdown.tempFilesSize,
                        color: .purple
                    )
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Text("Total Used")
                            .font(.headline)
                        Spacer()
                        Text(breakdown.totalFormatted)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .task {
            // ✅ Chỉ tính 1 lần duy nhất
            guard !hasLoaded else { return }
            await calculateBreakdown()
        }
    }
    
    private func calculateBreakdown() async {
        guard !hasLoaded else { return }
        
        isLoading = true
        
        // ✅ Tính toán trong background
        let breakdown = await StorageCalculator.getStorageBreakdown()
        
        // ✅ Update UI một lần duy nhất
        await MainActor.run {
            self.breakdown = breakdown
            self.isLoading = false
            self.hasLoaded = true  // ✅ Đánh dấu đã load
        }
    }
}

struct StorageBreakdownRow: View {
    let title: String
    let size: Int64
    let color: Color
    
    private var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(sizeFormatted)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(size > 0 ? color : .secondary)
        }
    }
}

// MARK: - Cleanup Types

enum CleanupType: String, CaseIterable, Hashable {
    case unsignedApps
    case signedApps
    case tempFiles
    case all
    
    var displayName: String {
        switch self {
        case .unsignedApps: return "Unsigned Apps"
        case .signedApps: return "Signed Apps"
        case .tempFiles: return "Temp Files"
        case .all: return "All Data"
        }
    }
    
    var description: String {
        switch self {
        case .unsignedApps: return "Remove all imported apps"
        case .signedApps: return "Remove all signed apps & IPAs"
        case .tempFiles: return "Remove temporary cache"
        case .all: return "Remove everything except certificates"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .unsignedApps: return .orange
        case .signedApps: return .accentColor
        case .tempFiles: return .purple
        case .all: return .red
        }
    }
    
    var alertMessage: String {
        switch self {
        case .unsignedApps:
            return "This will delete all imported apps. You can re-import them later."
        case .signedApps:
            return "This will delete all signed apps and IPAs. You'll need to sign them again."
        case .tempFiles:
            return "This will delete all temporary files from previous operations."
        case .all:
            return "This will delete all apps, IPAs, and temp files. Certificates will be kept safe."
        }
    }
}

// MARK: - Storage Cleaner

struct StorageCleaner {
    static func cleanup(type: CleanupType) async throws {
        let fileManager = FileManager.default
        
        switch type {
        case .unsignedApps:
            try await cleanUnsignedApps(fileManager)
            
        case .signedApps:
            try await cleanSignedApps(fileManager)
            
        case .tempFiles:
            try await cleanTempFiles(fileManager)
            
        case .all:
            try await cleanUnsignedApps(fileManager)
            try await cleanSignedApps(fileManager)
            try await cleanTempFiles(fileManager)
        }
    }
    
    private static func cleanUnsignedApps(_ fileManager: FileManager) async throws {
        print("Cleaning unsigned apps...")
        
        let appsDir = fileManager.appsDirectory
        if fileManager.fileExists(atPath: appsDir.path) {
            try fileManager.removeItem(at: appsDir)
            try fileManager.createDirectory(at: appsDir, withIntermediateDirectories: true)
            print("Deleted Apps directory")
        }
        
        await MainActor.run {
            Storage.shared.deleteAllApps()
            print("Cleared imported apps from database")
        }
    }
    
    private static func cleanSignedApps(_ fileManager: FileManager) async throws {
        print("Cleaning signed apps...")
        
        let signedDir = fileManager.signedAppsDirectory
        if fileManager.fileExists(atPath: signedDir.path) {
            try fileManager.removeItem(at: signedDir)
            try fileManager.createDirectory(at: signedDir, withIntermediateDirectories: true)
            print("Deleted SignedApps directory")
        }
        
        await MainActor.run {
            Storage.shared.deleteAllSignedApps()
            print("Cleared signed apps from database")
        }
    }
    
    private static func cleanTempFiles(_ fileManager: FileManager) async throws {
        print("Cleaning temp files...")
        
        let tempDir = fileManager.temporaryDirectory
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        
        for item in contents {
            if item.lastPathComponent.hasPrefix("ZsignImport_") ||
               item.lastPathComponent.hasPrefix("Signing_") ||
               item.lastPathComponent.hasPrefix("IPACreation_") {
                try? fileManager.removeItem(at: item)
                print("Deleted: \(item.lastPathComponent)")
            }
        }
    }
}

// MARK: - Storage Extensions

extension Storage {
    func deleteAllApps() {
        let fetchRequest = ImportedApp.fetchRequest()
        
        do {
            let apps = try context.fetch(fetchRequest)
            for app in apps {
                context.delete(app)
            }
            try context.save()
        } catch {
            print("Failed to delete apps: \(error)")
        }
    }
    
    func deleteAllSignedApps() {
        let fetchRequest = SignedApp.fetchRequest()
        
        do {
            let apps = try context.fetch(fetchRequest)
            for app in apps {
                context.delete(app)
            }
            try context.save()
        } catch {
            print("Failed to delete signed apps: \(error)")
        }
    }
}

// MARK: - Storage Info Row

struct StorageInfoRow: View {
    @State private var storageInfo: StorageInfo?
    @State private var isLoading = true
    @State private var hasLoaded = false  // ✅ Flag để tránh tính lại
    
    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let info = storageInfo {
                StorageBar(used: info.usedSpace, total: info.totalSpace)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Used")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(info.usedSpaceFormatted)
                            .font(.subheadline)
                            .bold()
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("Total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(info.totalSpaceFormatted)
                            .font(.subheadline)
                            .bold()
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(info.availableSpaceFormatted)
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .task {
            // ✅ Chỉ tính 1 lần duy nhất
            guard !hasLoaded else { return }
            await calculateStorage()
        }
    }
    
    private func calculateStorage() async {
        guard !hasLoaded else { return }
        
        isLoading = true
        
        let info = StorageCalculator.getStorageInfo()
        await MainActor.run {
            self.storageInfo = info
            self.isLoading = false
            self.hasLoaded = true  // ✅ Đánh dấu đã load
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
                            colors: percentage > 0.9 ? [.red, .orange] : [.accentColor, .purple],
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

struct StorageBreakdown {
    let unsignedAppsSize: Int64
    let signedAppsSize: Int64
    let filesSize: Int64
    let tempFilesSize: Int64
    
    var total: Int64 {
        unsignedAppsSize + signedAppsSize + filesSize + tempFilesSize
    }
    
    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}

struct StorageCalculator {
    static func getStorageInfo() -> StorageInfo {
        let fileManager = FileManager.default
        
        var usedSpace: Int64 = 0
        usedSpace += calculateDirectorySize(at: fileManager.appsDirectory)
        usedSpace += calculateDirectorySize(at: fileManager.signedAppsDirectory)
        usedSpace += calculateDirectorySize(at: fileManager.filesDirectory)
        
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
    
    static func getStorageBreakdown() async -> StorageBreakdown {
        let fileManager = FileManager.default
        
        let unsignedSize = calculateDirectorySize(at: fileManager.appsDirectory)
        let signedSize = calculateDirectorySize(at: fileManager.signedAppsDirectory)
        let filesSize = calculateDirectorySize(at: fileManager.filesDirectory)
        
        var tempSize: Int64 = 0
        let tempDir = fileManager.temporaryDirectory
        if let contents = try? fileManager.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for item in contents {
                if item.lastPathComponent.hasPrefix("ZsignImport_") ||
                   item.lastPathComponent.hasPrefix("Signing_") ||
                   item.lastPathComponent.hasPrefix("IPACreation_") {
                    tempSize += calculateDirectorySize(at: item)
                }
            }
        }
        
        return StorageBreakdown(
            unsignedAppsSize: unsignedSize,
            signedAppsSize: signedSize,
            filesSize: filesSize,
            tempFilesSize: tempSize
        )
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
