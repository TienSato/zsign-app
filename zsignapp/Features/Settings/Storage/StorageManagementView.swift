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
    
    private var isCleanupDisabled: Bool {
        isCleaningUp || storageSize == "0 bytes" || isCalculating
    }

    var body: some View {
        CardScreen {
            overviewGroup
            breakdownGroup
            cleanupGroup
        }
        .screenChrome("Storage Management")
        .onAppear {
            updateStorageSize()
        }
        .alert(Text(String(format: L("Delete %@?"), L(selectedCleanupType.displayName))),
               isPresented: $showCleanupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                performCleanup(type: selectedCleanupType)
            }
        } message: {
            Text(L(selectedCleanupType.alertMessage))
        }
    }

    // MARK: - Tổng quan dung lượng

    private var overviewGroup: some View {
        CardGroup(L("Storage Overview"),
                  footnote: L("Total space used by Zsign app data (excluding certificates)")) {
            StorageInfoRow()
                .padding(.horizontal, Theme.Metric.cardPadding)
                .padding(.vertical, 14)
        }
    }

    // MARK: - Chi tiết theo nhóm

    private var breakdownGroup: some View {
        CardGroup(L("Storage Breakdown"),
                  footnote: L("Detailed view of storage usage by category")) {
            StorageBreakdownView()
                .padding(.horizontal, Theme.Metric.cardPadding)
                .padding(.vertical, 14)
        }
    }

    // MARK: - Dọn dẹp

    private var cleanupGroup: some View {
        CardGroup(L("Storage Cleanup"),
                  footnote: L("Certificates will never be deleted. Only app files and temporary data will be removed.")) {
            // Chọn kiểu dọn
            CardRow(icon: "trash.fill",
                    title: L("Cleanup Type"),
                    iconTint: selectedCleanupType.iconColor) {
                Picker("", selection: $selectedCleanupType) {
                    ForEach([
                        CleanupType.unsignedApps,
                        CleanupType.signedApps,
                        CleanupType.tempFiles,
                        CleanupType.all
                    ], id: \.self) { type in
                        Text(L(type.displayName)).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: selectedCleanupType) { _ in
                    updateStorageSize()
                }
            }

            CardDivider()

            // Mô tả & dung lượng sẽ giải phóng
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(selectedCleanupType.description))
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)

                    if isCalculating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Calculating...")
                                .font(.caption)
                                .foregroundStyle(Theme.ink2)
                        }
                    } else {
                        Text(storageSize)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(selectedCleanupType.iconColor)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)

            // Nút dọn
            Button {
                showCleanupAlert = true
            } label: {
                HStack(spacing: 8) {
                    if isCleaningUp {
                        ProgressView()
                            .tint(.white)
                        Text(L(cleanupMessage))
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Clean Now")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isCleanupDisabled ? Theme.ink3 : Color.red)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCleanupDisabled)
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.bottom, Theme.Metric.cardPadding)
            .padding(.top, 2)
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
                    
                }
            } catch {
                await MainActor.run {
                    isCleaningUp = false
                    cleanupMessage = ""
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

                    CardDivider(inset: 0)

                    StorageBreakdownRow(
                        title: "Signed Apps",
                        size: breakdown.signedAppsSize,
                        color: .accentColor
                    )

                    CardDivider(inset: 0)

                    StorageBreakdownRow(
                        title: "Other Files",
                        size: breakdown.filesSize,
                        color: .green
                    )

                    CardDivider(inset: 0)

                    StorageBreakdownRow(
                        title: "Temp Files",
                        size: breakdown.tempFilesSize,
                        color: .purple
                    )

                    CardDivider(inset: 0)
                        .padding(.vertical, 4)

                    HStack {
                        Text("Total Used")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(breakdown.totalFormatted)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
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
        HStack(spacing: 10) {
            Circle()
                .fill(size > 0 ? color : Theme.ink3.opacity(0.35))
                .frame(width: 8, height: 8)

            Text(L(title))
                .font(.subheadline)
                .foregroundStyle(Theme.ink)

            Spacer()

            Text(sizeFormatted)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(size > 0 ? color : Theme.ink2)
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
        
        let appsDir = fileManager.appsDirectory
        if fileManager.fileExists(atPath: appsDir.path) {
            try fileManager.removeItem(at: appsDir)
            try fileManager.createDirectory(at: appsDir, withIntermediateDirectories: true)
        }
        
        await MainActor.run {
            Storage.shared.deleteAllApps()
        }
    }
    
    private static func cleanSignedApps(_ fileManager: FileManager) async throws {
        
        let signedDir = fileManager.signedAppsDirectory
        if fileManager.fileExists(atPath: signedDir.path) {
            try fileManager.removeItem(at: signedDir)
            try fileManager.createDirectory(at: signedDir, withIntermediateDirectories: true)
        }
        
        await MainActor.run {
            Storage.shared.deleteAllSignedApps()
        }
    }
    
    private static func cleanTempFiles(_ fileManager: FileManager) async throws {
        
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
                            .foregroundStyle(Theme.ink2)
                        Text(info.usedSpaceFormatted)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(Theme.ink)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 4) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                        Text(info.totalSpaceFormatted)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(Theme.ink)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Available")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                        Text(info.availableSpaceFormatted)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.green)
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
                    .fill(Theme.cardAlt)

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
