//
//  IOSVersionHelper.swift
//  zsignapp
//
//  iOS version detection helper
//

import UIKit

class IOSVersionHelper {
    static func getCurrentIOSMajorVersion() -> Int {
        let version = UIDevice.current.systemVersion
        return Int(version.split(separator: ".").first ?? "0") ?? 0
    }
    
    static func isIOS26OrLater() -> Bool {
        return getCurrentIOSMajorVersion() >= 26
    }
    
    static func shouldEnableElleKitByDefault() -> Bool {
        return false  
    }
}
