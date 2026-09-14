//
//  AppTweaksManagerView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//
//  Liệt kê framework / dylib / bundle có sẵn trong IPA: bật-tắt cho lần ký,
//  hoặc trích xuất ra thư mục Tweaks. Giao diện dựng bằng bộ thẻ dùng chung
//  (Theme + CardComponents) thay cho Form.
//

import SwiftUI
import ZsignSwift

// MARK: - Main View
struct AppTweaksManagerView: View {
    let app: ImportedApp
    @Binding var disabledTweaks: [String]
    @Environment(\.dismiss) var dismiss
    
    @State private var frameworks: [TweakFile] = []
    @State private var dylibs: [TweakFile] = []
    @State private var bundles: [TweakFile] = []
    
    @State private var isFrameworksExpanded = false
    @State private var isDylibsExpanded = false
    @State private var isBundlesExpanded = false
    
    @State private var selectedForExtraction: Set<String> = []
    @State private var showExtractMode = false
    @State private var isExtracting = false
    @State private var showSuccess = false
    @State private var extractedCount = 0
    @State private var extractedPath = ""
    
    private var allTweaks: [TweakFile] {
        frameworks + dylibs + bundles
    }
    private var totalCount: Int {
        allTweaks.count
    }
    
    var body: some View {
        CardScreen {
            modeToggleSection
            instructionsSection
            if totalCount > 0 {
                summarySection
            }
            if !frameworks.isEmpty {
                collapsibleSection(
                    title: L("Frameworks"),
                    count: frameworks.count,
                    items: frameworks,
                    isExpanded: $isFrameworksExpanded
                )
            }
            if !dylibs.isEmpty {
                collapsibleSection(
                    title: L("Dynamic Libraries"),
                    count: dylibs.count,
                    items: dylibs,
                    isExpanded: $isDylibsExpanded
                )
            }
            if !bundles.isEmpty {
                collapsibleSection(
                    title: L("Bundles"),
                    count: bundles.count,
                    items: bundles,
                    isExpanded: $isBundlesExpanded
                )
            }
            
            if totalCount == 0 {
                emptyStateSection
            }
            
            if showExtractMode && !selectedForExtraction.isEmpty {
                extractButtonSection
            }
        }
        .screenChrome("App Tweaks")
        .toolbar {
            toolbarContent
        }
        .onAppear {
            frameworks = []
            dylibs = []
            bundles = []
            isFrameworksExpanded = false
            isDylibsExpanded = false
            isBundlesExpanded = false
            selectedForExtraction = []
            
            loadTweaks()
        }
        .alert("Extraction Complete", isPresented: $showSuccess) {
            Button("OK") {}
            Button("Show in Files") {
                showInFiles()
            }
        } message: {
            Text("Extracted \(extractedCount) file(s) to:\n\(extractedPath)")
        }
        .animation(.easeInOut, value: showExtractMode)
    }
    
