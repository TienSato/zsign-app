//
//  ParallelZipArchiver.swift
//  zsignapp
//
//  Nén IPA SONG SONG (raw deflate, đa nhân) rồi tự dựng ZIP — mô phỏng
//  cơ chế PrepareRawDeflateBatch của LCSign. Có Zip64. Nếu bất kỳ lỗi nào,
//  caller sẽ fallback về thư viện Zip cũ (đã kiểm chứng) => không bao giờ hỏng.
//

import Foundation
import Compression

enum ParallelZipError: Error { case tooLargeForMemory, ioError }

enum ParallelZip {
    /// Bật/tắt nhanh. Đặt false để luôn dùng thư viện Zip cũ.
    static var enabled = true

    // Ngưỡng: file lớn hơn -> STORE + stream (chống ngốn RAM). Nhỏ hơn -> deflate song song trong RAM.
    private static let bigFileThreshold: Int = 64 * 1024 * 1024      // 64MB
    // Tổng dữ liệu small-file giữ trong RAM tối đa; vượt -> ném lỗi để fallback.
    private static let smallBudget: Int = 800 * 1024 * 1024          // 800MB

    // MARK: CRC32 (đa thức chuẩn 0xEDB88320), hỗ trợ cộng dồn theo chunk
    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            return c
        }
    }()
    struct CRC32 {
        private var crc: UInt32 = 0xFFFFFFFF
        mutating func update(_ buf: UnsafeRawBufferPointer) {
            for b in buf.bindMemory(to: UInt8.self) {
                crc = ParallelZip.crcTable[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
            }
        }
        mutating func update(_ data: Data) { data.withUnsafeBytes { update($0) } }
        var value: UInt32 { crc ^ 0xFFFFFFFF }
    }
    static func crc32(_ data: Data) -> UInt32 { var c = CRC32(); c.update(data); return c.value }

    // MARK: raw DEFLATE bằng Compression framework (COMPRESSION_ZLIB = raw deflate, RFC1951)
    private static func deflate(_ input: Data) -> Data? {
        if input.isEmpty { return nil }
        let cap = input.count + 64
        var dst = Data(count: cap)
        let n = dst.withUnsafeMutableBytes { d -> Int in
            input.withUnsafeBytes { s -> Int in
                compression_encode_buffer(
                    d.bindMemory(to: UInt8.self).baseAddress!, cap,
                    s.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        if n == 0 || n >= input.count { return nil }   // không nén được / không nhỏ hơn -> STORE
        return dst.prefix(n)
    }

    // MARK: LE writers
    private struct Buf {
        var d = Data()
        mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        mutating func raw(_ x: Data) { d.append(x) }
        mutating func raw(_ x: [UInt8]) { d.append(contentsOf: x) }
    }

    private struct Item { let name: String; let url: URL?; let isDir: Bool; let size: Int }
    private struct Prepared { var method: UInt16 = 0; var crc: UInt32 = 0; var comp: Data = Data(); var uncomp: UInt64 = 0 }
    private struct Central { let name: [UInt8]; let method: UInt16; let crc: UInt32; let comp: UInt64; let uncomp: UInt64; let offset: UInt64; let isDir: Bool }

    // MARK: entry point
    static func archive(payloadFolder: URL, to outputURL: URL,
                        storeOnly: Bool = false,
                        progress: ((Double) -> Void)? = nil) throws {
        let fm = FileManager.default
        let base = payloadFolder.deletingLastPathComponent()

        // 1) Liệt kê item theo thứ tự ổn định (thư mục + file)
        var items: [Item] = []
        func rel(_ u: URL) -> String {
            var p = u.path
            let bp = base.path + "/"
            if p.hasPrefix(bp) { p.removeFirst(bp.count) }
            return p
        }
        items.append(Item(name: rel(payloadFolder) + "/", url: nil, isDir: true, size: 0))
        if let en = fm.enumerator(at: payloadFolder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: []) {
            for case let u as URL in en {
                let vals = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDir = vals?.isDirectory ?? false
                if isDir {
                    items.append(Item(name: rel(u) + "/", url: u, isDir: true, size: 0))
                } else {
                    let sz = vals?.fileSize ?? 0
                    items.append(Item(name: rel(u), url: u, isDir: false, size: sz))
                }
            }
        }

        // 2) Nén SONG SONG các file nhỏ (giữ trong RAM), kiểm ngân sách
        let smallIdx = items.indices.filter { !items[$0].isDir && items[$0].size <= bigFileThreshold }
        let totalSmall = smallIdx.reduce(0) { $0 + items[$1].size }
        if totalSmall > smallBudget { throw ParallelZipError.tooLargeForMemory }

        var prepared = [Int: Prepared]()
        let lock = NSLock()
        var prepError: Error?
        DispatchQueue.concurrentPerform(iterations: smallIdx.count) { k in
            if prepError != nil { return }
            let idx = smallIdx[k]
            guard let u = items[idx].url, let data = try? Data(contentsOf: u, options: .mappedIfSafe) else {
                lock.lock(); prepError = ParallelZipError.ioError; lock.unlock(); return
            }
            var p = Prepared()
            p.uncomp = UInt64(data.count)
            p.crc = crc32(data)
            if !storeOnly, let z = deflate(data) {
                p.method = 8; p.comp = z
            } else {
                p.method = 0; p.comp = data
            }
            lock.lock(); prepared[idx] = p; lock.unlock()
        }
        if let e = prepError { throw e }

        // 3) Ghi tuần tự: local header + data; dựng central directory
        fm.createFile(atPath: outputURL.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: outputURL) else { throw ParallelZipError.ioError }
        defer { try? fh.close() }

        var offset: UInt64 = 0
        var centrals: [Central] = []
        centrals.reserveCapacity(items.count)
        let (dtime, ddate) = dosDateTime()

        for (i, it) in items.enumerated() {
            let nameBytes = Array(it.name.utf8)
            if it.isDir {
                let lh = localHeader(name: nameBytes, method: 0, crc: 0, comp: 0, uncomp: 0, dtime: dtime, ddate: ddate)
                try write(fh, lh)
                centrals.append(Central(name: nameBytes, method: 0, crc: 0, comp: 0, uncomp: 0, offset: offset, isDir: true))
                offset += UInt64(lh.count)
            } else if let p = prepared[i] {
                let lh = localHeader(name: nameBytes, method: p.method, crc: p.crc, comp: UInt64(p.comp.count), uncomp: p.uncomp, dtime: dtime, ddate: ddate)
                try write(fh, lh); try write(fh, p.comp)
                centrals.append(Central(name: nameBytes, method: p.method, crc: p.crc, comp: UInt64(p.comp.count), uncomp: p.uncomp, offset: offset, isDir: false))
                offset += UInt64(lh.count) + UInt64(p.comp.count)
            } else {
                // File LỚN -> STORE + stream (2 lượt: tính CRC, rồi copy). RAM hằng số.
                guard let u = it.url else { throw ParallelZipError.ioError }
                let (crc, size) = try streamCRC(u)
                let lh = localHeader(name: nameBytes, method: 0, crc: crc, comp: size, uncomp: size, dtime: dtime, ddate: ddate)
                try write(fh, lh)
                try streamCopy(from: u, to: fh)
                centrals.append(Central(name: nameBytes, method: 0, crc: crc, comp: size, uncomp: size, offset: offset, isDir: false))
                offset += UInt64(lh.count) + size
            }
            progress?(Double(i + 1) / Double(items.count))
        }

        // 4) Central directory + (Zip64) EOCD
        let cdStart = offset
        var cd = Buf()
        for c in centrals { cd.raw(centralHeader(c, dtime: dtime, ddate: ddate)) }
        try write(fh, cd.d)
        let cdSize = UInt64(cd.d.count)

        try write(fh, endRecord(entries: UInt64(centrals.count), cdSize: cdSize, cdOffset: cdStart))
        progress?(1.0)
    }

    // MARK: helpers ghi file
    private static func write(_ fh: FileHandle, _ d: Data) throws {
        if #available(iOS 13.4, *) { try fh.write(contentsOf: d) } else { fh.write(d) }
    }
    private static func streamCRC(_ u: URL) throws -> (UInt32, UInt64) {
        guard let rh = try? FileHandle(forReadingFrom: u) else { throw ParallelZipError.ioError }
        defer { try? rh.close() }
        var crc = CRC32(); var total: UInt64 = 0
        while true {
            let chunk = rh.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            crc.update(chunk); total += UInt64(chunk.count)
        }
        return (crc.value, total)
    }
    private static func streamCopy(from u: URL, to fh: FileHandle) throws {
        guard let rh = try? FileHandle(forReadingFrom: u) else { throw ParallelZipError.ioError }
        defer { try? rh.close() }
        while true {
            let chunk = rh.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            try write(fh, chunk)
        }
    }

    // MARK: ZIP records
    private static func dosDateTime() -> (UInt16, UInt16) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let hour: Int = c.hour ?? 0
        let minute: Int = c.minute ?? 0
        let second: Int = c.second ?? 0
        let year: Int = max(0, (c.year ?? 1980) - 1980)
        let month: Int = c.month ?? 1
        let day: Int = c.day ?? 1
        let timeVal: Int = (hour << 11) | (minute << 5) | (second / 2)
        let dateVal: Int = (year << 9) | (month << 5) | day
        return (UInt16(timeVal & 0xFFFF), UInt16(dateVal & 0xFFFF))
    }
    private static func needZ64(_ v: UInt64) -> Bool { v >= 0xFFFFFFFF }

    private static func localHeader(name: [UInt8], method: UInt16, crc: UInt32, comp: UInt64, uncomp: UInt64, dtime: UInt16, ddate: UInt16) -> Data {
        let z64 = needZ64(comp) || needZ64(uncomp)
        var b = Buf()
        b.u32(0x04034b50)
        b.u16(z64 ? 45 : 20)               // version needed
        b.u16(0)                            // flags
        b.u16(method)
        b.u16(dtime); b.u16(ddate)
        b.u32(crc)
        b.u32(z64 ? 0xFFFFFFFF : UInt32(comp))
        b.u32(z64 ? 0xFFFFFFFF : UInt32(uncomp))
        b.u16(UInt16(name.count))
        var extra = Buf()
        if z64 { extra.u16(0x0001); extra.u16(16); extra.u64(uncomp); extra.u64(comp) }
        b.u16(UInt16(extra.d.count))
        b.raw(name)
        b.raw(extra.d)
        return b.d
    }

    private static func centralHeader(_ c: Central, dtime: UInt16, ddate: UInt16) -> Data {
        let z64 = needZ64(c.comp) || needZ64(c.uncomp) || needZ64(c.offset)
        var b = Buf()
        b.u32(0x02014b50)
        b.u16((3 << 8) | (z64 ? 45 : 20))  // version made by (unix)
        b.u16(z64 ? 45 : 20)               // version needed
        b.u16(0)                            // flags
        b.u16(c.method)
        b.u16(dtime); b.u16(ddate)
        b.u32(c.crc)
        b.u32(z64 ? 0xFFFFFFFF : UInt32(c.comp))
        b.u32(z64 ? 0xFFFFFFFF : UInt32(c.uncomp))
        b.u16(UInt16(c.name.count))
        var extra = Buf()
        if z64 {
            extra.u16(0x0001)
            extra.u16(24)
            extra.u64(c.uncomp); extra.u64(c.comp); extra.u64(c.offset)
        }
        b.u16(UInt16(extra.d.count))
        b.u16(0)                            // comment len
        b.u16(0)                            // disk start
        b.u16(0)                            // internal attr
        b.u32(c.isDir ? 0x41ED0000 : 0x81A40000)  // external attr (unix mode)
        b.u32(z64 ? 0xFFFFFFFF : UInt32(c.offset))
        b.raw(c.name)
        b.raw(extra.d)
        return b.d
    }

    private static func endRecord(entries: UInt64, cdSize: UInt64, cdOffset: UInt64) -> Data {
        let z64 = entries >= 0xFFFF || needZ64(cdSize) || needZ64(cdOffset)
        var b = Buf()
        if z64 {
            let z64eocdOffset = cdOffset + cdSize
            // Zip64 EOCD record
            b.u32(0x06064b50)
            b.u64(44)                       // size of remainder
            b.u16((3 << 8) | 45); b.u16(45)
            b.u32(0); b.u32(0)
            b.u64(entries); b.u64(entries)
            b.u64(cdSize); b.u64(cdOffset)
            // Zip64 EOCD locator
            b.u32(0x07064b50)
            b.u32(0)
            b.u64(z64eocdOffset)
            b.u32(1)
        }
        // EOCD
        b.u32(0x06054b50)
        b.u16(0); b.u16(0)
        b.u16(entries >= 0xFFFF ? 0xFFFF : UInt16(entries))
        b.u16(entries >= 0xFFFF ? 0xFFFF : UInt16(entries))
        b.u32(needZ64(cdSize) ? 0xFFFFFFFF : UInt32(cdSize))
        b.u32(needZ64(cdOffset) ? 0xFFFFFFFF : UInt32(cdOffset))
        b.u16(0)
        return b.d
    }
}
