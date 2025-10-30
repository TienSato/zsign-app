//
//  SimpleServer.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import Foundation
import NIO
import NIOCore
import NIOPosix
import NIOHTTP1
import UIKit

class SimpleServer {
    private let port: Int
    private var channel: Channel?
    private let group: MultiThreadedEventLoopGroup
    private let ipaPath: URL
    private let app: SignedApp
    
    var onInstallationDetected: (() -> Void)?
    var onInstallationComplete: (() -> Void)?
    
    private var ipaRequested = false
    private var iconsRequested = 0
    
    private let fileIO: NonBlockingFileIO
    private let threadPool: NIOThreadPool
    
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
                                if self?.ipaRequested == false {
                                    self?.ipaRequested = true
                                    
                                    DispatchQueue.main.async {
                                        self?.onInstallationDetected?()
                                        BackgroundAudioManager.shared.startBackgroundAudio()
                                    }
                                    
                                    self?.checkInstallationComplete()
                                }
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
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            try? self?.group.syncShutdownGracefully()
            try? self?.threadPool.syncShutdownGracefully()
            
            DispatchQueue.main.async {
                self?.channel = nil
                
                if !UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                    BackgroundAudioManager.shared.stopBackgroundAudio()
                }
            }
        }
    }
    
    private func checkInstallationComplete() {
        if ipaRequested && iconsRequested >= 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.onInstallationComplete?()
            }
        }
    }
}

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
        let part = unwrapInboundIn(data)
        
        switch part {
        case .head(let head):
            requestHead = head
            
        case .end:
            guard let head = requestHead else { return }
            
            if head.uri == "/app.ipa" {
                onIPARequested()
                streamIPA(context: context)
            } else if head.uri == "/app57x57.png" {
                onIconRequested()
                serveIcon(context: context, size: 57)
            } else if head.uri == "/app512x512.png" {
                onIconRequested()
                serveIcon(context: context, size: 512)
            } else {
                send404(context: context)
            }
            
            requestHead = nil
            
        case .body:
            break
        }
    }
    
    private func streamIPA(context: ChannelHandlerContext) {
        let path = ipaPath.path
        
        let fileSize: Int
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = attributes[.size] as? Int else {
                send404(context: context)
                return
            }
            fileSize = size
        } catch {
            send404(context: context)
            return
        }
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/octet-stream")
        headers.add(name: "Content-Length", value: "\(fileSize)")
        headers.add(name: "Connection", value: "close")
        
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .ok,
            headers: headers
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        let fileHandleFuture = context.eventLoop.makeSucceededFuture(()).flatMapThrowing { _ -> NIOFileHandle in
            return try NIOFileHandle(path: path)
        }
        
        fileHandleFuture.flatMap { fileHandle -> EventLoopFuture<Void> in
            let region = FileRegion(fileHandle: fileHandle, readerIndex: 0, endIndex: fileSize)
            
            return self.fileIO.readChunked(
                fileRegion: region,
                chunkSize: 1024 * 1024,
                allocator: context.channel.allocator,
                eventLoop: context.eventLoop
            ) { buffer in
                return context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))))
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
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "image/png")
        headers.add(name: "Content-Length", value: "\(iconData.count)")
        headers.add(name: "Connection", value: "close")
        
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .ok,
            headers: headers
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        var buffer = context.channel.allocator.buffer(capacity: iconData.count)
        buffer.writeBytes(iconData)
        
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
    
    private func getIconData(size: CGFloat) -> Data {
        guard let iconFileName = app.iconFileName,
              let appUUID = app.uuid else {
            return createPlaceholderIcon(size: size)
        }
        
        let customIconURL = FileManager.default.signedAppIconsDirectory(for: appUUID)
            .appendingPathComponent(iconFileName)
        
        if FileManager.default.fileExists(atPath: customIconURL.path),
           let customImage = UIImage(contentsOfFile: customIconURL.path) {
            let resizedImage = resizeImage(customImage, to: CGSize(width: size, height: size))
            return resizedImage.pngData() ?? createPlaceholderIcon(size: size)
        }
        
        guard let sourceUUID = app.sourceUUID else {
            return createPlaceholderIcon(size: size)
        }
        
        let sourceIconURL = FileManager.default.iconsDirectory(for: sourceUUID)
            .appendingPathComponent(iconFileName)
        
        guard FileManager.default.fileExists(atPath: sourceIconURL.path),
              let originalImage = UIImage(contentsOfFile: sourceIconURL.path) else {
            return createPlaceholderIcon(size: size)
        }
        
        let resizedImage = resizeImage(originalImage, to: CGSize(width: size, height: size))
        return resizedImage.pngData() ?? createPlaceholderIcon(size: size)
    }
    
    private func send404(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain")
        headers.add(name: "Content-Length", value: "9")
        
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .notFound,
            headers: headers
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        var buffer = context.channel.allocator.buffer(capacity: 9)
        buffer.writeString("Not Found")
        
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
    
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    private func createPlaceholderIcon(size: CGFloat) -> Data {
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
                let tintedImage = symbolImage.withTintColor(.white, renderingMode: .alwaysOriginal)
                tintedImage.draw(in: symbolRect)
            }
        }
        return image.pngData() ?? Data()
    }
}
