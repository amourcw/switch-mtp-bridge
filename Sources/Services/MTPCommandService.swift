import Foundation

struct MTPCommandService {
    private let commandPaths = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    func toolStatus() async -> ToolStatus {
        guard let path = helperPath() ?? findExecutable(named: "mtp-detect") else {
            return .missing
        }
        return .available(path: path)
    }

    func detectDevice() async -> ProcessResult {
        await run("mtp-detect", arguments: [])
    }

    func listFiles() async -> ProcessResult {
        await run("mtp-files", arguments: [])
    }

    func listStorages() async -> ProcessResult {
        await runHelper(arguments: ["list-storages"])
    }

    func listFiles(storageID: String, parentID: UInt32 = 0) async -> ProcessResult {
        await runHelper(arguments: ["list-files", storageID, String(parentID)])
    }

    func sendFile(localURL: URL, storageID: String, remoteName: String, parentID: UInt32) async -> ProcessResult {
        await runHelper(arguments: ["send-file", localURL.path, storageID, remoteName, String(parentID)])
    }

    func receiveFile(itemID: UInt32, destinationURL: URL) async -> ProcessResult {
        await runHelper(arguments: ["get-file", String(itemID), destinationURL.path])
    }

    func createFolder(name: String, storageID: String, parentID: UInt32) async -> ProcessResult {
        await runHelper(arguments: ["create-folder", storageID, String(parentID), name])
    }

    private func runHelper(arguments: [String]) async -> ProcessResult {
        guard let executable = helperPath() else {
            return ProcessResult(
                exitCode: 127,
                output: "",
                error: "没有找到 mtp-helper。请重新打包应用。"
            )
        }

        return await runExecutable(executable, arguments: arguments)
    }

    private func run(_ executableName: String, arguments: [String]) async -> ProcessResult {
        guard let executable = findExecutable(named: executableName) else {
            return ProcessResult(
                exitCode: 127,
                output: "",
                error: "没有找到 \(executableName)。请使用 Homebrew 安装 libmtp。"
            )
        }

        return await runExecutable(executable, arguments: arguments)
    }

    private func runExecutable(_ executable: String, arguments: [String]) async -> ProcessResult {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = processEnvironment()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { terminatedProcess in
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(
                    exitCode: terminatedProcess.terminationStatus,
                    output: output,
                    error: error
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ProcessResult(
                    exitCode: 126,
                    output: "",
                    error: error.localizedDescription
                ))
            }
        }
    }

    private func helperPath() -> String? {
        let bundleHelper = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("mtp-helper")
            .path

        if let bundleHelper, FileManager.default.isExecutableFile(atPath: bundleHelper) {
            return bundleHelper
        }

        let localHelper = FileManager.default.currentDirectoryPath + "/.build/mtp-helper"
        if FileManager.default.isExecutableFile(atPath: localHelper) {
            return localHelper
        }

        return nil
    }

    private func findExecutable(named name: String) -> String? {
        for directory in commandPaths {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = commandPaths.joined(separator: ":")
        return environment
    }
}
