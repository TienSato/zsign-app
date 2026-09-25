//
//  X509Certificate.swift
//  zsignapp
//

import Foundation
import CryptoKit

struct X509Certificate {
    var commonName: String?
    var organization: String?
    var organizationalUnit: String?
    var teamID: String?
    var country: String?
    var serial: String?
    var sha1: String?
    var notBefore: Date?
    var notAfter: Date?
    var issuer: String?

    var isExpired: Bool {
        guard let notAfter else { return false }
        return notAfter < Date()
    }

    // MARK: - Đọc

    init?(der: Data) {
        let b = [UInt8](der)

        sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()

        guard let cert = Self.readTLV(b, 0), cert.isConstructed else { return nil }
        let top = Self.children(b, cert.value)
        guard let tbs = top.first, tbs.isConstructed else { return nil }

        var f = Self.children(b, tbs.value)
        if let first = f.first, first.tag == 0xA0 { f.removeFirst() }
        guard f.count >= 5 else { return nil }

        var serialBytes = Array(b[f[0].value])
        if serialBytes.first == 0x00 { serialBytes.removeFirst() }
        serial = serialBytes.map { String(format: "%02X", $0) }.joined()

        issuer = Self.parseName(b, f[2].value)[Self.oidCN]

        let validity = Self.children(b, f[3].value)
        if validity.count >= 2 {
            notBefore = Self.parseTime(b, validity[0])
            notAfter  = Self.parseTime(b, validity[1])
        }

        let subject = Self.parseName(b, f[4].value)
        commonName         = subject[Self.oidCN]
        organization       = subject[Self.oidO]
        organizationalUnit = subject[Self.oidOU]
        country            = subject[Self.oidC]
        teamID             = subject[Self.oidUID]
    }

    // MARK: - ASN.1 / DER

    private static let oidCN  = "2.5.4.3"
    private static let oidC   = "2.5.4.6"
    private static let oidO   = "2.5.4.10"
    private static let oidOU  = "2.5.4.11"
    private static let oidUID = "0.9.2342.19200300.100.1.1"

    private struct TLV {
        let tag: UInt8
        let value: Range<Int>
        let end: Int
        var isConstructed: Bool { tag & 0x20 != 0 }
    }

    private static func readTLV(_ b: [UInt8], _ start: Int) -> TLV? {
        var i = start
        guard i < b.count else { return nil }
        let tag = b[i]
        i += 1
        guard i < b.count else { return nil }

        var length = 0
        let lengthByte = b[i]
        i += 1
        if lengthByte & 0x80 == 0 {
            length = Int(lengthByte)
        } else {
            let count = Int(lengthByte & 0x7F)
            guard count > 0, count <= 4, i + count <= b.count else { return nil }
            for _ in 0..<count {
                length = (length << 8) | Int(b[i])
                i += 1
            }
        }

        guard length >= 0, i + length <= b.count else { return nil }
        return TLV(tag: tag, value: i..<(i + length), end: i + length)
    }

    private static func children(_ b: [UInt8], _ range: Range<Int>) -> [TLV] {
        var result: [TLV] = []
        var i = range.lowerBound
        while i < range.upperBound, let tlv = readTLV(b, i) {
            result.append(tlv)
            guard tlv.end > i else { break }
            i = tlv.end
        }
        return result
    }

    private static func parseName(_ b: [UInt8], _ range: Range<Int>) -> [String: String] {
        var out: [String: String] = [:]
        for rdn in children(b, range) where rdn.isConstructed {
            for pair in children(b, rdn.value) where pair.isConstructed {
                let parts = children(b, pair.value)
                guard parts.count >= 2, parts[0].tag == 0x06 else { continue }
                let oid = oidString(b, parts[0].value)
                guard out[oid] == nil else { continue }
                let raw = Array(b[parts[1].value])
                out[oid] = String(bytes: raw, encoding: .utf8)
                    ?? String(bytes: raw, encoding: .isoLatin1)
            }
        }
        return out
    }

    private static func oidString(_ b: [UInt8], _ range: Range<Int>) -> String {
        var parts: [String] = []
        var i = range.lowerBound
        guard i < range.upperBound else { return "" }

        let first = Int(b[i])
        i += 1
        parts.append("\(first / 40)")
        parts.append("\(first % 40)")

        var value = 0
        while i < range.upperBound {
            let byte = b[i]
            i += 1
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                parts.append("\(value)")
                value = 0
            }
        }
        return parts.joined(separator: ".")
    }

    private static func parseTime(_ b: [UInt8], _ tlv: TLV) -> Date? {
        guard let text = String(bytes: b[tlv.value], encoding: .ascii) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        let patterns = tlv.tag == 0x18
            ? ["yyyyMMddHHmmss'Z'", "yyyyMMddHHmm'Z'", "yyyyMMddHHmmss.SSS'Z'"]
            : ["yyMMddHHmmss'Z'", "yyMMddHHmm'Z'"]

        for pattern in patterns {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
