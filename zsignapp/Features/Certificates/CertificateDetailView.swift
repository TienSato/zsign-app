//
//  CertificateDetailView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import SwiftUI

struct CertificateDetailView: View {
    let certificate: CertificatePair
    
    @State private var provision: Certificate?
    
    var body: some View {
        Form {
            if let provision = provision {
                // Certificate Name & App ID
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(provision.Name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Text("App ID")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(provision.AppIDName)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Status & Features
                Section("Status") {
                    HStack {
                        Text("PPQ Check")
                        Spacer()
                        if let ppqCheck = provision.PPQCheck {
                            Text(ppqCheck ? "✓ Enabled" : "✗ Disabled")
                                .foregroundColor(ppqCheck ? .green : .secondary)
                                .fontWeight(.medium)
                        } else {
                            Text("Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Xcode Managed")
                        Spacer()
                        if let isXcodeManaged = provision.IsXcodeManaged {
                            Text(isXcodeManaged ? "Yes" : "No")
                                .foregroundColor(isXcodeManaged ? .accentColor : .secondary)
                                .fontWeight(.medium)
                        } else {
                            Text("Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("All Devices")
                        Spacer()
                        if let provisionsAll = provision.ProvisionsAllDevices {
                            Text(provisionsAll ? "✓ Yes" : "✗ No")
                                .foregroundColor(provisionsAll ? .green : .secondary)
                                .fontWeight(.medium)
                        } else {
                            Text("Specific Devices")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Team Info
                Section("Team Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Team Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(provision.TeamName)
                            .fontWeight(.medium)
                    }
                    
                    if !provision.TeamIdentifier.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Team ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(provision.TeamIdentifier, id: \.self) { id in
                                Text(id)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    
                    if let appIdPrefix = provision.ApplicationIdentifierPrefix, !appIdPrefix.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("App ID Prefix")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(appIdPrefix, id: \.self) { prefix in
                                Text(prefix)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                
                // Validity
                Section("Validity") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Created")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDateShort(provision.CreationDate))
                                    .fontWeight(.medium)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Expires")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDateShort(provision.ExpirationDate))
                                    .fontWeight(.medium)
                                    .foregroundColor(provision.ExpirationDate < Date() ? .red : .primary)
                            }
                        }
                        
                        // Progress bar for expiration
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 8)
                                    .cornerRadius(4)
                                
                                Rectangle()
                                    .fill(getExpirationColor(provision.CreationDate, provision.ExpirationDate))
                                    .frame(width: geometry.size.width * getExpirationProgress(provision.CreationDate, provision.ExpirationDate), height: 8)
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: 8)
                        
                        HStack {
                            Text(getDaysRemaining(provision.ExpirationDate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(provision.TimeToLive) days total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Platform
                Section("Platform") {
                    HStack {
                        ForEach(provision.Platform, id: \.self) { platform in
                            Text(platform)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Provisioned Devices
                if let devices = provision.ProvisionedDevices, !devices.isEmpty {
                    Section(header: Text("Provisioned Devices (\(devices.count))")) {
                        ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                            HStack {
                                Text("#\(index + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .leading)
                                Text(device)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                
                // Developer Certificates Count
                if let certificates = provision.DeveloperCertificates, !certificates.isEmpty {
                    Section("Developer Certificates") {
                        HStack {
                            Text("Certificate Count")
                            Spacer()
                            Text("\(certificates.count)")
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                // Entitlements
                if let entitlements = provision.Entitlements, !entitlements.isEmpty {
                    Section(header: Text("Entitlements (\(entitlements.count))")) {
                        ForEach(Array(entitlements.keys.sorted()), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(key)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(formatEntitlementValue(entitlements[key]?.value))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Certificate Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadProvision()
        }
    }
    
    private func loadProvision() {
        DispatchQueue.main.async {
            self.provision = Storage.shared.getProvisionDecoded(for: certificate)
        }
    }
    
    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func getDaysRemaining(_ expirationDate: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if expirationDate < now {
            return "Expired"
        }
        
        let components = calendar.dateComponents([.day], from: now, to: expirationDate)
        if let days = components.day {
            return "\(days) days remaining"
        }
        return "Unknown"
    }
    
    private func getExpirationProgress(_ creationDate: Date, _ expirationDate: Date) -> CGFloat {
        let now = Date()
        let total = expirationDate.timeIntervalSince(creationDate)
        let elapsed = now.timeIntervalSince(creationDate)
        
        if elapsed < 0 { return 0 }
        if elapsed > total { return 1 }
        
        return CGFloat(elapsed / total)
    }
    
    private func getExpirationColor(_ creationDate: Date, _ expirationDate: Date) -> Color {
        let progress = getExpirationProgress(creationDate, expirationDate)
        
        if progress >= 0.9 {
            return .red
        } else if progress >= 0.7 {
            return .orange
        } else {
            return .green
        }
    }
    
    private func formatEntitlementValue(_ value: Any?) -> String {
        guard let value = value else { return "nil" }
        
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if let string = value as? String {
            return string
        } else if let number = value as? NSNumber {
            return "\(number)"
        } else if let array = value as? [Any] {
            return array.map { formatEntitlementValue($0) }.joined(separator: ", ")
        } else if let dict = value as? [String: Any] {
            let items = dict.map { "\($0.key): \(formatEntitlementValue($0.value))" }
            return items.joined(separator: "\n")
        }
        
        return "\(value)"
    }
}
