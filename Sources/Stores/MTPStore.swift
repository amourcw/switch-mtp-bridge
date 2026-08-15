import AppKit
import Foundation

@MainActor
final class MTPStore: ObservableObject {
    @Published var toolStatus: ToolStatus = .unknown
    @Published var device: DeviceSnapshot?
    @Published var storages: [MTPStorage] = []
    @Published var selectedStorageID = ""
    @Published var files: [MTPFileItem] = []
    @Published var selectedMTPIDs: Set<UInt32> = []
    @Published var mtpPath: [MTPFileItem] = []
    @Published var localDirectory = FileManager.default.homeDirectoryForCurrentUser
    @Published var localFiles: [LocalFileItem] = []
    @Published var selectedLocalURLs: Set<URL> = []
    @Published var transfers: [TransferItem] = []
    @Published var logLines: [String] = []
    @Published var isBusy = false
    @Published var lastRefreshDate: Date?

    private let service = MTPCommandService()
    private var lastRefreshAttempt: Date?
    private var consecutiveRefreshFailures = 0

    init() {
        refreshLocalFiles()
        Task { await refreshDevice() }
    }

    func refreshDevice() async {
        isBusy = true
        defer { isBusy = false }
        lastRefreshAttempt = Date()
        appendLog("正在检查 libmtp 工具...")
        toolStatus = await service.toolStatus()
        guard case .available = toolStatus else {
            clearDevice()
            appendLog("没有找到 libmtp。请先安装：brew install libmtp")
            return
        }

        appendLog("正在连接 MTP 设备...")
        let result = await service.refresh(currentStorageID: selectedStorageID)
        let text = result.combinedOutput
        lastRefreshDate = Date()
        guard MTPOutputParser.hasDetectedDevice(in: text) else {
            consecutiveRefreshFailures += 1
            clearDevice()
            appendLog("未检测到 MTP 设备。")
            if !text.isEmpty { appendLog(MTPOutputParser.shortFailureMessage(from: text)) }
            return
        }

        consecutiveRefreshFailures = 0
        let newStorages = MTPHelperParser.storages(from: text)
        device = DeviceSnapshot(summary: MTPOutputParser.deviceSummary(from: text), rawDetails: text)
        storages = newStorages
        selectedStorageID = preferredStorageID(from: newStorages, current: selectedStorageID)
        mtpPath = []
        files = sortedFiles(MTPHelperParser.files(from: text))
        selectedMTPIDs = []
        appendLog("已连接 MTP 设备。")
    }

    /// 轻量探测：仅枚举 USB，不打开 MTP 会话；发现设备存在后才执行完整刷新。
    /// 连续失败后自动退避，避免在设备被其他程序占用时反复触发会话开/关。
    func pollForDevice() async {
        guard !isBusy else { return }
        if consecutiveRefreshFailures >= 2,
           let last = lastRefreshAttempt,
           Date().timeIntervalSince(last) < 30 {
            return
        }
        let result = await service.probe()
        guard result.exitCode == 0 else { return }
        await refreshDevice()
    }

    func refreshFiles() async {
        guard !selectedStorageID.isEmpty else { files = []; return }
        let result = await service.listFiles(storageID: selectedStorageID, parentID: currentMTPParentID)
        if result.exitCode == 0 {
            files = sortedFiles(MTPHelperParser.files(from: result.output))
            selectedMTPIDs = []
        } else {
            files = []
            appendLog("读取设备目录失败：\(result.combinedOutput)")
        }
    }

    func selectStorage(_ storageID: String) {
        selectedStorageID = storageID
        mtpPath = []
        Task { await refreshFiles() }
    }

    func openMTPItem(_ item: MTPFileItem) {
        guard item.isFolder else { return }
        mtpPath.append(item)
        Task { await refreshFiles() }
    }

    func goToMTPPath(index: Int?) {
        if let index { mtpPath = Array(mtpPath.prefix(index + 1)) } else { mtpPath = [] }
        Task { await refreshFiles() }
    }

