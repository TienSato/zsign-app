//
//  SignProject.swift
//  zsignapp
//
//  "Workspace" rút gọn (kiểu LCSign): mỗi app đã nhập lưu thành 1 project =
//  IPA GỐC (chính là ImportedApp đã lưu) + danh sách dylib + cert. Sửa tweak ->
//  ký lại TỪ GỐC -> cài đè (cùng bundle id = cập nhật tại chỗ, giữ data).
//
//  Lưu bằng JSON trong Documents/SignProjects/ (không đụng Core Data model).
//

import Foundation
import UIKit
import ZsignSwift

struct ProjectDylib: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var fileName: String            // lưu tại SignProjects/<projectId>/dylibs/<fileName>
    var enabled: Bool = true
    var weak: Bool = true
}

struct SignProject: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var importedAppUUID: String     // liên kết ImportedApp (bản gốc)
    var displayName: String
    var bundleId: String
    var version: String
    var certificateUUID: String?
    var dylibs: [ProjectDylib] = []
    var disabledTweaks: [String] = []   // tweak SẴN CÓ bị tắt -> gỡ khi ký
    var detectedTweakCount: Int = 0     // số tweak/mod app đã có sẵn (cache để hiện ngoài danh sách)
    // Cấu hình ký RIÊNG project (rỗng = giữ như gốc)
    var customBundleID: String = ""
    var customName: String = ""
    var customVersion: String = ""
    var removeWatch: Bool = false
    var removeURLScheme: Bool = false
    var removeProvision: Bool = false
    var hasCustomIcon: Bool = false

    /// Bundle id thực tế khi ký (custom nếu có, không thì gốc).
    var effectiveBundleId: String { customBundleID.isEmpty ? bundleId : customBundleID }
    var createdAt: Date = Date()
    var lastSignedAt: Date?
}

@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published var projects: [SignProject] = []

    private let rootDir: URL
    private let jsonURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootDir = docs.appendingPathComponent("SignProjects", isDirectory: true)
        jsonURL = rootDir.appendingPathComponent("projects.json")
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence
    func load() {
        guard let data = try? Data(contentsOf: jsonURL),
              let list = try? JSONDecoder().decode([SignProject].self, from: data) else {
            projects = []
            return
        }
        projects = list
    }

    func save() {
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }

    // MARK: - CRUD
    @discardableResult
    func addProject(from app: ImportedApp) -> SignProject {
        let p = SignProject(
            importedAppUUID: app.uuid ?? "",
            displayName: app.name ?? "Unknown",
            bundleId: app.identifier ?? "",
            version: app.version ?? ""
        )
        projects.insert(p, at: 0)
        try? FileManager.default.createDirectory(at: dylibsDir(for: p), withIntermediateDirectories: true)
        save()
        refreshDetectedCount(p.id)
        return p
    }

    func update(_ project: SignProject) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
            save()
        }
    }

    func delete(_ project: SignProject) {
        projects.removeAll { $0.id == project.id }
        try? FileManager.default.removeItem(at: projectDir(for: project))
        save()
    }

    // MARK: - Quét tweak có sẵn (cache detectedTweakCount)
    func refreshDetectedCount(_ projectID: UUID) {
        guard let p = projects.first(where: { $0.id == projectID }),
              let app = Storage.shared.fetchApps().first(where: { $0.uuid == p.importedAppUUID }),
              let dir = Storage.shared.getAppDirectory(for: app) else { return }
        Task.detached {
            let count = TweakScanner.count(appDirectory: dir)
            await MainActor.run {
                if var proj = ProjectStore.shared.projects.first(where: { $0.id == projectID }),
                   proj.detectedTweakCount != count {
                    proj.detectedTweakCount = count
                    ProjectStore.shared.update(proj)
                }
            }
        }
    }

    // MARK: - Icon riêng
    func iconURL(for p: SignProject) -> URL {
        projectDir(for: p).appendingPathComponent("icon.png")
    }
    func setIcon(_ image: UIImage, for projectIn: SignProject) -> SignProject {
        var p = projectIn
        try? FileManager.default.createDirectory(at: projectDir(for: p), withIntermediateDirectories: true)
        if let data = image.pngData() {
            try? data.write(to: iconURL(for: p), options: .atomic)
            p.hasCustomIcon = true
            update(p)
        }
        return p
    }
    func removeIcon(for projectIn: SignProject) -> SignProject {
        var p = projectIn
        try? FileManager.default.removeItem(at: iconURL(for: p))
        p.hasCustomIcon = false
        update(p)
        return p
    }
    func iconImage(for p: SignProject) -> UIImage? {
        guard p.hasCustomIcon, let data = try? Data(contentsOf: iconURL(for: p)) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Files
    func projectDir(for p: SignProject) -> URL {
        rootDir.appendingPathComponent(p.id.uuidString, isDirectory: true)
    }
    func dylibsDir(for p: SignProject) -> URL {
        projectDir(for: p).appendingPathComponent("dylibs", isDirectory: true)
    }

    /// Copy 1 file dylib/deb vào project. Trả về ProjectDylib mới (hoặc nil nếu lỗi).
    func addDylib(to projectIn: SignProject, from srcURL: URL) -> SignProject {
        var project = projectIn
        let dir = dylibsDir(for: project)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var name = srcURL.lastPathComponent
        // tránh trùng tên -> nếu trùng thì GHI ĐÈ (giống LCSign: plugin cùng tên -> cập nhật)
        let dest = dir.appendingPathComponent(name)

        let accessing = srcURL.startAccessingSecurityScopedResource()
        defer { if accessing { srcURL.stopAccessingSecurityScopedResource() } }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: srcURL, to: dest)
        } catch {
            return project
        }

        // nếu chưa có entry cùng tên thì thêm (nếu trùng: đã ghi đè file, giữ entry cũ)
        if !project.dylibs.contains(where: { $0.fileName == name }) {
            project.dylibs.append(ProjectDylib(fileName: name))
        }
        update(project)
        return project
    }

    func removeDylib(from projectIn: SignProject, dylib: ProjectDylib) -> SignProject {
        var project = projectIn
        let f = dylibsDir(for: project).appendingPathComponent(dylib.fileName)
        try? FileManager.default.removeItem(at: f)
        project.dylibs.removeAll { $0.id == dylib.id }
        update(project)
        return project
    }

    /// URL các dylib đang bật -> đưa vào options.injectionFiles khi ký.
    func enabledDylibURLs(for p: SignProject) -> [URL] {
        let dir = dylibsDir(for: p)
        return p.dylibs.filter { $0.enabled }.map { dir.appendingPathComponent($0.fileName) }
    }
}

