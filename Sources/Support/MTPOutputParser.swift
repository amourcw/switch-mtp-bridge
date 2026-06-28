import Foundation

enum MTPOutputParser {
    static func hasDetectedDevice(in output: String) -> Bool {
        if output.localizedCaseInsensitiveContains("No raw devices found") { return false }
        if output.localizedCaseInsensitiveContains("No devices") { return false }
        if output.localizedCaseInsensitiveContains("Device recognized as MTP") { return true }
        if output.localizedCaseInsensitiveContains("Friendly name: DBI MTP Responder") { return true }
        if output.localizedCaseInsensitiveContains("Model: Switch") { return true }
        return false
    }

    static func deviceSummary(from output: String) -> String {
        let interestingPrefixes = [
            "Manufacturer:",
            "Model:",
            "Device version:",
            "Serial number:",
            "Friendly name:",
            "StorageDescription:",
            "Vendor extension ID:",
            "Vendor extension description:"
        ]

        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let matches = lines.filter { line in
            interestingPrefixes.contains { line.hasPrefix($0) }
        }

        if matches.isEmpty {
            return output.components(separatedBy: .newlines).prefix(8).joined(separator: "\n")
        }

        return matches.map(localizedLine).joined(separator: "\n")
    }

    static func shortFailureMessage(from output: String) -> String {
        if output.localizedCaseInsensitiveContains("No raw devices found") {
            return "USB 没有向 libmtp 暴露 MTP 设备。"
        }
        if output.localizedCaseInsensitiveContains("No devices") {
            return "libmtp 没有找到设备。"
        }

        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: " ")
    }

    private static func localizedLine(_ line: String) -> String {
        let replacements = [
            "Manufacturer:": "制造商：",
            "Model:": "型号：",
            "Device version:": "系统版本：",
            "Serial number:": "序列号：",
            "Friendly name:": "设备名称：",
            "StorageDescription:": "存储：",
            "Vendor extension ID:": "厂商扩展 ID：",
            "Vendor extension description:": "厂商扩展说明："
        ]

        for (prefix, localizedPrefix) in replacements where line.hasPrefix(prefix) {
            return localizedPrefix + line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }

        return line
    }
}
