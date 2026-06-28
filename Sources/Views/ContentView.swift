import SwiftUI

struct ContentView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            DetailView(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.refreshDevice() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新设备")
                .disabled(store.isBusy)

                Button {
                    store.presentFilePicker()
                } label: {
                    Label("添加文件", systemImage: "plus")
                }
                .help("添加要传输的文件")

                Button {
                    Task { await store.uploadQueuedFiles() }
                } label: {
                    Label("上传", systemImage: "arrow.up.doc")
                }
                .help("上传队列中的文件")
                .disabled(store.isBusy || store.transfers.isEmpty)
            }
        }
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            guard !store.isBusy else { return }
            guard store.device == nil else { return }
            Task { await store.refreshDevice() }
        }
    }
}