    func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = localDirectory
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            openLocalDirectory(url)
        }
    }

    func openLocalItem(_ item: LocalFileItem) {
        guard item.isDirectory else { return }
        openLocalDirectory(item.url)
    }

    func openLocalDirectory(_ url: URL) {
        localDirectory = url.standardizedFileURL
        refreshLocalFiles()
    }

    func goUpLocalDirectory() {
        let parent = localDirectory.deletingLastPathComponent()
        guard parent.path != localDirectory.path else { return }
        openLocalDirectory(parent)
    }

    func refreshLocalFiles() {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        do {
            localFiles = try FileManager.default.contentsOfDirectory(
                at: localDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ).compactMap { url in
                let values = try? url.resourceValues(forKeys: keys)
                return LocalFileItem(
                    url: url,
                    isDirectory: values?.isDirectory ?? false,
                    sizeBytes: UInt64(values?.fileSize ?? 0),
                    modifiedDate: values?.contentModificationDate
                )
            }.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            selectedLocalURLs = []
        } catch {
            localFiles = []
            appendLog("无法读取本机目录：\(error.localizedDescription)")
        }
    }

    func queueUpload() {
        guard !selectedStorageID.isEmpty else { appendLog("请先连接并选择设备存储区。"); return }
        let items = localFiles.filter { selectedLocalURLs.contains($0.url) }
        guard !items.isEmpty else { return }
        let newItems = items.map { item in
            TransferItem(
                direction: .upload,
                sourceName: item.name,
                destinationName: "\(selectedStorageName) / \(mtpPathText)",
                operation: .upload(localURL: item.url, storageID: selectedStorageID, parentID: currentMTPParentID)
            )
        }
        transfers.append(contentsOf: newItems)
        appendLog("已加入 \(newItems.count) 个上传项目。")
        Task { await runQueuedTransfers() }
    }

    func queueDownload() {
        let items = files.filter { selectedMTPIDs.contains($0.id) }
        guard !items.isEmpty else { return }
        let newItems = items.map { item in
            TransferItem(
                direction: .download,
                sourceName: item.name,
                destinationName: localDirectory.path,
                operation: .download(file: item, destinationURL: localDirectory.appendingPathComponent(item.name))
            )
        }
        transfers.append(contentsOf: newItems)
        appendLog("已加入 \(newItems.count) 个下载项目。")
        Task { await runQueuedTransfers() }
    }

    func runQueuedTransfers() async {
        guard !isBusy else { return }
        let queuedIDs = transfers.filter { $0.status == .queued || isRetryable($0.status) }.map(\.id)
        guard !queuedIDs.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        for id in queuedIDs {
            guard let index = transfers.firstIndex(where: { $0.id == id }) else { continue }
            transfers[index].status = .running
            let operation = transfers[index].operation
            let name = transfers[index].sourceName
            appendLog("正在传输 \(name)...")
            do {
                switch operation {
                case let .upload(localURL, storageID, parentID):
                    try await upload(localURL, storageID: storageID, parentID: parentID)
                case let .download(file, destinationURL):
                    try await download(file, to: destinationURL)
                }
                transfers[index].status = .completed
                appendLog("已完成 \(name)。")
            } catch {
                transfers[index].status = .failed(error.localizedDescription)
                appendLog("传输失败 \(name)：\(error.localizedDescription)")
            }
        }
        refreshLocalFiles()
        await refreshFiles()
    }

    func removeTransfer(_ item: TransferItem) { transfers.removeAll { $0.id == item.id } }
    func clearCompleted() { transfers.removeAll { $0.status == .completed } }

    func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install libmtp", forType: .string)
        appendLog("已复制安装命令。")
    }

    var selectedStorageName: String { storages.first { $0.id == selectedStorageID }?.displayName ?? "未选择" }
    var currentMTPParentID: UInt32 { mtpPath.last?.id ?? 0 }
    var mtpPathText: String { mtpPath.map(\.name).joined(separator: " / ").isEmpty ? "根目录" : mtpPath.map(\.name).joined(separator: " / ") }

    private func upload(_ url: URL, storageID: String, parentID: UInt32) async throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            let folder = await service.createFolder(name: url.lastPathComponent, storageID: storageID, parentID: parentID)
            guard folder.exitCode == 0, let folderID = MTPHelperParser.folderID(from: folder.output) else { throw MTPTransferError.message(folder.combinedOutput) }
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for child in children { try await upload(child, storageID: storageID, parentID: folderID) }
        } else {
            let result = await service.sendFile(localURL: url, storageID: storageID, remoteName: url.lastPathComponent, parentID: parentID)
            guard result.exitCode == 0 else { throw MTPTransferError.message(result.combinedOutput) }
        }
    }

    private func download(_ item: MTPFileItem, to destination: URL) async throws {
        if item.isFolder {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let result = await service.listFiles(storageID: item.storageID, parentID: item.id)
            guard result.exitCode == 0 else { throw MTPTransferError.message(result.combinedOutput) }
            for child in MTPHelperParser.files(from: result.output) {
                try await download(child, to: destination.appendingPathComponent(child.name))
            }
        } else {
            let result = await service.receiveFile(itemID: item.id, destinationURL: destination)
            guard result.exitCode == 0 else { throw MTPTransferError.message(result.combinedOutput) }
        }
    }

    private func clearDevice() { device = nil; storages = []; selectedStorageID = ""; files = []; mtpPath = [] }
    private func isRetryable(_ status: TransferStatus) -> Bool { if case .failed = status { return true }; return false }
    private func sortedFiles(_ items: [MTPFileItem]) -> [MTPFileItem] {
        items.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    private func preferredStorageID(from storages: [MTPStorage], current: String) -> String {
        if storages.contains(where: { $0.id == current }) { return current }
        if let install = storages.first(where: { $0.name.localizedCaseInsensitiveContains("SD Card install") }) { return install.id }
        if let writable = storages.first(where: { $0.accessCapability == 0 }) { return writable.id }
        return storages.first?.id ?? ""
    }
    private func appendLog(_ line: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        logLines.append("[\(formatter.string(from: Date()))] \(line)")
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }
}

private enum MTPTransferError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message.isEmpty ? "MTP 操作失败" : message }
    }
}
