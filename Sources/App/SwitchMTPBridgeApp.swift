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
        WindowGroup("Switch MTP 助手") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新设备") {
                    Task { await store.refreshDevice() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("上传文件...") {
                    store.presentFilePicker()
                }
                .keyboardShortcut("u", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
