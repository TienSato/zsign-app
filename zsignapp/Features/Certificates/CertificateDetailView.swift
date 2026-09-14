//
//  CertificateDetailView.swift
//  zsignapp
//
//  Chi tiết đầy đủ của một cặp chứng chỉ:
//    1. Chứng chỉ (P12)     - bóc từ X.509 DER trong mobileprovision
//    2. Hồ sơ cấp quyền     - đọc từ plist của mobileprovision
//    3. Quyền (entitlements) - gom nhóm, có tên dễ hiểu (EntitlementCatalog)
//    4. UDID thiết bị       - danh sách máy được cấp phép
//

import SwiftUI
import UIKit

struct CertificateDetailView: View {
    let certificate: CertificatePair

    @State private var provision: Certificate?
    @State private var x509: X509Certificate?

    /// Lấy locale từ môi trường (gốc app đã set theo ngôn ngữ người dùng chọn)
    /// thay vì đụng vào LocalizationManager.shared — nó là @MainActor.
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            if let provision {
                p12Section
                profileSection(provision)
                entitlementSections(provision)
                deviceSection(provision)
            } else {
                HStack {
                    Spacer()
                    ProgressView().padding()
                    Spacer()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Certificate Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    // MARK: - 1. Chứng chỉ (P12)

    @ViewBuilder
    private var p12Section: some View {
        Section {
            if let x509 {
                CertRow("Common Name", x509.commonName)
                CertRow("Organization", x509.organization)
                CertRow("OU", x509.organizationalUnit)
                CertRow("UID / Team ID", x509.teamID)
                CertRow("Country", x509.country)
                CertRow("Serial", x509.serial, mono: true)
                CertRow("SHA-1", x509.sha1, mono: true, copyable: true)
                CertRow("Not Before", format(x509.notBefore))
                CertRow("Not After", format(x509.notAfter),
                        valueColor: x509.isExpired ? .red : .primary)
                CertRow("Issuer", x509.issuer)
                CertRow("OCSP",
                        certificate.revoked ? L("Revoked") : L("Valid (OCSP verified)"),
                        valueColor: certificate.revoked ? .red : .green)
            } else {
                Text("Could not read the X.509 certificate inside this profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader(L("Certificate (P12)"), icon: "lock.doc", color: .blue)
        }
    }

    // MARK: - 2. Hồ sơ cấp quyền

    @ViewBuilder
    private func profileSection(_ p: Certificate) -> some View {
        Section {
            CertRow("Name", p.Name)
            CertRow("App ID Name", p.AppIDName)
            CertRow("Bundle ID", bundleID(p), mono: true, copyable: true)
            CertRow("Team", p.TeamName)
            CertRow("Team ID", p.TeamIdentifier.joined(separator: ", "))
            CertRow("Type", profileType(p))
            CertRow("UUID", p.UUID, mono: true, copyable: true)
            CertRow("Version", "\(p.Version)")
            CertRow("Creation", format(p.CreationDate))
            CertRow("Expiration", format(p.ExpirationDate),
                    valueColor: p.ExpirationDate < Date() ? .red : .primary)
            CertRow("Devices", "\(p.ProvisionedDevices?.count ?? 0)")
            CertRow("Platform", p.Platform.joined(separator: ", "))
        } header: {
            SectionHeader(L("Provisioning Profile"), icon: "doc.badge.gearshape", color: .red)
        }
    }

    // MARK: - 3. Quyền

    @ViewBuilder
    private func entitlementSections(_ p: Certificate) -> some View {
        let granted = p.Entitlements ?? [:]

        ForEach(EntitlementCategory.allCases, id: \.rawValue) { category in
            let items = entitlements(in: category, granted: granted)
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        EntitlementRow(info: item.info, value: item.value)
                    }
                } header: {
                    SectionHeader(category.title, icon: category.icon, color: .secondary)
                }
            }
        }
    }

    /// Ghép danh mục có sẵn với những khoá lạ chỉ xuất hiện trong hồ sơ này,
    /// để không quyền nào bị giấu đi.
    private func entitlements(
        in category: EntitlementCategory,
        granted: [String: AnyCodable]
    ) -> [EntitlementItem] {
        var keys = EntitlementCatalog.keys(in: category)
        if category == .other {
            keys.append(contentsOf: granted.keys.filter { !EntitlementCatalog.isKnown($0) }.sorted())
        }
        return keys.map { key in
            EntitlementItem(info: EntitlementCatalog.info(for: key),
                            value: granted[key].map { describe($0.value) })
        }
    }

    // MARK: - 4. UDID thiết bị

    @ViewBuilder
    private func deviceSection(_ p: Certificate) -> some View {
        if let devices = p.ProvisionedDevices, !devices.isEmpty {
            Section {
                ForEach(Array(devices.enumerated()), id: \.offset) { index, udid in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .leading)
                        Text(udid)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        CopyButton(udid)
                    }
                }
            } header: {
                SectionHeader(L("Provisioned Devices"), icon: "iphone",
                              color: .red, badge: "\(devices.count)")
            }
        }
    }

    // MARK: - Nạp dữ liệu

    private func load() {
        guard provision == nil else { return }
        let decoded = Storage.shared.getProvisionDecoded(for: certificate)
        provision = decoded
        if let der = decoded?.DeveloperCertificates?.first {
            x509 = X509Certificate(der: der)
        }
    }

    // MARK: - Tiện ích

    private func format(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// application-identifier là "TEAMID.com.vi.du" — bỏ tiền tố đội cho dễ đọc.
    private func bundleID(_ p: Certificate) -> String? {
        guard let full = p.Entitlements?["application-identifier"]?.value as? String else { return nil }
        for prefix in (p.ApplicationIdentifierPrefix ?? []) + p.TeamIdentifier
        where full.hasPrefix(prefix + ".") {
            return String(full.dropFirst(prefix.count + 1))
        }
        return full
    }

    private func profileType(_ p: Certificate) -> String {
        if p.ProvisionsAllDevices == true { return L("Enterprise") }
        if (p.Entitlements?["get-task-allow"]?.value as? Bool) == true { return L("Development") }
        if let devices = p.ProvisionedDevices, !devices.isEmpty { return L("Ad Hoc") }
        return L("App Store")
    }

    private func describe(_ value: Any) -> String {
        switch value {
        case let bool as Bool:        return bool ? "true" : "false"
        case let string as String:    return string
        case let number as NSNumber:  return "\(number)"
        case let array as [Any]:      return array.map(describe).joined(separator: ", ")
        case let dict as [String: Any]:
            return dict.sorted { $0.key < $1.key }
                .map { "\($0.key): \(describe($0.value))" }
                .joined(separator: "\n")
        case is NSNull:               return "null"
        default:                      return "\(value)"
        }
    }
}

