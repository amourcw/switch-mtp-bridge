import SwiftUI

struct TransferQueueView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("传输队列")
                    .font(.headline)

                Spacer()

                Button {
                    store.clearCompleted()
                } label: {
                    Label("清除已完成", systemImage: "checkmark.circle")
                }
                .disabled(!store.transfers.contains { $0.status == .completed })
            }

            if store.transfers.isEmpty {
                EmptyQueueView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.transfers) {
                    TableColumn("文件") { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                                .lineLimit(1)
                            Text(item.fileURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    TableColumn("目标存储区") { item in
                        Text(item.storageName)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                    }

                    TableColumn("状态") { item in
                        StatusBadge(status: item.status)
                    }

                    TableColumn("") { item in
                        Button {
                            store.removeTransfer(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("移除")
                    }
                    .width(44)
                }
            }
        }
        .padding(20)
    }
}

private struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text("还没有添加文件")
                .font(.headline)

            Text("添加 NSP、NSZ、XCI 或其他要发送到 DBI 的文件。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct StatusBadge: View {
    var status: TransferStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
            Text(status.title)
        }
        .foregroundStyle(foregroundStyle)
    }

    private var iconName: String {
        switch status {
        case .queued:
            return "clock"
        case .running:
            return "arrow.up.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        }
    }

    private var foregroundStyle: Color {
        switch status {
        case .queued, .running:
            return .secondary
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}
