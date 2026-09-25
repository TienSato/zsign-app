//
//  DeviceThemeManager.swift
//  zsignapp
//

import SwiftUI

@MainActor
final class DeviceThemeManager: ObservableObject {
    static let shared = DeviceThemeManager()

    @Published var accent: Color
    @Published var deviceName: String = ""
    @Published var finish: String? = nil

    private let d = UserDefaults.standard
    private let kIdent = "deviceTheme.identifier"
    private let kFinish = "deviceTheme.finish"
    private let kName = "deviceTheme.name"
    private let kFetched = "deviceTheme.fetched"

    private init() {
        let cachedFinish = d.string(forKey: kFinish)
        self.finish = cachedFinish
        self.deviceName = d.string(forKey: kName) ?? ""
        self.accent = DeviceThemeManager.accentColor(forFinish: cachedFinish)
    }

    func bootstrap() {
        let ident = DeviceInfo.modelIdentifier
        let fetched = d.bool(forKey: kFetched)
        let sameDevice = (d.string(forKey: kIdent) == ident)
        if fetched && sameDevice { return }
        Task { await resolve(ident: ident) }
    }

    private struct ZDevice: Codable {
        let finish: String?
        let identifier: String?
        let generation: String?
        let models: [String]?
    }

    private func resolve(ident: String) async {
        guard let url = URL(string: "https://sign.zsign.app/device.json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let list = try? JSONDecoder().decode([ZDevice].self, from: data) else {
            return
        }
        let matches = list.filter { $0.identifier == ident }
        guard !matches.isEmpty else { return }

        let chosen = matches.first

        let fin = chosen?.finish
        let name = chosen?.generation ?? matches.first?.generation ?? ident

        d.set(ident, forKey: kIdent)
        d.set(fin, forKey: kFinish)
        d.set(name, forKey: kName)
        d.set(true, forKey: kFetched)

        self.finish = fin
        self.deviceName = name
        withAnimation(.easeInOut(duration: 0.4)) {
            self.accent = DeviceThemeManager.accentColor(forFinish: fin)
        }
    }

    static func accentColor(forFinish finish: String?) -> Color {
        guard let f = finish?.lowercased(), !f.isEmpty else {
            return Color(red: 0.30, green: 0.52, blue: 0.85) // xanh mặc định dịu
        }
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

        if f.contains("desert") { return rgb(0.78, 0.66, 0.50) }
        if f.contains("natural titanium") || f.contains("natural") { return rgb(0.66, 0.63, 0.60) }
        if f.contains("blue titanium") { return rgb(0.42, 0.50, 0.62) }
        if f.contains("white titanium") { return rgb(0.80, 0.80, 0.82) }
        if f.contains("black titanium") { return rgb(0.36, 0.37, 0.40) }
        if f.contains("titanium") { return rgb(0.62, 0.60, 0.58) }
        if f.contains("sierra blue") { return rgb(0.58, 0.72, 0.85) }
        if f.contains("pacific blue") { return rgb(0.24, 0.46, 0.62) }
        if f.contains("alpine green") { return rgb(0.40, 0.55, 0.48) }
        if f.contains("deep purple") { return rgb(0.45, 0.40, 0.55) }
        if f.contains("rose gold") || f.contains("rose") { return rgb(0.90, 0.68, 0.66) }
        if f.contains("midnight") { return rgb(0.28, 0.33, 0.42) }
        if f.contains("starlight") { return rgb(0.86, 0.83, 0.78) }
        if f.contains("graphite") { return rgb(0.40, 0.40, 0.42) }
        if f.contains("space gray") || f.contains("space grey") { return rgb(0.42, 0.44, 0.48) }
        if f.contains("gold") { return rgb(0.86, 0.74, 0.52) }
        if f.contains("silver") { return rgb(0.72, 0.74, 0.78) }
        if f.contains("red") { return rgb(0.82, 0.36, 0.36) }
        if f.contains("green") { return rgb(0.42, 0.66, 0.50) }
        if f.contains("blue") { return rgb(0.36, 0.56, 0.82) }
        if f.contains("purple") { return rgb(0.58, 0.50, 0.78) }
        if f.contains("pink") { return rgb(0.90, 0.62, 0.72) }
        if f.contains("yellow") { return rgb(0.90, 0.78, 0.42) }
        if f.contains("coral") { return rgb(0.94, 0.55, 0.45) }
        if f.contains("white") { return rgb(0.72, 0.74, 0.78) }
        if f.contains("black") { return rgb(0.38, 0.40, 0.44) }
        return rgb(0.30, 0.52, 0.85)
    }
}
