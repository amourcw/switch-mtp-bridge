import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("设备文件")
                    .font(.headline)

                Spacer()

                Button {
                    Task { await store.refreshFiles() }
                } label: {
                    Label("刷新列表", systemImage: "arrow.clockwise")
                }
                .disabled(store.selectedStorageID.isEmpty || store.isBusy)
            }

            if store.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(store.selectedStorageID.isEmpty ? "还没有选择存储区" : "当前存储区没有显示项目")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.files) {
                    TableColumn("名称") { item in
                        Label(item.name, systemImage: item.isFolder ? "folder" : "doc")
                            .lineLimit(1)
                    }

                    TableColumn("大小") { item in
                        Text(item.isFolder ? "--" : ByteCountText.string(from: item.sizeBytes))
                            .foregroundStyle(.secondary)
                    }
                    .width(90)

                    TableColumn("ID") { item in
                        Text("\(item.id)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(90)
                }
            }
        }
        .padding(20)
    }
}
