//
//  DownloadManagerView.swift
//  zsignapp
//
//  Created by Sato on 13/1/26.
//
//  Màn hình tải IPA: nhập link, xem hàng đợi tải, và trình duyệt nhúng để
//  bấm nút tải trên trang web. Giao diện SwiftUI bao quanh dựng bằng bộ thẻ
//  dùng chung (Theme + CardComponents); phần cầu nối WKWebView giữ nguyên.
//

import SwiftUI
import WebKit

// MARK: - Main Download Manager View
struct DownloadManagerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var downloadManager = DownloadManager.shared
    
    @State private var downloadURL: String = ""
    @State private var customFileName: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showWebView = false
    @State private var webViewURL: URL?
    @State private var isProcessing = false
    
    var body: some View {
        NavigationStack {
            CardScreen {
                urlGroup
                if !downloadManager.downloads.isEmpty {
                    downloadsGroup
                }
                startButton
                hintFootnote
            }
            .screenChrome("Download IPA")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(L(errorMessage))
            }
            .sheet(isPresented: $showWebView) {
                if let url = webViewURL {
                    DownloadWebView(
                        url: url,
                        customFileName: customFileName.isEmpty ? nil : customFileName,
                        onItmsServicesDetected: { itmsURL in
                            // ✅ NEW: Handle itms-services from WebView
                            handleItmsServicesLink(itmsURL)
                        },
                        onDismiss: {
                            showWebView = false
                            webViewURL = nil
                        }
                    )
                }
            }
        }
    }

    // MARK: - Ô nhập liên kết

    private var urlGroup: some View {
        CardGroup(L("Download Information"),
                  footnote: L("Paste any link. Browser opens - click download to start.")) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: Theme.Metric.iconBox, alignment: .center)

                TextField("https://example.com/app.ipa", text: $downloadURL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)
            .frame(minHeight: Theme.Metric.rowHeight)

            CardDivider()

            HStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: Theme.Metric.iconBox, alignment: .center)

                TextField("Custom file name (optional)", text: $customFileName)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 12)
            .frame(minHeight: Theme.Metric.rowHeight)
        }
    }

    // MARK: - Hàng đợi đang tải

    private var downloadsGroup: some View {
        CardGroup(L("Active Downloads")) {
            ForEach(Array(downloadManager.downloads.enumerated()), id: \.element.id) { index, download in
                if index > 0 {
                    CardDivider()
                }
                DownloadProgressRow(download: download)
                    .padding(.horizontal, Theme.Metric.cardPadding)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Nút bắt đầu

    private var startButton: some View {
        Button {
            startDownload()
        } label: {
            HStack(spacing: 8) {
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                    Text("Processing...")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(downloadManager.downloads.isEmpty ? L("Start Download") : L("Add to Queue"))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(
                        (downloadURL.isEmpty || !isValidURL(downloadURL) || isProcessing) ? 0.5 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(downloadURL.isEmpty || !isValidURL(downloadURL) || isProcessing)
    }

    // MARK: - Ghi chú cuối màn

    private var hintFootnote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            Text("Supports direct download links")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func isValidURL(_ string: String) -> Bool {
        // ✅ NEW: Support itms-services
        if string.lowercased().hasPrefix("itms-services://") {
            return true
        }
        guard let url = URL(string: string) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
    
    private func startDownload() {
        let urlString = downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // ✅ NEW: Check itms-services
        if urlString.lowercased().hasPrefix("itms-services://") {
            handleItmsServicesLink(urlString)
            return
        }
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Please enter a valid URL"
            showError = true
            return
        }
        
        if url.absoluteString.lowercased().hasSuffix(".ipa") {
            let fileName = customFileName.isEmpty ? url.lastPathComponent : customFileName
            let finalName = fileName.hasSuffix(".ipa") ? fileName : "\(fileName).ipa"
            _ = downloadManager.startDownload(url: url, id: "dl_\(UUID().uuidString)", appName: finalName)
            downloadURL = ""
            customFileName = ""
        } else {
            webViewURL = url
            showWebView = true
            downloadURL = ""
        }
    }
    
    // ✅ NEW: Handle itms-services links
    private func handleItmsServicesLink(_ urlString: String) {
        isProcessing = true
        showWebView = false
        
        Task {
            do {
                
                // Extract plist URL
                guard let plistURL = extractPlistURL(from: urlString) else {
                    throw NSError(domain: "DownloadManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot extract plist URL"])
                }
                
                
                // Download plist
                let (data, _) = try await URLSession.shared.data(from: plistURL)
                
                guard let plistString = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "DownloadManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot decode plist"])
                }
                
                
                // Extract IPA URL
                guard let ipaURL = extractIPAURL(from: plistString) else {
                    throw NSError(domain: "DownloadManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot find IPA URL in plist"])
                }
                
                
                // Start download
                await MainActor.run {
                    let fileName = customFileName.isEmpty ? ipaURL.lastPathComponent : customFileName
                    let finalName = fileName.hasSuffix(".ipa") ? fileName : "\(fileName).ipa"
                    
                    
                    _ = downloadManager.startDownload(url: ipaURL, id: "dl_\(UUID().uuidString)", appName: finalName)
                    
                    downloadURL = ""
                    customFileName = ""
                    isProcessing = false
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to process itms-services link: \(error.localizedDescription)"
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func extractPlistURL(from itmsLink: String) -> URL? {
        guard let urlRange = itmsLink.range(of: "url=") else {
            return nil
        }
        
        let urlParam = String(itmsLink[urlRange.upperBound...])
        
        guard let decodedString = urlParam.removingPercentEncoding else {
            return nil
        }
        
        return URL(string: decodedString)
    }
    
    private func extractIPAURL(from plistContent: String) -> URL? {
        
        // Method 1: Regex
        let pattern = "<string>(https?://[^<]+\\.ipa[^<]*)</string>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: plistContent, options: [], range: NSRange(plistContent.startIndex..., in: plistContent)),
           let range = Range(match.range(at: 1), in: plistContent) {
            let urlString = String(plistContent[range])
            return URL(string: urlString)
        }
        
        // Method 2: Line search
        let lines = plistContent.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().contains(".ipa") && (trimmed.contains("http://") || trimmed.contains("https://")) {
                if let startIndex = trimmed.range(of: ">")?.upperBound,
                   let endIndex = trimmed.range(of: "</", options: .backwards)?.lowerBound {
                    let urlString = String(trimmed[startIndex..<endIndex])
                    if let url = URL(string: urlString), urlString.lowercased().contains(".ipa") {
                        return url
                    }
                }
            }
        }
        
        // Method 3: Broad search
        let urlPattern = "(https?://[^\\s<>\"']+\\.ipa[^\\s<>\"']*)"
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: plistContent, options: [], range: NSRange(plistContent.startIndex..., in: plistContent)),
           let range = Range(match.range(at: 1), in: plistContent) {
            let urlString = String(plistContent[range])
            return URL(string: urlString)
        }
        
        return nil
    }
}

// MARK: - Download WebView
struct DownloadWebView: View {
    let url: URL
    let customFileName: String?
    let onItmsServicesDetected: (String) -> Void  // ✅ NEW
    let onDismiss: () -> Void
    
    @StateObject private var coordinator = WebViewCoordinator()
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var pageTitle = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { coordinator.goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(canGoBack ? Color.accentColor : Theme.ink3)
                    }
                    .disabled(!canGoBack)
                    
                    Button { coordinator.goForward() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(canGoForward ? Color.accentColor : Theme.ink3)
                    }
                    .disabled(!canGoForward)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pageTitle.isEmpty ? L("Loading...") : pageTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(coordinator.currentURL?.host ?? url.host ?? "")
                            .font(.caption2)
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button { coordinator.reload() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .padding()
                .background(Theme.card)
                .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .bottom)
                
                SimpleWebView(
                    url: url,
                    coordinator: coordinator,
                    customFileName: customFileName,
                    onStateChange: { back, forward, loading, title in
                        canGoBack = back
                        canGoForward = forward
                        isLoading = loading
                        pageTitle = title
                    },
                    onItmsServicesDetected: onItmsServicesDetected,  // ✅ NEW
                    onDownloadStarted: {
                        onDismiss()
                    }
                )
                
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                    Text("Click download - progress will show in the list above")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }
                .padding()
                .background(Theme.cardAlt)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}

// MARK: - WebView Coordinator
class WebViewCoordinator: NSObject, ObservableObject {
    var webView: WKWebView?
    @Published var currentURL: URL?
    
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

// MARK: - Simple WebView
struct SimpleWebView: UIViewRepresentable {
    let url: URL
    let coordinator: WebViewCoordinator
    let customFileName: String?
    let onStateChange: (Bool, Bool, Bool, String) -> Void
    let onItmsServicesDetected: (String) -> Void  // ✅ NEW
    let onDownloadStarted: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            customFileName: customFileName,
            onStateChange: onStateChange,
            onItmsServicesDetected: onItmsServicesDetected,  // ✅ NEW
            onDownloadStarted: onDownloadStarted
        )
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        coordinator.webView = webView
        context.coordinator.webView = webView
        
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {}
    
    @available(iOS 14.5, *)
    class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate, WKUIDelegate {
        let customFileName: String?
        let onStateChange: (Bool, Bool, Bool, String) -> Void
        let onItmsServicesDetected: (String) -> Void  // ✅ NEW
        let onDownloadStarted: () -> Void
        weak var webView: WKWebView?
        
        init(customFileName: String?, onStateChange: @escaping (Bool, Bool, Bool, String) -> Void, onItmsServicesDetected: @escaping (String) -> Void, onDownloadStarted: @escaping () -> Void) {
            self.customFileName = customFileName
            self.onStateChange = onStateChange
            self.onItmsServicesDetected = onItmsServicesDetected
            self.onDownloadStarted = onDownloadStarted
        }
        
        // MARK: - WKUIDelegate
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString
                
                
                // ✅ NEW: Check itms-services
                if urlString.lowercased().hasPrefix("itms-services://") {
                    DispatchQueue.main.async {
                        self.onItmsServicesDetected(urlString)
                    }
                    return nil
                }
                
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(webView)
        }
        
        // ✅ NEW: Check itms-services in navigation
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            let urlString = url.absoluteString
            
            // Check itms-services
            if urlString.lowercased().hasPrefix("itms-services://") {
                DispatchQueue.main.async {
                    self.onItmsServicesDetected(urlString)
                }
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            
            guard let response = navigationResponse.response as? HTTPURLResponse,
                  let url = response.url else {
                decisionHandler(.allow)
                return
            }
            
            let type = response.value(forHTTPHeaderField: "Content-Type") ?? ""
            let disp = response.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            
            let isDownloadable = type.contains("application/") ||
                                type.contains("octet-stream") ||
                                type.contains("binary") ||
                                type.contains("zip") ||
                                disp.contains("attachment") ||
                                url.absoluteString.lowercased().hasSuffix(".ipa")
            
            if isDownloadable {
                
                if #available(iOS 14.5, *) {
                    decisionHandler(.download)
                    return
                } else {
                    decisionHandler(.cancel)
                    return
                }
            }
            
            decisionHandler(.allow)
        }
        
        // MARK: - WKDownloadDelegate
        
        @available(iOS 14.5, *)
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }
        
        @available(iOS 14.5, *)
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            
            
            guard let url = response.url else {
                completionHandler(nil)
                return
            }
            
            
            DispatchQueue.main.async {
                let name = self.customFileName ?? suggestedFilename
                let finalName = name.hasSuffix(".ipa") ? name : "\(name).ipa"
                
                
                _ = DownloadManager.shared.startDownload(
                    url: url,
                    id: "dl_\(UUID().uuidString)",
                    appName: finalName
                )
                
                self.onDownloadStarted()
            }
            
            completionHandler(nil)
        }
        
        @available(iOS 14.5, *)
        func downloadDidFinish(_ download: WKDownload) {
        }
        
        @available(iOS 14.5, *)
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        }
        
        private func updateState(_ webView: WKWebView) {
            DispatchQueue.main.async {
                self.onStateChange(
                    webView.canGoBack,
                    webView.canGoForward,
                    webView.isLoading,
                    webView.title ?? ""
                )
            }
        }
    }
}

