import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct SwitchMTPBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MTPStore()

    var body: some Scene {
        WindowGroup("MTP 文件传输") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新设备") {
                    Task { await store.refreshDevice() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("选择本地目录...") {
                    store.chooseLocalDirectory()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