    private func showInFiles() {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let tweaksURL = documentsURL.appendingPathComponent("Tweaks")
        
        if let url = URL(string: "shareddocuments://\(tweaksURL.path)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Các mảnh giao diện, hành động, nạp dữ liệu và trích xuất
private extension AppTweaksManagerView {

    // MARK: - View Components
    
    var modeToggleSection: some View {
        CardGroup {
            Picker("Mode", selection: $showExtractMode) {
                Text("Enable/Disable for Signing").tag(false)
                Text("Extract Tweaks").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(Theme.Metric.cardPadding)
        }
    }
    
    var instructionsSection: some View {
        Text(showExtractMode ?
             L("Select tweaks to extract to your library") :
             L("Enabled tweaks will be injected when signing"))
            .font(.caption)
            .foregroundStyle(Theme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
    
    var summarySection: some View {
        CardGroup(L("Overview")) {
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    summaryItem(
                        count: frameworks.count,
                        label: L("Frameworks")
                    )
                    
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1, height: 40)
                    
                    summaryItem(
                        count: dylibs.count,
                        label: L("Dylibs")
                    )
                    
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1, height: 40)
                    
                    summaryItem(
                        count: bundles.count,
                        label: L("Bundles")
                    )
                }
                
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                
                HStack {
                    Text("Total Tweaks")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                    
                    Spacer()
                    
                    Text("\(totalCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(Theme.Metric.cardPadding)
        }
    }
    
    func summaryItem(count: Int, label: String) -> some View {
        VStack(spacing: 8) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.ink)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
    }
    
    func collapsibleSection(
        title: String,
        count: Int,
        items: [TweakFile],
        isExpanded: Binding<Bool>
    ) -> some View {
        CardGroup {
            Button {
                withAnimation {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        
                        Text(String(format: L("%d item(s)"), count))
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(.horizontal, Theme.Metric.cardPadding)
                .padding(.vertical, 12)
                .frame(minHeight: Theme.Metric.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded.wrappedValue {
                ForEach(items) { tweak in
                    CardDivider()
                    if showExtractMode {
                        ExtractRow(
                            tweak: tweak,
                            isSelected: selectedForExtraction.contains(tweak.relativePath),
                            action: { toggleExtractSelection(tweak) }
                        )
                    } else {
                        ToggleRow(
                            tweak: tweak,
                            isEnabled: !disabledTweaks.contains(tweak.relativePath),
                            action: { toggleTweakEnabled(tweak) }
                        )
                    }
                }
            }
        }
    }
    
    var emptyStateSection: some View {
        EmptyStateView(
            title: "No Tweaks Found",
            systemImage: "wrench.and.screwdriver",
            message: "This app doesn't contain any tweaks",
            style: .compact
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .cardStyle()
    }
    
    var extractButtonSection: some View {
        Button {
            extractSelected()
        } label: {
            HStack(spacing: 8) {
                if isExtracting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(isExtracting
                     ? L("Extracting...")
                     : String(format: L("Extract %d File(s)"), selectedForExtraction.count))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(isExtracting ? 0.5 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isExtracting)
    }
    
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if totalCount > 0 {
            ToolbarItem(placement: .navigationBarTrailing) {
                if showExtractMode {
                    Button(selectedForExtraction.isEmpty ? "Select All" : "Deselect All") {
                        toggleSelectAll()
                    }
                } else {
                    Menu {
                        Button(action: enableAll) {
                            Label("Enable All", systemImage: "checkmark.circle")
                        }
                        Button(action: disableAll) {
                            Label("Disable All", systemImage: "xmark.circle")
                        }
                        
                        Divider()
                        
                        Button(action: expandAll) {
                            Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        Button(action: collapseAll) {
                            Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Actions
    
    func toggleTweakEnabled(_ tweak: TweakFile) {
        if disabledTweaks.contains(tweak.relativePath) {
            disabledTweaks.removeAll { $0 == tweak.relativePath }
        } else {
            disabledTweaks.append(tweak.relativePath)
        }
    }
    
    func enableAll() {
        disabledTweaks.removeAll()
    }
    
    func disableAll() {
        disabledTweaks = allTweaks.map { $0.relativePath }
    }
    
    func toggleExtractSelection(_ tweak: TweakFile) {
        if selectedForExtraction.contains(tweak.relativePath) {
            selectedForExtraction.remove(tweak.relativePath)
        } else {
            selectedForExtraction.insert(tweak.relativePath)
        }
    }
    
    func toggleSelectAll() {
        if selectedForExtraction.isEmpty {
            selectedForExtraction = Set(allTweaks.map { $0.relativePath })
        } else {
            selectedForExtraction.removeAll()
        }
    }
    
    func expandAll() {
        withAnimation {
            isFrameworksExpanded = true
            isDylibsExpanded = true
            isBundlesExpanded = true
        }
    }
    
    func collapseAll() {
        withAnimation {
            isFrameworksExpanded = false
            isDylibsExpanded = false
            isBundlesExpanded = false
        }
    }

    // MARK: - Data Loading
    
    func loadTweaks() {
        guard let appDirURL = Storage.shared.getAppDirectory(for: app) else {
            return
        }
        
        guard let appURL = findAppFile(in: appDirURL) else {
            return
        }
        
        if let (frameworks, dylibs) = loadTweaksFromExecutable(appURL: appURL) {
            self.frameworks = frameworks
            self.dylibs = dylibs
        }
        
        self.bundles = loadBundles(appURL: appURL)
    }
    
    func findAppFile(in directory: URL) -> URL? {
        if directory.pathExtension == "app" {
            return directory
        }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        
        for item in contents where item.hasSuffix(".app") {
            return directory.appendingPathComponent(item)
        }
        
        return nil
    }
    
    func loadTweaksFromExecutable(appURL: URL) -> (frameworks: [TweakFile], dylibs: [TweakFile])? {
        guard let bundle = Bundle(url: appURL),
              let execURL = bundle.executableURL else {
            return nil
        }
        
        let execPath: String
        if execURL.path.hasPrefix(appURL.path) {
            execPath = execURL.path
        } else {
            execPath = appURL.appendingPathComponent(execURL.relativePath).path
        }
        
        guard FileManager.default.fileExists(atPath: execPath) else {
            return nil
        }
        
        var allDylibs: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global(qos: .userInitiated).async {
            usleep(100_000)
            let result = Zsign.listDylibs(appExecutable: execPath).map { $0 as String }
            allDylibs = result
            semaphore.signal()
        }
        
        semaphore.wait()
        
        guard !allDylibs.isEmpty else {
            return nil
        }
        
        var foundFrameworks: [TweakFile] = []
        var foundDylibs: [TweakFile] = []
        
        for dylibPath in allDylibs {
            guard !dylibPath.hasPrefix("/usr/"),
                  !dylibPath.hasPrefix("/System/"),
                  !dylibPath.contains("CydiaSubstrate") else {
                continue
            }
            
            var actualPath = dylibPath
                .replacingOccurrences(of: "@rpath/", with: "Frameworks/")
                .replacingOccurrences(of: "@executable_path/", with: "")
            
            let fileURL = appURL.appendingPathComponent(actualPath)
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            
            if actualPath.contains(".framework/") {
                if let framework = extractFramework(from: actualPath, appURL: appURL) {
                    if !foundFrameworks.contains(where: { $0.name == framework.name }) {
                        foundFrameworks.append(framework)
                    }
                }
            } else if fileURL.lastPathComponent.hasSuffix(".dylib") {
                foundDylibs.append(TweakFile(
                    name: fileURL.lastPathComponent,
                    type: .dylib,
                    relativePath: actualPath,
                    url: fileURL
                ))
            }
        }
        
        return (
            frameworks: foundFrameworks.sorted { $0.name < $1.name },
            dylibs: foundDylibs.sorted { $0.name < $1.name }
        )
    }
    
    func extractFramework(from path: String, appURL: URL) -> TweakFile? {
        let components = path.components(separatedBy: "/")
        guard let fwIndex = components.firstIndex(where: { $0.hasSuffix(".framework") }) else {
            return nil
        }
        
        let frameworkName = components[fwIndex]
        let frameworkPath = components[...fwIndex].joined(separator: "/")
        let frameworkURL = appURL.appendingPathComponent(frameworkPath)
        
        return TweakFile(
            name: frameworkName,
            type: .framework,
            relativePath: frameworkPath,
            url: frameworkURL
        )
    }
    
    func loadBundles(appURL: URL) -> [TweakFile] {
        let bundlePaths = ["", "Library/Application Support", "var/jb/Library/Application Support"]
        var foundBundles: [TweakFile] = []
        
        for path in bundlePaths {
            let fullPath = path.isEmpty ? appURL : appURL.appendingPathComponent(path)
            
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: fullPath.path) else {
                continue
            }
            
            for item in items where item.hasSuffix(".bundle") {
                let itemURL = fullPath.appendingPathComponent(item)
                let relativePath = path.isEmpty ? item : "\(path)/\(item)"
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    foundBundles.append(TweakFile(
                        name: item,
                        type: .bundle,
                        relativePath: relativePath,
                        url: itemURL
                    ))
                }
            }
        }
        
        return foundBundles.sorted { $0.name < $1.name }
    }

    // MARK: - Extraction
    
    func extractSelected() {
        guard !selectedForExtraction.isEmpty else { return }
        
        isExtracting = true
        
        Task {
            do {
                let documentsURL = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )[0]
                let tweaksURL = documentsURL.appendingPathComponent("Tweaks")
                
                try? FileManager.default.createDirectory(
                    at: tweaksURL,
                    withIntermediateDirectories: true
                )
                
                var count = 0
                
                for tweak in allTweaks where selectedForExtraction.contains(tweak.relativePath) {
                    let destURL = tweaksURL.appendingPathComponent(tweak.name)
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.copyItem(at: tweak.url, to: destURL)
                    count += 1
                }
                
                await MainActor.run {
                    self.isExtracting = false
                    self.extractedCount = count
                    self.extractedPath = "Documents/Tweaks"
                    self.showSuccess = true
                    self.selectedForExtraction.removeAll()
                }
                
            } catch {
                await MainActor.run {
                    self.isExtracting = false
                }
            }
        }
    }
}

// MARK: - Row Views
struct ToggleRow: View {
    let tweak: TweakFile
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            CardRow(icon: isEnabled ? "checkmark.circle.fill" : "xmark.circle",
                    title: tweak.name,
                    subtitle: tweak.type.displayName,
                    iconTint: isEnabled ? .green : .red)
        }
        .buttonStyle(.plain)
    }
}

struct ExtractRow: View {
    let tweak: TweakFile
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Theme.ink3)
                    .frame(width: Theme.Metric.iconBox, alignment: .center)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(tweak.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    
                    HStack(spacing: 6) {
                        Text(tweak.type.displayName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tweak.type.color, in: Capsule())
                        
                        Text(tweak.relativePath)
                            .font(.caption2)
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 8)
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)
            .frame(minHeight: Theme.Metric.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data Models
struct TweakFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: TweakFileType
    let relativePath: String
    let url: URL
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(relativePath)
    }
    
    static func == (lhs: TweakFile, rhs: TweakFile) -> Bool {
        lhs.relativePath == rhs.relativePath
    }
}

enum TweakFileType {
    case dylib
    case framework
    case bundle
    
    var displayName: String {
        switch self {
        case .dylib: return "DYLIB"
        case .framework: return "FRAMEWORK"
        case .bundle: return "BUNDLE"
        }
    }
    
    var color: Color {
        switch self {
        case .dylib: return .accentColor
        case .framework: return .purple
        case .bundle: return .green
        }
    }
}
