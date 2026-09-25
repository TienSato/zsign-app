//
//  PlistServerStore.swift
//  zsignapp
//
//  Danh sách máy chủ sinh manifest plist và máy chủ đang được chọn.
//
//  Vì sao cần: khi ký xong, iOS chỉ chịu cài từ một tệp manifest plist tải qua
//  HTTPS. Máy chủ sinh tệp đó — file IPA vẫn nằm trong máy, plist chỉ trỏ ngược
//  về 127.0.0.1. Trước đây địa chỉ máy chủ bị viết cứng trong InstallHandler,
//  nên ai muốn tự dựng máy chủ riêng phải sửa mã nguồn rồi build lại.
//

import Foundation

// MARK: - Một máy chủ

struct PlistServer: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, host: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.isBuiltIn = isBuiltIn
    }

    var displayURL: String { "https://\(host)/plist" }
}

// MARK: - Đọc máy chủ đang chọn (an toàn ở mọi luồng)

enum PlistServerConfig {
    static let defaultHost = "sign.zsign.app"
    static let hostKey = "zsign.plistServerHost"

    static var host: String {
        let saved = UserDefaults.standard.string(forKey: hostKey) ?? ""
        return saved.isEmpty ? defaultHost : saved
    }

    static func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[text.startIndex..<slash])
        }
        return text
    }

    static func isValid(_ host: String) -> Bool {
        let h = normalize(host)
        guard h.count >= 4, h.contains("."), !h.contains(" ") else { return false }
        guard !h.hasPrefix("."), !h.hasSuffix(".") else { return false }
        return h.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }
}

// MARK: - Kho máy chủ

final class PlistServerStore: ObservableObject {
    static let shared = PlistServerStore()

    @Published private(set) var servers: [PlistServer] = []
    @Published private(set) var selectedID: UUID?

    private let listKey = "zsign.plistServers"
    private let selectedKey = "zsign.plistServerSelectedID"
    private let defaults = UserDefaults.standard

    private static let builtIn = PlistServer(
        id: UUID(uuidString: "00000000-0000-0000-0000-00005A534E00")!,
        name: "zSign (mặc định)",
        host: PlistServerConfig.defaultHost,
        isBuiltIn: true
    )

    private init() {
        load()
    }

    var selected: PlistServer {
        servers.first { $0.id == selectedID } ?? Self.builtIn
    }

    // MARK: Thao tác

    @discardableResult
    func add(name: String, host: String) -> Bool {
        let cleanHost = PlistServerConfig.normalize(host)
        guard PlistServerConfig.isValid(cleanHost) else { return false }
        guard !servers.contains(where: { $0.host == cleanHost }) else { return false }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = PlistServer(name: cleanName.isEmpty ? cleanHost : cleanName,
                                 host: cleanHost)
        servers.append(server)
        select(server)          // thêm xong dùng luôn
        return true
    }

    func remove(_ server: PlistServer) {
        guard !server.isBuiltIn else { return }
        servers.removeAll { $0.id == server.id }
        if selectedID == server.id {
            select(Self.builtIn)
        } else {
            persist()
        }
    }

    func select(_ server: PlistServer) {
        selectedID = server.id
        defaults.set(server.host, forKey: PlistServerConfig.hostKey)
        persist()
    }

    func resetToDefault() {
        servers = [Self.builtIn]
        select(Self.builtIn)
    }

    // MARK: Lưu / nạp

    private func persist() {
        // Không lưu máy chủ mặc định — nó luôn được dựng lại lúc nạp.
        let custom = servers.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            defaults.set(data, forKey: listKey)
        }
        defaults.set(selectedID?.uuidString, forKey: selectedKey)
    }

    private func load() {
        var list = [Self.builtIn]
        if let data = defaults.data(forKey: listKey),
           let custom = try? JSONDecoder().decode([PlistServer].self, from: data) {
            list.append(contentsOf: custom.filter { !$0.isBuiltIn })
        }
        servers = list

        let savedID = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
        if let savedID, list.contains(where: { $0.id == savedID }) {
            selectedID = savedID
        } else {
            selectedID = Self.builtIn.id
        }

        // Giữ khoá host luôn khớp với máy chủ đang chọn, kể cả khi bản lưu hỏng.
        defaults.set(selected.host, forKey: PlistServerConfig.hostKey)
    }
}
