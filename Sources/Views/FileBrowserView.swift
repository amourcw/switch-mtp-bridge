import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        HSplitView {
            LocalBrowserPane(store: store)
                .frame(minWidth: 330)
            MTPBrowserPane(store: store)
                .frame(minWidth: 330)
        }
    }
}

private struct LocalBrowserPane: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "本地 Mac", icon: "internaldrive") {
                Button { store.goUpLocalDirectory() } label: { Image(systemName: "chevron.up") }
                    .help("上一级目录")
                Button { store.chooseLocalDirectory() } label: { Image(systemName: "folder") }
                    .help("选择目录")
                Button { store.refreshLocalFiles() } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新本地目录")
            }
            PathLabel(path: store.localDirectory.path)
            Table(store.localFiles, selection: $store.selectedLocalURLs) {
                TableColumn("名称") { item in
                    Label(item.name, systemImage: item.isDirectory ? "folder.fill" : "doc")
                        .lineLimit(1)
                }
                TableColumn("大小") { item in
                    Text(item.isDirectory ? "--" : ByteCountText.string(from: item.sizeBytes))
                        .foregroundStyle(.secondary)
                }.width(85)
                TableColumn("修改日期") { item in
                    Text(item.modifiedDate?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }.width(135)
            }
            .contextMenu(forSelectionType: URL.self) { _ in
                Button("传输到设备") { store.queueUpload() }
                    .disabled(store.selectedLocalURLs.isEmpty || store.device == nil)
            } primaryAction: { urls in
                if let item = store.localFiles.first(where: { urls.contains($0.url) }) { store.openLocalItem(item) }
            }
            Divider()
            Button {
                store.queueUpload()
            } label: {
                Label("传输所选项目到设备", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(10)
            .disabled(store.selectedLocalURLs.isEmpty || store.device == nil || store.isBusy)
        }
    }
}

private struct MTPBrowserPane: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "MTP 设备", icon: "externaldrive") {
                Button { store.goToMTPPath(index: store.mtpPath.isEmpty ? nil : store.mtpPath.count - 2) } label: { Image(systemName: "chevron.up") }
                    .help("上一级目录")
                    .disabled(store.mtpPath.isEmpty)
                Button { Task { await store.refreshFiles() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新设备目录")
                    .disabled(store.selectedStorageID.isEmpty || store.isBusy)
            }
            MTPBreadcrumbs(store: store)
            if store.device == nil {
                EmptyBrowserView(title: "未连接 MTP 设备", icon: "cable.connector.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.files, selection: $store.selectedMTPIDs) {
                    TableColumn("名称") { item in
                        Label(item.name, systemImage: item.isFolder ? "folder.fill" : "doc")
                            .lineLimit(1)
                    }
                    TableColumn("大小") { item in
                        Text(item.isFolder ? "--" : ByteCountText.string(from: item.sizeBytes))
                            .foregroundStyle(.secondary)
                    }.width(85)
                    TableColumn("类型") { item in
                        Text(item.isFolder ? "文件夹" : "文件")
                            .foregroundStyle(.secondary)
                    }.width(62)
                }
                .contextMenu(forSelectionType: UInt32.self) { _ in
                    Button("下载到本机") { store.queueDownload() }
                        .disabled(store.selectedMTPIDs.isEmpty)
                } primaryAction: { ids in
                    if let item = store.files.first(where: { ids.contains($0.id) }) { store.openMTPItem(item) }
                }
            }
            Divider()
            Button {
                store.queueDownload()
            } label: {
                Label("传输所选项目到本机", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(10)
            .disabled(store.selectedMTPIDs.isEmpty || store.device == nil || store.isBusy)
        }
    }
}

private struct EmptyBrowserView: View {
    var title: String
    var icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
        }
    }
}

private struct PaneHeader<Actions: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack {
            Label(title, systemImage: icon).font(.headline)
            Spacer()
            HStack(spacing: 8, content: actions)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct PathLabel: View {
    var path: String
    var body: some View {
        Text(path)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }
}

private struct MTPBreadcrumbs: View {
    @ObservedObject var store: MTPStore
    var body: some View {
        HStack(spacing: 4) {
            Button(store.selectedStorageName) { store.goToMTPPath(index: nil) }
                .buttonStyle(.link)
            ForEach(Array(store.mtpPath.enumerated()), id: \.element.id) { index, item in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(item.name) { store.goToMTPPath(index: index) }
                    .buttonStyle(.link)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}
