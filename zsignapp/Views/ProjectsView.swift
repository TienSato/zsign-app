//
//  ProjectsView.swift
//  zsignapp
//
//  Workspace rút gọn: quản lý project (IPA gốc + danh sách dylib) và ký lại + cài đè.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Danh sách project
struct ProjectsListView: View {
    @ObservedObject private var store = ProjectStore.shared
    @State private var showNewPicker = false

    var body: some View {
        List {
            if store.projects.isEmpty {
                Text("No projects yet. Tap + to create one from an imported app.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(store.projects) { p in
                NavigationLink {
                    ProjectDetailView(project: p)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.displayName).font(.headline)
                        Text("\(p.bundleId) · v\(p.version)")
                            .font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 10) {
                            Label("\(p.detectedTweakCount + p.dylibs.count) tweak", systemImage: "puzzlepiece.extension")
                            if let d = p.lastSignedAt {
                                Text(L("signed:") + " \(d.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                        .font(.caption2).foregroundColor(.secondary)
                        projectStatusBadge(p)
                    }
                }
            }
            .onDelete { idx in
                for i in idx { store.delete(store.projects[i]) }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            Button { showNewPicker = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showNewPicker) {
            NewProjectPicker()
        }
    }

    @ViewBuilder
    private func projectStatusBadge(_ p: SignProject) -> some View {
        switch InstalledRegistry.status(bundleId: p.effectiveBundleId, availableVersion: p.version) {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundColor(.green)
        case .updateAvailable:
            Label("Needs re-signing (new build)", systemImage: "arrow.up.circle.fill")
                .font(.caption2).foregroundColor(.orange)
        case .notInstalled:
            Label("Not installed", systemImage: "circle")
                .font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Chọn app gốc để tạo project
struct NewProjectPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ProjectStore.shared
    @State private var apps: [ImportedApp] = []

    var body: some View {
        NavigationView {
            List {
                if apps.isEmpty {
                    Text("No imported apps. Import an IPA from the Apps/Store tab first.")
                        .foregroundColor(.secondary)
                }
                ForEach(apps, id: \.uuid) { app in
                    Button {
                        _ = store.addProject(from: app)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name ?? "Unknown").foregroundColor(.primary)
                            Text("\(app.identifier ?? "") · v\(app.version ?? "")")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select source app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { apps = Storage.shared.fetchApps() }
        }
    }
}

// MARK: - Chi tiết project
struct ProjectDetailView: View {
    @State var project: SignProject
    @ObservedObject private var store = ProjectStore.shared
    @State private var certificates: [CertificatePair] = []
    @State private var showImporter = false
    @State private var isSigning = false
    @State private var status = ""
    @State private var sourceApp: ImportedApp?
    @State private var showChangeSource = false
    @State private var pickedIconItem: PhotosPickerItem?

    private var dylibTypes: [UTType] {
        var t: [UTType] = []
        if let d = UTType(filenameExtension: "dylib") { t.append(d) }
        if let d = UTType(filenameExtension: "deb") { t.append(d) }
        return t.isEmpty ? [.data] : t
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: project.displayName)
                LabeledContent("Bundle ID", value: project.bundleId)
                LabeledContent("Version", value: project.version)
                Button {
                    showChangeSource = true
                } label: {
                    Label("Replace source IPA with a newer build", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: { Text("Source App") } footer: {
                Text("Upgrading an app: import the new IPA in the Apps tab, then swap the source here. Tweaks and certificate are KEPT, only the source changes.")
                    .font(.caption)
            }

            Section {
                Picker("Certificate", selection: Binding(
                    get: { project.certificateUUID ?? "" },
                    set: { newVal in
                        project.certificateUUID = newVal.isEmpty ? nil : newVal
                        store.update(project)
                    }
                )) {
                    Text("(default)").tag("")
                    ForEach(certificates, id: \.uuid) { c in
                        Text(c.nickname ?? (c.uuid ?? "Cert")).tag(c.uuid ?? "")
                    }
                }
            } header: { Text("Signing Certificate") }

            // MARK: - Cấu hình ký RIÊNG project
            Section {
                TextField("Name (blank = keep original)", text: Binding(
                    get: { project.customName }, set: { project.customName = $0; store.update(project) }))
                TextField("Bundle ID (blank = keep original)", text: Binding(
                    get: { project.customBundleID }, set: { project.customBundleID = $0; store.update(project) }))
                    .autocapitalization(.none).autocorrectionDisabled()
                TextField("Version (blank = keep original)", text: Binding(
                    get: { project.customVersion }, set: { project.customVersion = $0; store.update(project) }))
                Toggle("Remove Watch app", isOn: Binding(
                    get: { project.removeWatch }, set: { project.removeWatch = $0; store.update(project) }))
                Toggle("Remove URL scheme", isOn: Binding(
                    get: { project.removeURLScheme }, set: { project.removeURLScheme = $0; store.update(project) }))
                Toggle("Remove provisioning", isOn: Binding(
                    get: { project.removeProvision }, set: { project.removeProvision = $0; store.update(project) }))
            } header: { Text("Per-project Signing") } footer: {
                Text("Changing the Bundle ID makes it a DIFFERENT APP (no in-place update). Leave blank to keep the original.")
                    .font(.caption)
            }

            // MARK: - Icon riêng
            Section {
                HStack(spacing: 12) {
                    if let img = store.iconImage(for: project) {
                        Image(uiImage: img).resizable().frame(width: 48, height: 48).cornerRadius(10)
                    } else {
                        Image(systemName: "app.dashed").font(.system(size: 38))
                            .foregroundColor(.secondary).frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.hasCustomIcon ? "Custom Icon" : "Use original icon").font(.subheadline)
                        PhotosPicker("Choose image...", selection: $pickedIconItem, matching: .images).font(.caption)
                    }
                    Spacer()
                    if project.hasCustomIcon {
                        Button(role: .destructive) { project = store.removeIcon(for: project) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            } header: { Text("Custom Icon") }

            Section {
                if project.dylibs.isEmpty {
                    Text("No tweaks yet. Tap Add dylib/.deb.")
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(project.dylibs) { d in
                    Toggle(isOn: Binding(
                        get: { d.enabled },
                        set: { v in toggleEnabled(d, v) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.fileName).font(.subheadline)
                            Text(d.weak ? "weak inject" : "normal inject")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx { project = store.removeDylib(from: project, dylib: project.dylibs[i]) }
                }
                .onMove { from, to in
                    project.dylibs.move(fromOffsets: from, toOffset: to)
                    store.update(project)
                }
                Button { showImporter = true } label: {
                    Label("Add dylib/.deb", systemImage: "plus.circle")
                }
            } header: { Text("Your Added Tweaks (dylib/.deb)") } footer: {
                Text("Enabled dylibs are INJECTED into the source IPA when signing. Adding a file with the same name overwrites it.")
                    .font(.caption)
            }

            // MARK: - Tweak/mod SẴN CÓ trong app (tự quét)
            Section {
                if let app = sourceApp {
                    NavigationLink {
                        AppTweaksManagerView(app: app, disabledTweaks: Binding(
                            get: { project.disabledTweaks },
                            set: { project.disabledTweaks = $0; store.update(project) }
                        ))
                    } label: {
                        HStack {
                            Label("Manage Built-in Tweaks", systemImage: "wrench.and.screwdriver")
                            Spacer()
                            if !project.disabledTweaks.isEmpty {
                                Text("\(project.disabledTweaks.count) " + L("off"))
                                    .font(.caption).foregroundColor(.orange)
                            }
                        }
                    }
                } else {
                    Text("Source app not found for scanning (removed from the Apps tab?).")
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: { Text("Tweaks Already in the App") } footer: {
                Text("Automatically scans dylibs/frameworks/bundles already in the modded app. Turning one OFF REMOVES it on re-sign; ON keeps it.")
                    .font(.caption)
            }

            Section {
                Button {
                    Task { await signAndInstall() }
                } label: {
                    HStack {
                        Spacer()
                        if isSigning { ProgressView().padding(.trailing, 6) }
                        Text(isSigning ? "Processing..." : "Sign & Install (update)").bold()
                        Spacer()
                    }
                }
                .disabled(isSigning)

                if !status.isEmpty {
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            } footer: {
                Text("Re-signs from the source IPA and installs over it: same bundle id, so iOS updates in place and keeps app data.")
                    .font(.caption)
            }
        }
        .navigationTitle(project.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear {
            certificates = Storage.shared.fetchCertificates()
            sourceApp = Storage.shared.fetchApps().first { $0.uuid == project.importedAppUUID }
            store.refreshDetectedCount(project.id)
            if project.certificateUUID == nil,
               let def = certificates.first(where: { $0.isDefault }) {
                project.certificateUUID = def.uuid
                store.update(project)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: dylibTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { project = store.addDylib(to: project, from: url) }
            }
        }
        .sheet(isPresented: $showChangeSource) {
            ChangeSourceSheet(currentBundleId: project.bundleId) { app in
                applyNewSource(app)
            }
        }
        .onChange(of: pickedIconItem) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data)?.resizeToSquare() {
                    await MainActor.run { project = store.setIcon(img, for: project) }
                }
            }
        }
    }

    private func applyNewSource(_ app: ImportedApp) {
        if let bid = app.identifier, !bid.isEmpty, bid != project.bundleId {
            status = String(format: L("Different bundle id (%@) — installing over will NOT apply; iOS treats it as a different app."), bid)
        } else {
            status = String(format: L("Source replaced → v%@. Tap Sign & Install to update."), app.version ?? "?")
        }
        project.importedAppUUID = app.uuid ?? ""
        project.displayName = app.name ?? project.displayName
        project.bundleId = app.identifier ?? project.bundleId
        project.version = app.version ?? project.version
        store.update(project)
        sourceApp = app
        store.refreshDetectedCount(project.id)
    }

    private func toggleEnabled(_ d: ProjectDylib, _ enabled: Bool) {
        if let i = project.dylibs.firstIndex(where: { $0.id == d.id }) {
            project.dylibs[i].enabled = enabled
            store.update(project)
        }
    }

    @MainActor
    private func signAndInstall() async {
        guard let app = Storage.shared.fetchApps().first(where: { $0.uuid == project.importedAppUUID }) else {
            status = L("Source app not found (it may have been removed from the Apps tab).")
            return
        }
        let certs = Storage.shared.fetchCertificates()
        guard let cert = certs.first(where: { $0.uuid == project.certificateUUID })
                ?? certs.first(where: { $0.isDefault })
                ?? certs.first else {
            status = L("No certificates. Add a certificate first.")
            return
        }

        isSigning = true
        status = L("Signing...")
        do {
            var options = SigningOptionsManager.shared.options
            options.injectionFiles = store.enabledDylibURLs(for: project)
            if !project.customName.isEmpty { options.appName = project.customName }
            if !project.customBundleID.isEmpty { options.appIdentifier = project.customBundleID }
            if !project.customVersion.isEmpty { options.appVersion = project.customVersion }
            if project.removeWatch { options.removeWatchPlaceholder = true }
            if project.removeURLScheme { options.removeURLScheme = true }
            if project.removeProvision { options.removeProvisioning = true }
            let projectIcon = store.iconImage(for: project)

            let handler = SigningHandler(sourceApp: app, certificate: cert, options: options, customIcon: projectIcon, disabledTweaks: project.disabledTweaks)
            handler.stepProgressCallback = { s in
                Task { @MainActor in self.status = s }
            }
            try await handler.performFullSigning()

            status = L("Installing...")
            let signed = Storage.shared.fetchSignedApps()
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                .first { $0.identifier == project.effectiveBundleId }

            if let signed = signed {
                let installer = InstallHandler(signedApp: signed)
                try await installer.install()
                status = L("Install request sent — confirm on your device to update.")
                project.lastSignedAt = Date()
                store.update(project)
            } else {
                status = L("Signed, but no signed build was found to install.")
            }
        } catch {
            status = L("Error:") + " \(error.localizedDescription)"
        }
        isSigning = false
    }
}

// MARK: - Đổi IPA gốc (lên phiên bản mới) — giữ tweak/cert
struct ChangeSourceSheet: View {
    let currentBundleId: String
    let onPick: (ImportedApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [ImportedApp] = []

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Choose an imported IPA as the NEW SOURCE. Prefer the SAME bundle id with a newer version (green check = same bundle).")
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(apps, id: \.uuid) { app in
                    Button {
                        onPick(app); dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name ?? "Unknown").foregroundColor(.primary)
                                Text("\(app.identifier ?? "") · v\(app.version ?? "")")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if app.identifier == currentBundleId {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Replace Source IPA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { apps = Storage.shared.fetchApps() }
        }
    }
}
