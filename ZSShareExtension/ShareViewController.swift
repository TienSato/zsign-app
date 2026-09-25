//
//  ShareViewController.swift
//  ZSShareExtension

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

final class ShareViewController: UIViewController {

    // PHẢI trùng App Group đã bật ở CẢ app chính và extension
    static let appGroupId = "group.signipa.sato.zsignapp"
    static let hostScheme = "zsignapp://import"

    // Các UTI coi là "file có thể nhập"
    private let acceptedTypes = ["com.apple.itunes.ipa",
                                 "public.zip-archive",
                                 "public.archive",
                                 "public.data"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedFiles()
    }

    private func inboxURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) else { return nil }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private func handleSharedFiles() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let inbox = inboxURL() else {
            return finish()
        }

        let group = DispatchGroup()
        var savedAny = false

        for item in items {
            for provider in item.attachments ?? [] {
                // chọn UTI phù hợp đầu tiên mà provider hỗ trợ
                guard let typeId = acceptedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) })
                        ?? provider.registeredTypeIdentifiers.first else { continue }

                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                    defer { group.leave() }
                    guard let src = url else { return }
                    // Chỉ nhận đuôi .ipa (hoặc .tipa)
                    let ext = src.pathExtension.lowercased()
                    guard ext == "ipa" || ext == "tipa" || ext.isEmpty else { return }

                    let name = src.lastPathComponent.isEmpty
                        ? "Shared_\(UUID().uuidString).ipa" : src.lastPathComponent
                    let dst = inbox.appendingPathComponent(name)
                    try? FileManager.default.removeItem(at: dst)
                    do {
                        try FileManager.default.copyItem(at: src, to: dst)
                        savedAny = true
                    } catch {
                        // loadFileRepresentation trả về bản sao tạm, copy là đủ
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            if savedAny { self?.openHostApp() }
            self?.finish()
        }
    }

    private func openHostApp() {
        guard let url = URL(string: Self.hostScheme) else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication, app.responds(to: selector) {
                _ = app.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
