import SwiftUI

struct DetailView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VStack(spacing: 0) {
            ConnectionHeaderView(store: store)

            Divider()

            FileBrowserView(store: store)
                .frame(minHeight: 170)

            Divider()

            TransferQueueView(store: store)
                .frame(minHeight: 240)

            Divider()

            LogView(lines: store.logLines)
                .frame(minHeight: 160)
        }
        .navigationTitle("Switch MTP 助手")
    }
}

private struct ConnectionHeaderView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nintendo Switch DBI 传输")
                        .font(.title2.weight(.semibold))
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("目标存储区")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("目标存储区", selection: $store.selectedStorageID) {
                        if store.storages.isEmpty {
                            Text("未读取到存储区").tag("")
                        } else {
                            ForEach(store.storages) { storage in
                                Text(storage.displayName).tag(storage.id)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    .onChange(of: store.selectedStorageID) { _ in
                        Task { await store.refreshFiles() }
                    }
                    Text(storageHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 360)
                }

                Spacer()

                Button {
                    store.copyInstallCommand()
                } label: {
                    Label("复制安装命令", systemImage: "doc.on.doc")
                }
                .disabled({
                    if case .missing = store.toolStatus { return false }
                    return true
                }())
            }

            if let device = store.device {
                Text(device.summary)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
    }

    private var statusText: String {
        if store.device != nil {
            return "DBI 已连接。添加文件后即可通过 libmtp 上传。"
        }

        if let lastRefreshDate = store.lastRefreshDate {
            let formatted = lastRefreshDate.formatted(date: .omitted, time: .standard)
            return "正在等待 DBI MTP 响应器。上次扫描：\(formatted)。"
        }

        return "正在等待 DBI MTP 响应器。"
    }

    private var storageHint: String {
        guard let storage = store.storages.first(where: { $0.id == store.selectedStorageID }) else {
            return "连接 DBI 后会显示可用存储区"
        }

        return "可用 \(ByteCountText.string(from: storage.freeBytes)) / 总计 \(ByteCountText.string(from: storage.capacityBytes))"
    }
}
