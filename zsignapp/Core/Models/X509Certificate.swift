//
//  X509Certificate.swift
//  zsignapp
//
//  Đọc chứng chỉ X.509 (DER) nhúng trong mobileprovision, khoá
//  DeveloperCertificates. iOS KHÔNG có SecCertificateCopyValues (chỉ macOS mới
//  có) nên phải tự bóc ASN.1/DER để lấy Common Name, Organization, OU, Team ID,
//  Country, Serial, hạn dùng và Issuer.
//
//  Cấu trúc theo RFC 5280:
//      Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
//      TBSCertificate ::= SEQUENCE {
//          [0] version OPTIONAL, serialNumber, signature,
//          issuer Name, validity Validity, subject Name, ... }
//      Name ::= SEQUENCE OF SET OF SEQUENCE { OID, value }
//

import Foundation
import CryptoKit

struct X509Certificate {
    var commonName: String?
    var organization: String?
    var organizationalUnit: String?
    var teamID: String?          // OID UID — Apple để Team ID ở đây
    var country: String?
    var serial: String?          // hex hoa
    var sha1: String?            // hex hoa của toàn bộ DER
    var notBefore: Date?
    var notAfter: Date?
    var issuer: String?          // Common Name của bên cấp

    var isExpired: Bool {
        guard let notAfter else { return false }
        return notAfter < Date()
    }

    // MARK: - Đọc

    init?(der: Data) {
        let b = [UInt8](der)

        // SHA-1 tính trên toàn bộ DER, không phụ thuộc việc bóc tách bên dưới.
        sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()

        guard let cert = Self.readTLV(b, 0), cert.isConstructed else { return nil }
        let top = Self.children(b, cert.value)
        guard let tbs = top.first, tbs.isConstructed else { return nil }

        var f = Self.children(b, tbs.value)
        // [0] version là tuỳ chọn; có thì bỏ qua để các trường sau về đúng chỗ.
        if let first = f.first, first.tag == 0xA0 { f.removeFirst() }
        guard f.count >= 5 else { return nil }

        // serialNumber: INTEGER, bỏ byte 0x00 đệm dấu ở đầu nếu có.
        var serialBytes = Array(b[f[0].value])
        if serialBytes.first == 0x00 { serialBytes.removeFirst() }
        serial = serialBytes.map { String(format: "%02X", $0) }.joined()

        // f[1] = thuật toán ký (bỏ qua), f[2] = issuer, f[3] = validity, f[4] = subject
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

    /// Một khối Tag-Length-Value, mô tả bằng chỉ số tuyệt đối trong mảng gốc.
    private struct TLV {
        let tag: UInt8
        let value: Range<Int>
        let end: Int                 // vị trí ngay sau khối này
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
            guard tlv.end > i else { break }   // chặn vòng lặp vô tận nếu DER hỏng
            i = tlv.end
        }
        return result
    }

    /// Name -> [OID: giá trị]. Trùng OID thì giữ giá trị đầu tiên.
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

        // Byte đầu gói 2 thành phần: first * 40 + second
        let first = Int(b[i])
        i += 1
        parts.append("\(first / 40)")
        parts.append("\(first % 40)")

        // Các thành phần sau: base-128, bit cao = còn byte tiếp theo
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

    /// UTCTime (tag 0x17, YY) hoặc GeneralizedTime (tag 0x18, YYYY).
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
