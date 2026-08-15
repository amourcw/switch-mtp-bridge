import Foundation

struct MTPCommandService {
    private let daemon: MTPHelperDaemon

    init() {
        daemon = MTPHelperDaemon(helperURL: Self.helperURL())
    }

    func toolStatus() async -> ToolStatus {
        guard let path = Self.helperURL()?.path else {
            return .missing
        }
        return .available(path: path)
    }

    /// 仅做 USB 层检测，不打开 MTP 会话（不会在 Switch 上触发“会话打开/关闭”）。
    func probe() async -> ProcessResult {
        await daemon.run(arguments: ["probe"], timeout: 15)
    }

    /// 单次会话内完成一次完整刷新：设备信息 + 全部存储区 + 首选存储区的根目录。
    func refresh(currentStorageID: String) async -> ProcessResult {
        await daemon.run(arguments: ["refresh", currentStorageID], timeout: 30)
    }

    func listStorages() async -> ProcessResult {
        await daemon.run(arguments: ["list-storages"], timeout: 30)
    }

    func listFiles(storageID: String, parentID: UInt32 = 0) async -> ProcessResult {
        await daemon.run(arguments: ["list-files", storageID, String(parentID)], timeout: 30)
    }

    func sendFile(localURL: URL, storageID: String, remoteName: String, parentID: UInt32) async -> ProcessResult {
        await daemon.run(arguments: ["send-file", localURL.path, storageID, remoteName, String(parentID)], timeout: 600)
    }

    func receiveFile(itemID: UInt32, destinationURL: URL) async -> ProcessResult {
        await daemon.run(arguments: ["get-file", String(itemID), destinationURL.path], timeout: 600)
    }

    func createFolder(name: String, storageID: String, parentID: UInt32) async -> ProcessResult {
        await daemon.run(arguments: ["create-folder", storageID, String(parentID), name], timeout: 30)
    }

    private static func helperURL() -> URL? {
        if let bundleHelper = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("mtp-helper"),
           FileManager.default.isExecutableFile(atPath: bundleHelper.path) {
            return bundleHelper
        }

        let localHelper = FileManager.default.currentDirectoryPath + "/.build/mtp-helper"
        if FileManager.default.isExecutableFile(atPath: localHelper) {
            return URL(fileURLWithPath: localHelper)
        }

        return nil
    }
}
