import SwiftUI

struct ContentView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        DetailView(store: store)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        store.chooseLocalDirectory()
                    } label: {
                        Label("选择本地目录", systemImage: "folder")
                    }
                    .help("选择本地目录")

                    Button {
                        Task { await store.refreshDevice() }
                    } label: {
                        Label("刷新设备", systemImage: "arrow.clockwise")
                    }
                    .help("刷新 MTP 设备")
                    .disabled(store.isBusy)
                }
            }
            .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
                guard !store.isBusy, store.device == nil else { return }
                Task { await store.pollForDevice() }
            }
    }
}
