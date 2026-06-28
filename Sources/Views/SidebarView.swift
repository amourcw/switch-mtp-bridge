import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: MTPStore

    var body: some View {
        List {
            Section("连接") {
                StatusRow(
                    title: store.toolStatus.title,
                    subtitle: toolSubtitle,
                    systemImage: toolImage
                )

                StatusRow(
                    title: store.device == nil ? "未检测到设备" : "已检测到设备",
                    subtitle: deviceSubtitle,
                    systemImage: store.device == nil ? "cable.connector.slash" : "cable.connector"
                )
            }

            Section("传输") {
                StatusRow(
                    title: "\(store.transfers.count) 个文件",
                    subtitle: transferSubtitle,
                    systemImage: "tray.and.arrow.up"
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("DBI MTP")
    }

    private var toolSubtitle: String {
        switch store.toolStatus {
        case .unknown:
            return "准备中"
        case .available(let path):
            return path
        case .missing:
            return "请安装 Homebrew libmtp"
        }
    }

    private var toolImage: String {
        if case .missing = store.toolStatus {
            return "exclamationmark.triangle"
        }
        return "checkmark.circle"
    }

    private var deviceSubtitle: String {
        store.device?.summary.components(separatedBy: .newlines).first ?? "每 4 秒自动扫描"
    }

    private var transferSubtitle: String {
        let done = store.transfers.filter { $0.status == .completed }.count
        let failed = store.transfers.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
        return "\(done) 个完成，\(failed) 个失败"
    }
}

private struct StatusRow: View {
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}
