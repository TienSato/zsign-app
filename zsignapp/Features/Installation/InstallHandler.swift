//
//  InstallHandler.swift
//  zsignapp
//  Created by Sato on 26/10/25.
//

import Foundation
import UIKit
import NIO
import NIOCore
import NIOPosix
import NIOHTTP1

// MARK: - Điều phối cài đặt

final class InstallHandler {
    private let signedApp: SignedApp
    private let port: UInt16 = UInt16.random(in: 4000...8000)

    private let serverTimeout: TimeInterval = 900   // 15 phút

    init(signedApp: SignedApp) {
        self.signedApp = signedApp
    }

    func install() async throws {
        guard let uuid = signedApp.uuid else { throw InstallError.invalidApp }

        let signedDir = FileManager.default.signedAppDirectory(uuid)
        let contents = try FileManager.default.contentsOfDirectory(
            at: signedDir,
            includingPropertiesForKeys: nil
        )
        guard let ipaFile = contents.first(where: { $0.pathExtension == "ipa" }) else {
            throw InstallError.ipaNotFound
        }

        let server = InstallServer(port: port, ipaPath: ipaFile, app: signedApp)
        try server.start()
        InstallServerPool.shared.keep(server, timeout: serverTimeout)

        let manifestURL = buildManifestURL()
        let opened = await openURL(buildITunesLink(manifestURL: manifestURL))
        guard opened else {
            InstallServerPool.shared.release(server)
            throw InstallError.failedToOpenLink
        }

        InstalledRegistry.record(bundleId: signedApp.identifier, version: signedApp.version)
    }

    private func buildManifestURL() -> URL {
        let host = PlistServerConfig.host
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/plist"
        comps.queryItems = [
            URLQueryItem(name: "bundleid",   value: signedApp.identifier ?? ""),
            URLQueryItem(name: "name",       value: signedApp.name ?? ""),
            URLQueryItem(name: "version",    value: signedApp.version ?? ""),
            URLQueryItem(name: "fetchurl",   value: "http://127.0.0.1:\(port)/app.ipa"),
            URLQueryItem(name: "smallimage", value: "http://127.0.0.1:\(port)/app57x57.png"),
            URLQueryItem(name: "largeimage", value: "http://127.0.0.1:\(port)/app512x512.png"),
            URLQueryItem(name: "t",          value: String(Int(Date().timeIntervalSince1970)))
        ]
        return comps.url ?? URL(string: "https://\(PlistServerConfig.defaultHost)/error")!
    }

    private func buildITunesLink(manifestURL: URL) -> URL {
        var comps = URLComponents()
        comps.scheme = "itms-services"
        comps.path = "/"
        comps.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString)
        ]
        return comps.url!
    }

    @MainActor
    private func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
}

enum InstallError: LocalizedError {
    case invalidApp
    case ipaNotFound
    case failedToOpenLink

    var errorDescription: String? {
        switch self {
        case .invalidApp:        return "Invalid app"
        case .ipaNotFound:       return "IPA file not found. Please re-sign the app."
        case .failedToOpenLink:  return "Failed to open iTunes link"
        }
    }
}
private final class InstallServerPool {
    static let shared = InstallServerPool()

    private let lock = NSLock()
    private var servers: [InstallServer] = []

    func keep(_ server: InstallServer, timeout: TimeInterval) {
        lock.lock()
        servers.append(server)
        lock.unlock()

        server.onInstallationComplete = { [weak self, weak server] in
            guard let server else { return }
            self?.release(server)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self, weak server] in
            guard let server else { return }
            self?.release(server)
        }
    }

    func release(_ server: InstallServer) {
        lock.lock()
        guard let index = servers.firstIndex(where: { $0 === server }) else {
            lock.unlock()
            return
        }
        servers.remove(at: index)
        lock.unlock()

        server.stop()
    }
}

// MARK: - Server HTTP cục bộ

private final class InstallServer {
    private let port: Int
    private let ipaPath: URL
    private let app: SignedApp

    private var channel: Channel?
    private let group: MultiThreadedEventLoopGroup
    private let threadPool: NIOThreadPool
    private let fileIO: NonBlockingFileIO

    private var ipaRequested = false
    private var iconsRequested = 0

    var onInstallationComplete: (() -> Void)?

    init(port: UInt16, ipaPath: URL, app: SignedApp) {
        self.port = Int(port)
        self.ipaPath = ipaPath
        self.app = app

        self.threadPool = NIOThreadPool(numberOfThreads: 2)
        self.threadPool.start()
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.fileIO = NonBlockingFileIO(threadPool: threadPool)
    }

