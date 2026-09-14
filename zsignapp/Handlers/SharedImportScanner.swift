//
//  SharedImportScanner.swift
//  zsignapp
//
//  Quét App Group Inbox (do Share Extension ghi vào) và bơm .ipa vào
//  pipeline nhập sẵn có bằng notification "ImportIPAFromShare".
//

import Foundation

final class SharedImportScanner {
    static let shared = SharedImportScanner()
    static let appGroupId = "group.signipa.sato.zsignapp"

    private let queue = DispatchQueue(label: "com.zsignapp.sharedimport")
    private init() {}

    func scanAndImport() {
        queue.async {
            let fm = FileManager.default
            guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) else {
                return
            }
            let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else {
                return
            }

            for src in files where ["ipa", "tipa"].contains(src.pathExtension.lowercased()) {
                let tmp = fm.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("ipa")
                do {
                    try? fm.removeItem(at: tmp)
                    // move: vừa lấy file vừa dọn Inbox
                    try fm.moveItem(at: src, to: tmp)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ImportIPAFromShare"),
                            object: tmp
                        )
                    }
                } catch {
                    try? fm.removeItem(at: src)
                }
            }
        }
    }
}
