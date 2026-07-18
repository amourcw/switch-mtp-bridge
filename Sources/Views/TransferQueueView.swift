import SwiftUI

struct TransferQueueView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("传输队列").font(.headline)
                Spacer()
                Button { Task { await store.runQueuedTransfers() } } label: { Image(systemName: "play.fill") }
                    .help("开始或重试传输")
                    .disabled(store.isBusy || !store.transfers.contains { $0.status == .queued })
                Button { store.clearCompleted() } label: { Image(systemName: "checkmark.circle") }
                    .help("清除已完成")
                    .disabled(!store.transfers.contains { $0.status == .completed })
            }
            if store.transfers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right").font(.title2).foregroundStyle(.secondary)
                    Text("没有待传输项目").foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.transfers) {
                    TableColumn("项目") { item in Text(item.sourceName).lineLimit(1) }
                    TableColumn("方向") { item in Text(item.direction.title).foregroundStyle(.secondary) }.width(105)
                    TableColumn("目标") { item in Text(item.destinationName).lineLimit(1).foregroundStyle(.secondary) }
                    TableColumn("状态") { item in StatusBadge(status: item.status) }.width(82)
                    TableColumn("") { item in
                        Button { store.removeTransfer(item) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("移除")
                    }.width(36)
                }
            }
        }
        .padding(14)
    }
}

private struct StatusBadge: View {
    var status: TransferStatus
    var body: some View {
        HStack(spacing: 5) { Image(systemName: icon); Text(status.title) }
            .foregroundStyle(color)
    }
    private var icon: String {
        switch status { case .queued: return "clock"; case .running: return "arrow.triangle.2.circlepath"; case .completed: return "checkmark.circle"; case .failed: return "xmark.octagon" }
    }
    private var color: Color {
        switch status { case .completed: return .green; case .failed: return .red; default: return .secondary }
    }
}
