//
//  CertificateReader-models.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//
import Foundation

class CertificateReader {
    let file: URL?
    var decoded: Certificate?
    
    init(_ file: URL?) {
        self.file = file
        self.decoded = readAndDecode()
    }
    private func readAndDecode() -> Certificate? {
        guard let file = file else { return nil }
        
        do {
            let fileData = try Data(contentsOf: file)
            // Find XML start
            guard let xmlRange = fileData.range(of: Data("<?xml".utf8)) else {
                return nil
            }
            let xmlData = fileData.subdata(in: xmlRange.lowerBound..<fileData.endIndex)
            let decoder = PropertyListDecoder()
            let certificate = try decoder.decode(Certificate.self, from: xmlData)
            return certificate
        } catch {
            return nil
        }
    }
}
