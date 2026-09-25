//
//  PlistServerSettingsView.swift
//  zsignapp
//
//  Chọn máy chủ sinh manifest plist, thêm máy chủ riêng, và kiểm tra máy chủ
//  có trả lời đúng không.
//

import SwiftUI

struct PlistServerSettingsView: View {
    @ObservedObject private var store = PlistServerStore.shared
    @State private var showAdd = false
    @State private var testing = false
    @State private var testResult: TestResult?

    var body: some View {
        CardScreen {
            serverGroup
            testGroup
            noteGroup
        }
        .screenChrome("Plist Server")
        .sheet(isPresented: $showAdd) {
            AddPlistServerView()
        }
    }

    // MARK: - Danh sách máy chủ

    private var serverGroup: some View {
        CardGroup(L("Server in use"),
                  footnote: L("Only the manifest is fetched from this server. The IPA never leaves your device.")) {
            ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                if index > 0 { CardDivider() }
                serverRow(server)
            }

            CardDivider()

            Button { showAdd = true } label: {
                CardRow(icon: "plus.circle.fill", title: L("Add Server"))
            }
            .buttonStyle(.plain)
        }
    }

    private func serverRow(_ server: PlistServer) -> some View {
        let isSelected = server.id == store.selected.id

        return Button {
            store.select(server)
            testResult = nil
        } label: {
            CardRow(icon: isSelected ? "checkmark.circle.fill" : "circle",
                    title: server.name,
                    subtitle: server.displayURL,
                    iconTint: isSelected ? Color.accentColor : Theme.ink3) {
                if !server.isBuiltIn {
                    Button {
                        store.remove(server)
                        testResult = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.footnote)
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kiểm tra

    private var testGroup: some View {
        CardGroup {
            Button {
                Task { await runTest() }
            } label: {
                CardRow(icon: "checkmark.seal.fill",
                        title: L("Test this server"),
                        subtitle: store.selected.host) {
                    if testing { ProgressView() }
                }
            }
            .buttonStyle(.plain)
            .disabled(testing)

            if let testResult {
                CardDivider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                        .foregroundStyle(testResult.ok ? Color.green : Color.red)
                        .frame(width: Theme.Metric.iconBox)

                    Text(testResult.message)
                        .font(.caption)
                        .foregroundStyle(testResult.ok ? Theme.ink2 : Color.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Theme.Metric.cardPadding)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Hướng dẫn tự dựng máy chủ

    private var noteGroup: some View {
        CardGroup(L("Run your own server")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The server only turns your parameters into a manifest plist. It never receives the IPA — the manifest points back to 127.0.0.1 inside your device.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)

                Text("It is a single JavaScript file deployed free on Cloudflare Pages. The repository below has the code and a step-by-step guide.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.top, 14)
            .padding(.bottom, 4)

            CardDivider(inset: Theme.Metric.cardPadding)

            Link(destination: URL(string: "https://github.com/TienSato/zsign-pages")!) {
                CardRow(icon: "chevron.left.forwardslash.chevron.right",
                        title: L("Source code & guide"),
                        subtitle: "github.com/TienSato/zsign-pages") {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Gọi thử máy chủ

    private struct TestResult {
        let ok: Bool
        let message: String
    }

    private func runTest() async {
        testing = true
        testResult = nil
        defer { testing = false }

        let host = store.selected.host
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/plist"
        comps.queryItems = [
            URLQueryItem(name: "bundleid", value: "com.zsign.selftest"),
            URLQueryItem(name: "name", value: "zSign"),
            URLQueryItem(name: "version", value: "1.0"),
            URLQueryItem(name: "fetchurl", value: "http://127.0.0.1:1/app.ipa"),
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
        ]

        guard let url = comps.url else {
            testResult = TestResult(ok: false, message: L("Could not build the URL. Check the host name."))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""

            guard code == 200 else {
                testResult = TestResult(
                    ok: false,
                    message: "HTTP \(code)\n\(body.isEmpty ? L("Empty response") : body)"
                )
                return
            }

            // Manifest hợp lệ phải là plist và có khoá items.
            guard body.contains("<plist"), body.contains("items") else {
                testResult = TestResult(
                    ok: false,
                    message: L("Server answered HTTP 200 but the content is not a manifest plist:") + "\n" + body
                )
                return
            }

            testResult = TestResult(
                ok: true,
                message: String(format: L("OK — %@ returned a valid manifest (%d bytes)."), host, data.count)
            )
        } catch {
            testResult = TestResult(ok: false, message: error.localizedDescription)
        }
    }
}

// MARK: - Thêm máy chủ

struct AddPlistServerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlistServerStore.shared

    @State private var name = ""
    @State private var host = ""
    @State private var error: String?

    private var cleanHost: String { PlistServerConfig.normalize(host) }
    private var canSave: Bool { PlistServerConfig.isValid(host) }

    var body: some View {
        NavigationStack {
            CardScreen {
                CardGroup(L("Server address"),
                          footnote: L("Enter the domain only. https:// and /plist are added automatically.")) {
                    field(L("Name (optional)"), text: $name, placeholder: L("My server"))
                    CardDivider(inset: Theme.Metric.cardPadding)
                    field(L("Domain"), text: $host, placeholder: "abc.pages.dev")

                    if !cleanHost.isEmpty {
                        CardDivider(inset: Theme.Metric.cardPadding)
                        HStack {
                            Text("https://\(cleanHost)/plist")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(canSave ? Theme.ink2 : Color.red)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.Metric.cardPadding)
                        .padding(.vertical, 10)
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                FilledButton(title: L("Add Server"), icon: "plus") {
                    save()
                }
                .opacity(canSave ? 1 : 0.5)
                .disabled(!canSave)
            }
            .screenChrome("Add Server")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
    }

    private func save() {
        if store.add(name: name, host: host) {
            dismiss()
        } else {
            error = L("This server already exists, or the domain is not valid.")
        }
    }
}
