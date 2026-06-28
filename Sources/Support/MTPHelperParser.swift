import Foundation

enum MTPHelperParser {
    static func storages(from output: String) -> [MTPStorage] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 6, parts[0] == "STORAGE" else { return nil }
                return MTPStorage(
                    id: parts[1],
                    name: parts[2],
                    freeBytes: UInt64(parts[3]) ?? 0,
                    capacityBytes: UInt64(parts[4]) ?? 0,
                    accessCapability: UInt16(parts[5]) ?? 0
                )
            }
    }

    static func files(from output: String) -> [MTPFileItem] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 7, parts[0] == "FILE" else { return nil }
                return MTPFileItem(
                    id: UInt32(parts[1]) ?? 0,
                    parentID: UInt32(parts[2]) ?? 0,
                    storageID: parts[3],
                    fileType: UInt16(parts[4]) ?? 0,
                    sizeBytes: UInt64(parts[5]) ?? 0,
                    name: parts[6]
                )
            }
    }
}

enum ByteCountText {
    static func string(from bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
