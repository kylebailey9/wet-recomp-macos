import Foundation

enum XisoError: Error, LocalizedError {
    case notAnIso
    case xexNotFound
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .notAnIso: return "Not a recognized Xbox 360 ISO."
        case .xexNotFound: return "default.xex not found in ISO."
        case .ioError(let s): return "File error: \(s)"
        }
    }
}

/// Minimal XISO reader (based on XboxDev/extract-xiso).
/// Finds and extracts default.xex from the ISO root directory.
struct XisoReader {
    static func extractDefaultXex(from url: URL) throws -> Data {
        let fh: FileHandle
        do {
            fh = try FileHandle(forReadingFrom: url)
        } catch {
            throw XisoError.ioError(error.localizedDescription)
        }
        defer { try? fh.close() }

        let fileSize = try fh.seekToEnd()
        let magic = Data("MICROSOFT*XBOX*MEDIA".utf8)
        // Header offsets for plain XISO, XGD2, XGD3, XGD1 layouts
        let bases: [UInt64] = [0, 0xFD90000, 0x2080000, 0x18300000]

        for base in bases {
            let hOff = 0x10000 + base
            guard hOff + 28 <= fileSize else { continue }
            try fh.seek(toFileOffset: hOff)
            guard let h = try fh.read(upToCount: 28), h.count == 28, h.prefix(20) == magic else { continue }

            let rootSector: UInt32 = h.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt32.self) }.littleEndian
            let rootSize: UInt32 = h.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self) }.littleEndian
            guard rootSector != 0, rootSize != 0, rootSize < 10 * 1024 * 1024 else { continue }

            for tbase in [base, UInt64(0)] {
                let tOff = UInt64(rootSector) * 2048 + tbase
                guard tOff + UInt64(rootSize) <= fileSize else { continue }
                try fh.seek(toFileOffset: tOff)
                guard let table = try fh.read(upToCount: Int(rootSize)), table.count == rootSize else { continue }
                if let found = walk(table: table, dataBase: base, fh: fh, fileSize: fileSize) {
                    return found
                }
            }
        }
        throw XisoError.xexNotFound
    }

    /// Depth-first walk of the root directory's binary tree.
    /// Entry layout (14 bytes + name): l_offset u16, r_offset u16,
    /// start_sector u32, file_size u32, attrs u8, namelen u8, name.
    private static func walk(table: Data, dataBase: UInt64, fh: FileHandle, fileSize: UInt64) throws -> Data? {
        var stack: [Int] = [0]
        var seen = Set<Int>()
        var guardCount = 0

        while let off = stack.popLast(), guardCount < 200000 {
            guardCount += 1
            guard !seen.contains(off), off + 14 <= table.count else { continue }
            seen.insert(off)

            let l: UInt16 = table.withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt16.self) }.littleEndian
            if l == 0xFFFF { continue } // sector padding
            let r: UInt16 = table.withUnsafeBytes { $0.load(fromByteOffset: off + 2, as: UInt16.self) }.littleEndian
            let sector: UInt32 = table.withUnsafeBytes { $0.load(fromByteOffset: off + 4, as: UInt32.self) }.littleEndian
            let size: UInt32 = table.withUnsafeBytes { $0.load(fromByteOffset: off + 8, as: UInt32.self) }.littleEndian
            let attrs = table[off + 12]
            let nlen = Int(table[off + 13])
            guard nlen > 0, nlen <= 255, off + 14 + nlen <= table.count else { continue }

            let name = String(data: table.subdata(in: (off + 14)..<(off + 14 + nlen)), encoding: .ascii) ?? ""
            if name.lowercased() == "default.xex", attrs & 0x10 == 0, size > 0 {
                let dOff = UInt64(sector) * 2048 + dataBase
                guard dOff + UInt64(size) <= fileSize else { continue }
                try fh.seek(toFileOffset: dOff)
                if let data = try fh.read(upToCount: Int(size)), data.count == size {
                    return data
                }
                continue
            }
            if r != 0 { stack.append(Int(r) * 4) }
            if l != 0 { stack.append(Int(l) * 4) }
        }
        return nil
    }
}