// MARK: - Thành phần dùng lại trong màn hình này

/// Một dòng quyền: thông tin từ danh mục + giá trị thực tế (nil = chưa cấp).
private struct EntitlementItem: Identifiable {
    let info: EntitlementInfo
    let value: String?
    var id: String { info.key }
}

private struct SectionHeader: View {
    let title: String
    let icon: String
    var color: Color = .secondary
    var badge: String? = nil

    init(_ title: String, icon: String, color: Color = .secondary, badge: String? = nil) {
        self.title = title
        self.icon = icon
        self.color = color
        self.badge = badge
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
            if let badge {
                Text("(\(badge))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

private struct CertRow: View {
    let label: LocalizedStringKey
    let value: String?
    var mono: Bool = false
    var copyable: Bool = false
    var valueColor: Color = .primary

    init(_ label: LocalizedStringKey, _ value: String?,
         mono: Bool = false, copyable: Bool = false, valueColor: Color = .primary) {
        self.label = label
        self.value = value
        self.mono = mono
        self.copyable = copyable
        self.valueColor = valueColor
    }

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 112, alignment: .leading)

                Text(value)
                    .font(mono ? .system(.footnote, design: .monospaced) : .subheadline)
                    .foregroundStyle(valueColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if copyable {
                    CopyButton(value)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct EntitlementRow: View {
    let info: EntitlementInfo
    /// nil nghĩa là hồ sơ này KHÔNG có quyền đó.
    let value: String?

    private var isGranted: Bool { value != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? Color.green : Color.secondary.opacity(0.5))
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.subheadline)

                if !info.detail.isEmpty {
                    Text(info.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.75))
                        .textSelection(.enabled)
                }

                Text(info.key)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CopyButton: View {
    let value: String
    @State private var copied = false

    init(_ value: String) { self.value = value }

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.footnote)
                .foregroundStyle(copied ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
