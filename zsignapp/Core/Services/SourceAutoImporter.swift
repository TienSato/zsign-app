//
//  SourceAutoImporter.swift
//  zsignapp
//

import Foundation
import AltSourceKit

class SourceAutoImporter: ObservableObject {
    static let shared = SourceAutoImporter()
    
    @Published var isFetching = false
    @Published var statusMessage: String = ""
    
    private let importedSourcesKey = "importedSourceIdentifiers"
    
    private init() {}
    
    func autoImportSources() async {
        guard let apiURL = getAPIURL() else {
            return
        }
        
        await fetchAndImport(from: apiURL)
    }
    
    private func getAPIURL() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "API_SOURCE") as? String
    }
    
    private func getImportedIdentifiers() -> [String] {
        return UserDefaults.standard.stringArray(forKey: importedSourcesKey) ?? []
    }
    
    private func markAsImported(identifier: String) {
        var imported = getImportedIdentifiers()
        if !imported.contains(identifier) {
            imported.append(identifier)
            UserDefaults.standard.set(imported, forKey: importedSourcesKey)
        }
    }
    
    private func fetchAndImport(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        await MainActor.run {
            isFetching = true
            statusMessage = "Checking for new sources..."
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SourceError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw SourceError.fetchFailed(statusCode: httpResponse.statusCode)
            }
            
            let sources = try JSONDecoder().decode([ServerSource].self, from: data)
            
            let importedIdentifiers = getImportedIdentifiers()
            let newSources = sources.filter { !importedIdentifiers.contains($0.identifier) }
            
            if newSources.isEmpty {
                await MainActor.run {
                    isFetching = false
                    statusMessage = ""
                }
                return
            }
            
            await MainActor.run {
                statusMessage = "Importing \(newSources.count) new source(s)..."
            }
            
            for serverSource in newSources {
                do {
                    try await importSource(serverSource)
                    markAsImported(identifier: serverSource.identifier)
                } catch {
                }
            }
            
            await MainActor.run {
                isFetching = false
                statusMessage = newSources.count == 1 ? "1 source imported" : "\(newSources.count) sources imported"
            }
            
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                statusMessage = ""
            }
            
        } catch {
            await MainActor.run {
                isFetching = false
                statusMessage = ""
            }
        }
    }
    
    private func importSource(_ serverSource: ServerSource) async throws {
        guard let url = URL(string: serverSource.url) else {
            throw SourceError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let repository = try JSONDecoder().decode(ASRepository.self, from: data)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                Storage.shared.addSource(
                    url,
                    repository: repository,
                    id: serverSource.identifier
                ) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func resetImportHistory() {
        UserDefaults.standard.removeObject(forKey: importedSourcesKey)
    }
}

struct ServerSource: Codable {
    let url: String
    let name: String
    let identifier: String
}

enum SourceError: LocalizedError {
    case invalidResponse
    case fetchFailed(statusCode: Int)
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .fetchFailed(let code):
            return "Fetch failed with status code: \(code)"
        case .invalidURL:
            return "Invalid source URL"
        }
    }
}
