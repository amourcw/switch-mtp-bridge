import SwiftUI

struct DetailView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                ConnectionHeaderView(store: store)
                Divider()
                FileBrowserView(store: store)
            }
            .frame(minHeight: 360)

            TransferQueueView(store: store)
                .frame(minHeight: 150, idealHeight: 210)
        }
        .navigationTitle("MTP 文件传输")
    }
}

private struct ConnectionHeaderView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: store.device == nil ? "cable.connector.slash" : "externaldrive.connected.to.line.below")
                .font(.title2)
                .foregroundStyle(store.device == nil ? Color.secondary : Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.device == nil ? "等待 MTP 设备" : "MTP 设备已连接")
                    .font(.headline)
                Text(store.device?.summary.components(separatedBy: .newlines).first ?? "插入手机、相机、播放器或已开启 MTP 模式的 Switch 后点击刷新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Picker("设备存储区", selection: $store.selectedStorageID) {
                Text("未检测到存储区").tag("")
                ForEach(store.storages) { storage in
                    Text(storage.displayName).tag(storage.id)
                }
            }
            .labelsHidden()
            .frame(width: 250)
            .disabled(store.storages.isEmpty || store.isBusy)
            .onChange(of: store.selectedStorageID) { value in store.selectStorage(value) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
