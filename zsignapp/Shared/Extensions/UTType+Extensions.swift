//
//  UTType+Extensions.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import UniformTypeIdentifiers

extension UTType {
    static var ipa: UTType {
        UTType(filenameExtension: "ipa", conformingTo: .data)!
    }
    
    static var tipa: UTType {
        UTType(filenameExtension: "tipa", conformingTo: .data)!
    }
    
    static var p12: UTType {
        UTType(filenameExtension: "p12", conformingTo: .data)!
    }
    
    static var mobileProvision: UTType {
        UTType(filenameExtension: "mobileprovision", conformingTo: .data)!
    }
    
    // Thêm type cho .zsigncert
    static var zsignCert: UTType {
        UTType(filenameExtension: "zsigncert", conformingTo: .archive)!
    }
    
    // Thêm type cho .zip
    static var zip: UTType {
        UTType(filenameExtension: "zip", conformingTo: .archive)!
    }
}
