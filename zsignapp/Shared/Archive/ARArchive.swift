//
//  ARArchive.swift
//  zsignapp
//
//  AR archive reader for .deb files
//
import Foundation

struct ARFile {
    var name: String
    var content: Data
}
class AR {
    private var data: Data
    
    init(with url: URL) {
        self.data = (try? Data(contentsOf: url)) ?? Data()
    }
    func extract() async throws -> [ARFile] {
        // Check AR magic
        let magic = data.subdata(in: 0..<8)
        let expectedMagic: [UInt8] = [0x21, 0x3c, 0x61, 0x72, 0x63, 0x68, 0x3e, 0x0a]
        
        guard Array(magic) == expectedMagic else {
            throw ARError.invalidArchive
        }
        var files: [ARFile] = []
        var offset = 8
        while offset < data.count {
            // Read file header (60 bytes)
            guard offset + 60 <= data.count else { break }
            let header = data.subdata(in: offset..<offset+60)
            // Parse file name (16 bytes)
            let nameData = header.subdata(in: 0..<16)
            let name = String(data: nameData, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            // Parse file size (10 bytes at offset 48)
            let sizeData = header.subdata(in: 48..<58)
            let sizeString = String(data: sizeData, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces) ?? "0"
            let size = Int(sizeString) ?? 0
            guard size > 0 else { break }
            // Read file content
            let contentStart = offset + 60
            let contentEnd = min(contentStart + size, data.count)
            let content = data.subdata(in: contentStart..<contentEnd)
            files.append(ARFile(name: name, content: content))
            // Move to next file (align to 2 bytes)
            offset = contentEnd
            if offset % 2 != 0 {
                offset += 1
            }
        }
        
        return files
    }
}

enum ARError: Error {
    case invalidArchive
}
