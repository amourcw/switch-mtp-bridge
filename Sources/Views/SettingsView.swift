import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        Form {
            Picker("默认目标", selection: $store.selectedStorageID) {
                ForEach(store.storages) { storage in
                    Text(storage.displayName).tag(storage.id)
                }
            }

            Button("复制 libmtp 安装命令") {
                store.copyInstallCommand()
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}