// MARK: - Đếm tweak/mod có sẵn trong 1 app (framework injected + dylib + .bundle)
enum TweakScanner {
    static func count(appDirectory: URL) -> Int {
        guard let appURL = findAppBundle(in: appDirectory),
              let bundle = Bundle(url: appURL),
              let execURL = bundle.executableURL,
              FileManager.default.fileExists(atPath: execURL.path) else {
            return 0
        }
        let loads = Zsign.listDylibs(appExecutable: execURL.path)
        var frameworks = Set<String>()
        var dylibCount = 0
        for d in loads {
            if d.hasPrefix("/usr/") || d.hasPrefix("/System/") || d.contains("CydiaSubstrate") { continue }
            let rp = d.replacingOccurrences(of: "@rpath/", with: "Frameworks/")
                      .replacingOccurrences(of: "@executable_path/", with: "")
            let fileURL = appURL.appendingPathComponent(rp)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            if rp.contains(".framework/") {
                if let name = rp.components(separatedBy: ".framework/").first?
                        .components(separatedBy: "/").last, !name.isEmpty {
                    frameworks.insert(name)
                }
            } else if fileURL.lastPathComponent.hasSuffix(".dylib") {
                dylibCount += 1
            }
        }
        var bundleCount = 0
        for sub in ["", "Library/Application Support", "var/jb/Library/Application Support"] {
            let dir = sub.isEmpty ? appURL : appURL.appendingPathComponent(sub)
            if let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                bundleCount += items.filter { $0.hasSuffix(".bundle") }.count
            }
        }
        return frameworks.count + dylibCount + bundleCount
    }

    static func findAppBundle(in dir: URL) -> URL? {
        if dir.pathExtension == "app" { return dir }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        for i in items where i.hasSuffix(".app") { return dir.appendingPathComponent(i) }
        return nil
    }
}
