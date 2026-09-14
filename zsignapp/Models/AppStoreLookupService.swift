//
//  AppStoreLookupService.swift
//  zsignv2
//

import Foundation

class AppStoreLookupService {
    static let shared = AppStoreLookupService()
    
    private init() {}
    
    // MARK: - Lookup App by Bundle ID
    func lookupApp(bundleId: String) async -> AppStoreApp? {
        let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=us&entity=software"
        
        guard let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedUrlString) else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            
            guard let result = response.results.first else {
                return nil
            }
            
            return result
        } catch {
            print("AppStore lookup error: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - App Store Models
struct AppStoreLookupResponse: Codable {
    let resultCount: Int
    let results: [AppStoreApp]
}

struct AppStoreApp: Codable {
    let trackId: Int
    let trackName: String
    let bundleId: String
    let version: String
    let artistName: String
    let primaryGenreName: String
    let description: String
    let releaseNotes: String?
    let artworkUrl60: String
    let artworkUrl100: String
    let artworkUrl512: String
    let screenshotUrls: [String]
    let ipadScreenshotUrls: [String]
    let appletvScreenshotUrls: [String]
    let averageUserRating: Double?
    let userRatingCount: Int?
    let contentAdvisoryRating: String?
    let minimumOsVersion: String
    let languageCodesISO2A: [String]
    let fileSizeBytes: String
    let trackViewUrl: String
    let currentVersionReleaseDate: String
    
    var iconURL: URL? {
        return URL(string: artworkUrl512)
    }
    
    var allScreenshots: [URL] {
        var urls: [URL] = []
        urls.append(contentsOf: screenshotUrls.compactMap { URL(string: $0) })
        urls.append(contentsOf: ipadScreenshotUrls.compactMap { URL(string: $0) })
        return urls
    }
}