    func start() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self = self else {
                    return channel.eventLoop.makeSucceededFuture(())
                }
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        HTTPHandler(
                            fileIO: self.fileIO,
                            ipaPath: self.ipaPath,
                            app: self.app,
                            onIPARequested: { [weak self] in
                                guard let self = self, !self.ipaRequested else { return }
                                self.ipaRequested = true
                                // Giữ app sống suốt lúc installd kéo file, nếu không
                                // iOS treo app -> server chết -> cài hỏng dở.
                                DispatchQueue.main.async {
                                    BackgroundAudioManager.shared.startBackgroundAudio()
                                }
                                self.checkInstallationComplete()
                            },
                            onIconRequested: { [weak self] in
                                self?.iconsRequested += 1
                                self?.checkInstallationComplete()
                            }
                        )
                    )
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
    }

    func stop() {
        try? channel?.close().wait()
        channel = nil

        let group = self.group
        let threadPool = self.threadPool
        DispatchQueue.global(qos: .utility).async {
            try? group.syncShutdownGracefully()
            try? threadPool.syncShutdownGracefully()

            DispatchQueue.main.async {

                if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                    BackgroundAudioManager.shared.stopBackgroundAudio()
                }
            }
        }
    }

    private func checkInstallationComplete() {
        guard ipaRequested, iconsRequested >= 2 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.onInstallationComplete?()
        }
    }
}

// MARK: - Xử lý request của installd

private final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let fileIO: NonBlockingFileIO
    private let ipaPath: URL
    private let app: SignedApp
    private let onIPARequested: () -> Void
    private let onIconRequested: () -> Void

    private var requestHead: HTTPRequestHead?

    init(
        fileIO: NonBlockingFileIO,
        ipaPath: URL,
        app: SignedApp,
        onIPARequested: @escaping () -> Void,
        onIconRequested: @escaping () -> Void
    ) {
        self.fileIO = fileIO
        self.ipaPath = ipaPath
        self.app = app
        self.onIPARequested = onIPARequested
        self.onIconRequested = onIconRequested
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head

        case .end:
            guard let head = requestHead else { return }

            switch head.uri {
            case "/app.ipa":
                onIPARequested()
                streamIPA(context: context)
            case "/app57x57.png":
                onIconRequested()
                serveIcon(context: context, size: 57)
            case "/app512x512.png":
                onIconRequested()
                serveIcon(context: context, size: 512)
            default:
                send404(context: context)
            }

            requestHead = nil

        case .body:
            break
        }
    }

    private func streamIPA(context: ChannelHandlerContext) {
        let path = ipaPath.path

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int else {
            send404(context: context)
            return
        }

        context.write(wrapOutboundOut(.head(makeHead(
            contentType: "application/octet-stream",
            contentLength: fileSize
        ))), promise: nil)

        let fileHandleFuture = context.eventLoop.makeSucceededFuture(())
            .flatMapThrowing { _ -> NIOFileHandle in try NIOFileHandle(path: path) }

        fileHandleFuture.flatMap { fileHandle -> EventLoopFuture<Void> in
            let region = FileRegion(fileHandle: fileHandle, readerIndex: 0, endIndex: fileSize)
            return self.fileIO.readChunked(
                fileRegion: region,
                chunkSize: 1024 * 1024,
                allocator: context.channel.allocator,
                eventLoop: context.eventLoop
            ) { buffer in
                context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))))
            }.flatMap {
                try? fileHandle.close()
                return context.writeAndFlush(self.wrapOutboundOut(.end(nil)))
            }
        }.whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func serveIcon(context: ChannelHandlerContext, size: CGFloat) {
        let iconData = getIconData(size: size)
        sendOnce(context: context,
                 head: makeHead(contentType: "image/png", contentLength: iconData.count),
                 body: iconData)
    }

    private func send404(context: ChannelHandlerContext) {
        let body = Data("Not Found".utf8)
        var head = makeHead(contentType: "text/plain", contentLength: body.count)
        head.status = .notFound
        sendOnce(context: context, head: head, body: body)
    }

    private func makeHead(contentType: String, contentLength: Int) -> HTTPResponseHead {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: "\(contentLength)")
        headers.add(name: "Connection", value: "close")
        return HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
    }

    private func sendOnce(context: ChannelHandlerContext, head: HTTPResponseHead, body: Data) {
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)

        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    // MARK: Icon

    private func getIconData(size: CGFloat) -> Data {
        guard let iconFileName = app.iconFileName, let appUUID = app.uuid else {
            return placeholderIcon(size: size)
        }

        let customIconURL = FileManager.default.signedAppIconsDirectory(for: appUUID)
            .appendingPathComponent(iconFileName)
        if let image = UIImage(contentsOfFile: customIconURL.path) {
            return png(image, size: size)
        }

        guard let sourceUUID = app.sourceUUID else { return placeholderIcon(size: size) }

        let sourceIconURL = FileManager.default.iconsDirectory(for: sourceUUID)
            .appendingPathComponent(iconFileName)
        guard let image = UIImage(contentsOfFile: sourceIconURL.path) else {
            return placeholderIcon(size: size)
        }
        return png(image, size: size)
    }

    private func png(_ image: UIImage, size: CGFloat) -> Data {
        let target = CGSize(width: size, height: size)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.pngData() ?? placeholderIcon(size: size)
    }

    private func placeholderIcon(size: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: nil
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size, y: size),
                options: []
            )

            let symbolSize = size * 0.5
            let symbolRect = CGRect(
                x: (size - symbolSize) / 2,
                y: (size - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
            if let symbolImage = UIImage(systemName: "app.fill") {
                symbolImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: symbolRect)
            }
        }
        return image.pngData() ?? Data()
    }
}
