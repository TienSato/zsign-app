//
//  StoreCatalog.swift
//  zsignapp
//

import Foundation
import SwiftUI
import CryptoKit
import AltSourceKit

// MARK: - Một ứng dụng trong Store (đã gắn nguồn, đã tính sẵn chữ hiển thị)

struct StoreApp: Identifiable, Hashable {
    let id: String

    let app: ASRepository.App
    let sourceName: String
    let sourceKey: String

    // Đã tính sẵn để dòng danh sách không phải làm gì
    let name: String
    let developer: String?
    let iconURL: URL?
    let versionAndSize: String
    let searchName: String

    static func == (lhs: StoreApp, rhs: StoreApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct SourceRef: Sendable {
    let name: String
    let key: String
    let url: URL
}

// MARK: - Lưu JSON nguồn xuống đĩa

enum SourceDiskCache {
    private static let folder = "StoreSources"

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent(folder, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func file(for url: URL) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }

    static func read(_ url: URL) -> Data? {
        guard let file = file(for: url) else { return nil }
        return try? Data(contentsOf: file)
    }

    static func write(_ data: Data, for url: URL) {
        guard let file = file(for: url) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func modifiedDate(_ url: URL) -> Date? {
        guard let file = file(for: url) else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func size() -> Int64 {
        guard let directory,
              let items = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return items.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

// MARK: - View model

final class SourcesViewModel: ObservableObject {
    static let shared = SourcesViewModel()

    @Published private(set) var catalog: [StoreApp] = []

    @Published private(set) var isRefreshing = false

    @Published private(set) var hasContent = false

    @Published private(set) var lastRefreshed: Date?

    private var fetchTask: Task<Void, Never>?
    private var didLoadDisk = false

    private init() {}

    // MARK: Đọc bản lưu trên đĩa — trả kết quả ngay, không chạm mạng

    func loadCachedIfNeeded(_ sources: [AltSource]) async {
        guard !didLoadDisk else { return }
        didLoadDisk = true
        await loadCached(sources)
    }

    func loadCached(_ sources: [AltSource]) async {
        let refs = Self.refs(from: sources)
        guard !refs.isEmpty else { return }

        let decoded: [(SourceRef, ASRepository)] = await Task.detached(priority: .userInitiated) {
            refs.compactMap { ref in
                guard let data = SourceDiskCache.read(ref.url),
                      let repo = try? JSONDecoder().decode(ASRepository.self, from: data)
                else { return nil }
                return (ref, repo)
            }
        }.value

        guard !decoded.isEmpty else { return }

        let built = await Self.buildCatalog(decoded)
        let newest = refs.compactMap { SourceDiskCache.modifiedDate($0.url) }.max()

        await MainActor.run {
            self.catalog = built
            self.hasContent = true
            if self.lastRefreshed == nil { self.lastRefreshed = newest }
        }
    }

    // MARK: Làm mới từ mạng

    func refreshIfStale(_ sources: [AltSource], maxAge: TimeInterval = 900) async {
        if hasContent, let last = lastRefreshed, Date().timeIntervalSince(last) < maxAge {
            return
        }
        await fetchSources(sources)
    }

    func fetchSources(_ sources: [AltSource], refresh: Bool = false, batchSize: Int = 4) async {
        fetchTask?.cancel()

        let refs = Self.refs(from: sources)
        guard !refs.isEmpty else { return }

        await MainActor.run { self.isRefreshing = true }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isRefreshing = false } }

            var collected: [(SourceRef, ASRepository)] = []

            for start in stride(from: 0, to: refs.count, by: batchSize) {
                if Task.isCancelled { break }
                let batch = Array(refs[start..<min(start + batchSize, refs.count)])

                let results = await withTaskGroup(of: (SourceRef, ASRepository?).self) { group -> [(SourceRef, ASRepository?)] in
                    for ref in batch {
                        group.addTask { (ref, await Self.download(ref, force: refresh)) }
                    }
                    var out: [(SourceRef, ASRepository?)] = []
                    for await result in group { out.append(result) }
                    return out
                }

                collected.append(contentsOf: results.compactMap { ref, repo in
                    repo.map { (ref, $0) }
                })

                if Task.isCancelled { break }

                // Đăng kết quả MỘT LẦN cho cả lô, không phải từng nguồn một.
                let snapshot = collected
                let built = await Self.buildCatalog(snapshot)
                await MainActor.run {
                    self.catalog = built
                    self.hasContent = !built.isEmpty
                }
            }

            if !Task.isCancelled {
                await MainActor.run { self.lastRefreshed = Date() }
            }
        }

        fetchTask = task
        await task.value
    }

    func clearDiskCache() {
        SourceDiskCache.clear()
    }

    // MARK: - Nội bộ

    private static func download(_ ref: SourceRef, force: Bool) async -> ASRepository? {
        var request = URLRequest(url: ref.url)
        // Có ETag/Last-Modified thì máy chủ trả 304, gần như không tốn băng thông.
        request.cachePolicy = force ? .reloadRevalidatingCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 20

        if let (data, _) = try? await URLSession.shared.data(for: request),
           let repo = try? JSONDecoder().decode(ASRepository.self, from: data) {
            SourceDiskCache.write(data, for: ref.url)
            return repo
        }

        // Mạng hỏng -> dùng bản lưu, không để trống màn hình.
        if let data = SourceDiskCache.read(ref.url) {
            return try? JSONDecoder().decode(ASRepository.self, from: data)
        }
        return nil
    }

    private static func refs(from sources: [AltSource]) -> [SourceRef] {
        sources.compactMap { source in
            guard let url = source.sourceURL else { return nil }
            return SourceRef(
                name: source.name ?? L("Unknown Source"),
                key: source.identifier ?? url.absoluteString,
                url: url
            )
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func buildCatalog(_ decoded: [(SourceRef, ASRepository)]) async -> [StoreApp] {
        await Task.detached(priority: .userInitiated) {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useAll]
            formatter.countStyle = .file

            var out: [StoreApp] = []
            out.reserveCapacity(decoded.reduce(0) { $0 + $1.1.apps.count })
            var seen = Set<String>()

            for (ref, repo) in decoded {
                for app in repo.apps {
                    let id = ref.key + "|" + app.currentUniqueId
                    guard seen.insert(id).inserted else { continue }

                    var parts: [String] = []
                    if let version = app.currentVersion, !version.isEmpty {
                        parts.append("v" + version)
                    }
                    if let size = app.size {
                        parts.append(formatter.string(fromByteCount: Int64(size)))
                    }

                    let name = app.currentName
                    out.append(StoreApp(
                        id: id,
                        app: app,
                        sourceName: ref.name,
                        sourceKey: ref.key,
                        name: name,
                        developer: app.developer,
                        iconURL: app.iconURL,
                        versionAndSize: parts.joined(separator: " · "),
                        searchName: Self.fold(name)
                    ))
                }
            }
            return out
        }.value
    }
}
