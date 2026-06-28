import AppKit
import Foundation

@MainActor
final class MTPStore: ObservableObject {
    @Published var toolStatus: ToolStatus = .unknown
    @Published var device: DeviceSnapshot?
    @Published var transfers: [TransferItem] = []
    @Published var storages: [MTPStorage] = []
    @Published var selectedStorageID: String = ""
    @Published var files: [MTPFileItem] = []
    @Published var logLines: [String] = []
    @Published var isBusy = false
    @Published var lastRefreshDate: Date?
    private let service = MTPCommandService()

    init() {
        Task { await refreshDevice() }
    }

    func refreshDevice() async {
        isBusy = true
        defer { isBusy = false }

        appendLog("正在检查 libmtp 工具...")
        toolStatus = await service.toolStatus()

        guard case .available = toolStatus else {
            device = nil
            appendLog("没有找到 libmtp。请先安装：brew install libmtp")
            return
        }

        appendLog("正在查找 MTP 设备。请在 Switch 上打开 DBI 并启动 MTP 响应器。")
        let result = await service.detectDevice()
        let text = result.combinedOutput
        lastRefreshDate = Date()

        if result.exitCode == 0 && MTPOutputParser.hasDetectedDevice(in: text) {
            device = DeviceSnapshot(summary: MTPOutputParser.deviceSummary(from: text), rawDetails: text)
            appendLog("已检测到 DBI MTP 设备。")
            await refreshStoragesAndFiles()
        } else {
            device = nil
            storages = []
            selectedStorageID = ""
            files = []
            appendLog("未检测到 DBI MTP 设备。")
            if !text.isEmpty {
                appendLog(MTPOutputParser.shortFailureMessage(from: text))
            }
        }
    }

    func refreshStoragesAndFiles() async {
        let storageResult = await service.listStorages()
        guard storageResult.exitCode == 0 else {
            storages = []
            selectedStorageID = ""
            files = []
            appendLog("读取存储区失败：\(storageResult.combinedOutput)")
            return
        }

        storages = MTPHelperParser.storages(from: storageResult.output)
        selectedStorageID = preferredStorageID(from: storages, current: selectedStorageID)
        appendLog("已读取 \(storages.count) 个存储区。")

        await refreshFiles()
    }

    func refreshFiles() async {
        guard !selectedStorageID.isEmpty else {
            files = []
            return
        }

        let result = await service.listFiles(storageID: selectedStorageID)
        if result.exitCode == 0 {
            files = MTPHelperParser.files(from: result.output)
            appendLog("已读取 \(selectedStorageName) 中的 \(files.count) 个项目。")
        } else {
            files = []
            appendLog("读取文件列表失败：\(result.combinedOutput)")
        }
    }

    func presentFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "添加"

        if panel.runModal() == .OK {
            queueFiles(panel.urls)
        }
    }

    func queueFiles(_ urls: [URL]) {
        guard !selectedStorageID.isEmpty else {
            appendLog("请先选择目标存储区。")
            return
        }

        let newItems = urls.map { url in
            TransferItem(
                fileURL: url,
                storageID: selectedStorageID,
                storageName: selectedStorageName
            )
        }
        transfers.append(contentsOf: newItems)
        appendLog("已添加 \(newItems.count) 个文件。")
    }

    func removeTransfer(_ item: TransferItem) {
        transfers.removeAll { $0.id == item.id }
    }

    func clearCompleted() {
        transfers.removeAll { $0.status == .completed }
    }

    func uploadQueuedFiles() async {
        guard case .available = toolStatus else {
            appendLog("缺少 libmtp，已跳过上传。")
            return
        }

        let queuedIDs = transfers.filter { $0.status == .queued || isRetryable($0.status) }.map(\.id)
        guard !queuedIDs.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }

        for id in queuedIDs {
            guard let index = transfers.firstIndex(where: { $0.id == id }) else { continue }
            transfers[index].status = .running
            let item = transfers[index]
            appendLog("正在上传 \(item.fileName) -> \(item.storageName)")

            let result = await service.sendFile(
                localURL: item.fileURL,
                storageID: item.storageID,
                remoteName: item.fileName
            )
            if result.exitCode == 0 {
                transfers[index].status = .completed
                appendLog("已完成 \(item.fileName)。")
            } else {
                let message = result.combinedOutput.isEmpty ? "mtp-helper 退出码：\(result.exitCode)" : result.combinedOutput
                transfers[index].status = .failed(message)
                appendLog("上传失败 \(item.fileName)：\(message)")
            }
        }

        await refreshFiles()
    }

    func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install libmtp", forType: .string)
        appendLog("已复制安装命令。")
    }

    private func isRetryable(_ status: TransferStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }

    var selectedStorageName: String {
        storages.first { $0.id == selectedStorageID }?.displayName ?? "未选择"
    }

    private func preferredStorageID(from storages: [MTPStorage], current: String) -> String {
        if storages.contains(where: { $0.id == current }) {
            return current
        }

        if let sdInstall = storages.first(where: { $0.name.localizedCaseInsensitiveContains("SD Card install") }) {
            return sdInstall.id
        }

        if let writable = storages.first(where: { $0.accessCapability == 0 }) {
            return writable.id
        }

        return storages.first?.id ?? ""
    }

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logLines.append("[\(formatter.string(from: Date()))] \(line)")
        if logLines.count > 300 {
            logLines.removeFirst(logLines.count - 300)
        }
    }
}