// MARK: - Progress Row
struct DownloadProgressRow: View {
    @ObservedObject var download: Download
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: Theme.Metric.iconBox, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.appName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(L(statusText))
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 8)
                if download.status == .downloading {
                    Button { DownloadManager.shared.cancelDownload(download) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            if download.status == .downloading || download.status == .importing {
                ProgressView(value: download.progress).tint(.accentColor)
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: download.bytesDownloaded, countStyle: .file))
                        .font(.caption2).foregroundStyle(Theme.ink3)
                    if download.totalBytes > 0 {
                        Text("/ \(ByteCountFormatter.string(fromByteCount: download.totalBytes, countStyle: .file))")
                            .font(.caption2).foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    Text("\(Int(download.progress * 100))%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
    }
    
    private var iconName: String { download.status.iconName }
    private var iconColor: Color { download.status.iconColor }
    private var statusText: String { download.status.statusText }
}

// MARK: - List Row
struct DownloadListRow: View {
    @ObservedObject var download: Download
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.appName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(L(statusText))
                        .font(.caption2)
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 8)
                if download.status == .downloading || download.status == .importing {
                    Text("\(Int(download.progress * 100))%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(iconColor)
                }
            }
            if download.status == .downloading || download.status == .importing {
                ProgressView(value: download.progress).tint(iconColor)
            }
        }
    }
    
    private var iconName: String { download.status.iconName }
    private var iconColor: Color { download.status.iconColor }
    private var statusText: String { download.status.statusText }
}

// MARK: - Hien thi trang thai tai xuong (dung chung cho moi row)
extension Download.DownloadStatus {
    var iconName: String {
        switch self {
        case .downloading: return "arrow.down.circle.fill"
        case .importing: return "arrow.down.doc.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .downloading: return .accentColor
        case .importing: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return Theme.ink3
        }
    }

    var statusText: String {
        switch self {
        case .downloading: return "Downloading..."
        case .importing: return "Importing..."
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
