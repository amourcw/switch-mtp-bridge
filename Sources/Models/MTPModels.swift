import Foundation

enum ToolStatus: Equatable {
    case unknown
    case available(path: String)
    case missing

    var title: String {
        switch self {
        case .unknown:
            return "检查中"
        case .available:
            return "已就绪"
        case .missing:
            return "缺少 libmtp"
        }
    }
}

struct DeviceSnapshot: Equatable {
    var summary: String
    var rawDetails: String
}

struct MTPStorage: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var freeBytes: UInt64
    var capacityBytes: UInt64
    var accessCapability: UInt16

    var displayName: String {
        name.isEmpty ? id : name
    }
}

struct MTPFileItem: Identifiable, Equatable {
    var id: UInt32
    var parentID: UInt32
    var storageID: String
    var fileType: UInt16
    var sizeBytes: UInt64
    var name: String

    var isFolder: Bool {
        fileType == 0x3001 || (fileType == 0 && sizeBytes == 0)
    }
}

struct TransferItem: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    var storageID: String
    var storageName: String
    var status: TransferStatus = .queued

    var fileName: String {
        fileURL.lastPathComponent
    }
}

enum TransferStatus: Equatable {
    case queued
    case running
    case completed
    case failed(String)

    var title: String {
        switch self {
        case .queued:
            return "排队中"
        case .running:
            return "上传中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        }
    }
}

struct ProcessResult: Equatable {
    var exitCode: Int32
    var output: String
    var error: String

    var combinedOutput: String {
        [output, error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
