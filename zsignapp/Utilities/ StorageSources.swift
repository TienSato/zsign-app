//
//  Storage+Sources+cert.swift
//  zsignapp
//  Created by Sato on 26/10/25.
import CoreData
import AltSourceKit
import Foundation

extension Storage {
    func fetchSources() -> [AltSource] {
        let request: NSFetchRequest<AltSource> = AltSource.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
    func addSource(
        _ url: URL,
        name: String? = "Unknown",
        identifier: String,
        iconURL: URL? = nil,
        deferSave: Bool = false,
        completion: @escaping (Error?) -> Void
    ) {
        if sourceExists(identifier) {
            completion(NSError(domain: "Storage", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Source already exists"
            ]))
            return
        }
        let newSource = AltSource(context: context)
        newSource.name = name
        newSource.date = Date()
        newSource.identifier = identifier
        newSource.sourceURL = url
        newSource.iconURL = iconURL
        do {
            if !deferSave {
                try context.save()
            }
            completion(nil)
        } catch {
            completion(error)
        }
    }
    func addSource(
        _ url: URL,
        repository: ASRepository,
        id: String = "",
        deferSave: Bool = false,
        completion: @escaping (Error?) -> Void
    ) {
        addSource(
            url,
            name: repository.name,
            identifier: !id.isEmpty ? id : (repository.id ?? url.absoluteString),
            iconURL: repository.currentIconURL,
            deferSave: deferSave,
            completion: completion
        )
    }
    func addSources(
        repos: [URL: ASRepository],
        completion: @escaping (Error?) -> Void
    ) {
        for (url, repo) in repos {
            addSource(
                url,
                repository: repo,
                deferSave: true,
                completion: { _ in }
            )
        }
        
        saveContext()
        completion(nil)
    }
    func deleteSource(_ source: AltSource) {
        context.delete(source)
        saveContext()
    }
    func sourceExists(_ identifier: String) -> Bool {
        let request: NSFetchRequest<AltSource> = AltSource.fetchRequest()
        request.predicate = NSPredicate(format: "identifier == %@", identifier)
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            return false
        }
    }
}
