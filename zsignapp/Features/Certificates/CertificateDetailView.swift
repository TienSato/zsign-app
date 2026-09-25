//
//  CertificateDetailView.swift
//  zsignapp
//

import SwiftUI
import UIKit

struct CertificateDetailView: View {
    let certificate: CertificatePair

    @State private var provision: Certificate?
    @State private var x509: X509Certificate?

    
    @Environment(\.locale) private var locale

    var body: some View {
        CardScreen {
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
        .screenChrome("Certificate Details")
        .onAppear(perform: load)
    }


    @ViewBuilder
    private var p12Section: some View {
        DetailCard(header: SectionHeader(L("Certificate (P12)"),
                                         icon: "lock.doc",
                                         color: .accentColor)) {
            if let x509 {
                fieldRows([
                    CertField(label: "Common Name", value: x509.commonName),
                    CertField(label: "Organization", value: x509.organization),
                    CertField(label: "OU", value: x509.organizationalUnit),
                    CertField(label: "UID / Team ID", value: x509.teamID),
                    CertField(label: "Country", value: x509.country),
                    CertField(label: "Serial", value: x509.serial, mono: true),
                    CertField(label: "SHA-1", value: x509.sha1, mono: true, copyable: true),
                    CertField(label: "Not Before", value: format(x509.notBefore)),
                    CertField(label: "Not After", value: format(x509.notAfter),
                              valueColor: x509.isExpired ? .red : Theme.ink),
                    CertField(label: "Issuer", value: x509.issuer),
                    CertField(label: "OCSP",
                              value: certificate.revoked ? L("Revoked") : L("Valid (OCSP verified)"),
                              valueColor: certificate.revoked ? .red : .green)
                ])
            } else {
                Text("Could not read the X.509 certificate inside this profile.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metric.cardPadding)
                    .padding(.vertical, 14)
            }
        }
    }


    @ViewBuilder
    private func profileSection(_ p: Certificate) -> some View {
        DetailCard(header: SectionHeader(L("Provisioning Profile"),
                                         icon: "doc.badge.gearshape",
                                         color: .accentColor)) {
            fieldRows([
                CertField(label: "Name", value: p.Name),
                CertField(label: "App ID Name", value: p.AppIDName),
                CertField(label: "Bundle ID", value: bundleID(p), mono: true, copyable: true),
                CertField(label: "Team", value: p.TeamName),
                CertField(label: "Team ID", value: p.TeamIdentifier.joined(separator: ", ")),
                CertField(label: "Type", value: profileType(p)),
                CertField(label: "UUID", value: p.UUID, mono: true, copyable: true),
                CertField(label: "Version", value: "\(p.Version)"),
                CertField(label: "Creation", value: format(p.CreationDate)),
                CertField(label: "Expiration", value: format(p.ExpirationDate),
                          valueColor: p.ExpirationDate < Date() ? .red : Theme.ink),
                CertField(label: "Devices", value: "\(p.ProvisionedDevices?.count ?? 0)"),
                CertField(label: "Platform", value: p.Platform.joined(separator: ", "))
            ])
        }
    }

   
    @ViewBuilder
    private func fieldRows(_ fields: [CertField]) -> some View {
        let shown = fields.filter { !($0.value ?? "").isEmpty }

        ForEach(Array(shown.enumerated()), id: \.element.id) { index, field in
            if index > 0 {
                CardDivider(inset: Theme.Metric.cardPadding)
            }
            CertRow(field.label,
                    field.value,
                    mono: field.mono,
                    copyable: field.copyable,
                    valueColor: field.valueColor)
        }
    }


    @ViewBuilder
    private func entitlementSections(_ p: Certificate) -> some View {
        let granted = p.Entitlements ?? [:]

        ForEach(EntitlementCategory.allCases, id: \.rawValue) { category in
            let items = entitlements(in: category, granted: granted)
            if !items.isEmpty {
                DetailCard(header: SectionHeader(category.title,
                                                 icon: category.icon,
                                                 color: Theme.ink2),
                           isLazy: true) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            CardDivider()
                        }
                        EntitlementRow(info: item.info, value: item.value)
                    }
                }
            }
        }
    }

   
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


    @ViewBuilder
    private func deviceSection(_ p: Certificate) -> some View {
        if let devices = p.ProvisionedDevices, !devices.isEmpty {
            DetailCard(header: SectionHeader(L("Provisioned Devices"),
                                             icon: "iphone",
                                             color: .accentColor,
                                             badge: "\(devices.count)"),
                       isLazy: true) {
                ForEach(Array(devices.enumerated()), id: \.offset) { index, udid in
                    if index > 0 {
                        CardDivider(inset: Theme.Metric.cardPadding)
                    }
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(Theme.ink3)
                            .frame(width: 20, alignment: .leading)
                        Text(udid)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        CopyButton(udid)
                    }
                    .padding(.horizontal, Theme.Metric.cardPadding)
                    .padding(.vertical, 10)
                }
            }
        }
    }


    private func load() {
        guard provision == nil else { return }
        let decoded = Storage.shared.getProvisionDecoded(for: certificate)
        provision = decoded
        if let der = decoded?.DeveloperCertificates?.first {
            x509 = X509Certificate(der: der)
        }
    }


    private func format(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

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


private struct DetailCard<Content: View>: View {
    let header: SectionHeader
    
    var isLazy: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .padding(.horizontal, 4)

            Group {
                if isLazy {
                    LazyVStack(spacing: 0) { content }
                } else {
                    VStack(spacing: 0) { content }
                }
            }
            .cardStyle(padding: 0)
        }
    }
}

private struct CertField: Identifiable {
    let id = UUID()
    let label: LocalizedStringKey
    let value: String?
    var mono: Bool = false
    var copyable: Bool = false
    var valueColor: Color = Theme.ink
}

private struct EntitlementItem: Identifiable {
    let info: EntitlementInfo
    let value: String?
    var id: String { info.key }
}

private struct SectionHeader: View {
    let title: String
    let icon: String
    var color: Color = Theme.ink2
    var badge: String? = nil

    init(_ title: String, icon: String, color: Color = Theme.ink2, badge: String? = nil) {
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
                .foregroundStyle(Theme.ink2)
            if let badge {
                Text("(\(badge))")
                    .foregroundStyle(Theme.ink3)
            }
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
    }
}

private struct CertRow: View {
    let label: LocalizedStringKey
    let value: String?
    var mono: Bool = false
    var copyable: Bool = false
    var valueColor: Color = Theme.ink

    init(_ label: LocalizedStringKey, _ value: String?,
         mono: Bool = false, copyable: Bool = false, valueColor: Color = Theme.ink) {
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
                    .foregroundStyle(Theme.ink2)
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
            .padding(.horizontal, Theme.Metric.cardPadding)
            .padding(.vertical, 10)
        }
    }
}

private struct EntitlementRow: View {
    let info: EntitlementInfo
    let value: String?

    private var isGranted: Bool { value != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? Color.green : Theme.ink3)
                .font(.system(size: Theme.Metric.iconSize))
                .frame(width: Theme.Metric.iconBox, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)

                if !info.detail.isEmpty {
                    Text(info.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }

                Text(info.key)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 11)
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
                .foregroundStyle(copied ? Color.green : Theme.ink3)
        }
        .buttonStyle(.plain)
    }
}
