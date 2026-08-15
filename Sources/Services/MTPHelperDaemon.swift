import Foundation

/// 常驻 mtp-helper 进程的客户端。
///
/// mtp-helper 以 `serve` 模式启动后只打开一次 MTP 会话并保持，命令从 stdin
/// 以制表符分隔的行输入，响应以 `\n__END__\t<exit-code>` 结束。这样 DBI 的
/// 对象 ID 在同一会话内保持有效，可以正常浏览子目录，同时避免每次操作的
/// USB 复位。命令在内部串行执行；helper 空闲 120 秒会自动退出，本类每 60 秒
/// 发一次 probe 保活。
final class MTPHelperDaemon {
    private let helperURL: URL?
    private let queue = DispatchQueue(label: "mtp-helper-daemon.serial")

    private var process: Process?
    private var writeHandle: FileHandle?
    private var readHandle: FileHandle?

    /// 读线程与命令等待方共享的响应缓冲区
    private let lock = NSCondition()
    private var outputBuffer = Data()

    private var keepAliveScheduled = false

    private static let marker = Data("\n__END__\t".utf8)

    init(helperURL: URL?) {
        self.helperURL = helperURL
    }

    deinit {
        process?.terminate()
    }

    /// 执行一条命令。参数按制表符拼接成一行发给 helper。
    func run(arguments: [String], timeout: TimeInterval = 30) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.syncRun(arguments: arguments, timeout: timeout))
            }
        }
    }

    // MARK: - 内部实现（仅在串行 queue 上执行）

    private func syncRun(arguments: [String], timeout: TimeInterval) -> ProcessResult {
        scheduleKeepAlive()
        for attempt in 0..<2 {
            do {
                try ensureProcess()
                try writeRequest(arguments)
                return readResponse(timeout: timeout)
            } catch {
                resetProcess()
                if attempt == 1 {
                    return ProcessResult(exitCode: 126, output: "", error: error.localizedDescription)
                }
            }
        }
        return ProcessResult(exitCode: 126, output: "", error: "mtp-helper 通信失败")
    }

    private func ensureProcess() throws {
        if let process, process.isRunning, writeHandle != nil, readHandle != nil {
            return
        }
        guard let helperURL else {
            throw MTPHelperError.helperMissing
        }

        let newProcess = Process()
        newProcess.executableURL = helperURL
        newProcess.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        newProcess.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        newProcess.standardInput = inputPipe
        newProcess.standardOutput = outputPipe
        newProcess.standardError = errorPipe

        try newProcess.run()

        process = newProcess
        writeHandle = inputPipe.fileHandleForWriting
        readHandle = outputPipe.fileHandleForReading

        lock.lock()
        outputBuffer.removeAll(keepingCapacity: true)
        lock.unlock()

        startReaderThread(reading: outputPipe.fileHandleForReading)
    }

    /// 常驻读线程：持续把 helper 的 stdout 追加进缓冲区并广播。
    private func startReaderThread(reading handle: FileHandle) {
        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break } // EOF：进程退出或被终止
                self.lock.lock()
                self.outputBuffer.append(chunk)
                self.lock.broadcast()
                self.lock.unlock()
            }
        }
    }

    private func writeRequest(_ arguments: [String]) throws {
        guard let writeHandle else {
            throw MTPHelperError.notReady
        }
        let line = arguments.joined(separator: "\t") + "\n"
        try writeHandle.write(contentsOf: Data(line.utf8))
    }

    /// 读取一条响应（含超时）。读到 `__END__` 帧即返回；超时会杀掉进程自救。
    private func readResponse(timeout: TimeInterval) -> ProcessResult {
        lock.lock()
        let start = outputBuffer.count
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            if outputBuffer.range(of: Self.marker, options: [], in: start..<outputBuffer.count) != nil {
                break
            }
            if Date() >= deadline {
                let partial = String(data: outputBuffer.dropFirst(start), encoding: .utf8) ?? ""
                lock.unlock()
                resetProcess()
                return ProcessResult(exitCode: 124, output: partial, error: "MTP 操作超时（设备无响应）")
            }
            lock.wait(until: deadline)
        }

        let data = outputBuffer
        guard let markerRange = data.range(of: Self.marker, options: [], in: start..<data.count) else {
            lock.unlock()
            return ProcessResult(exitCode: 126, output: "", error: "响应解析失败")
        }

        let responseData = data[start..<markerRange.lowerBound]

        let codeStart = markerRange.lowerBound + 1 // 跳过 marker 前导的换行符
        var codeEnd = codeStart
        while codeEnd < data.count && data[codeEnd] != 0x0A {
            codeEnd += 1
        }
        let codeLine = String(data: data[codeStart..<codeEnd], encoding: .utf8) ?? ""
        let consumeEnd = min(codeEnd + 1, data.count)
        if consumeEnd > start {
            outputBuffer.removeSubrange(start..<consumeEnd)
        }
        lock.unlock()

        let text = String(data: responseData, encoding: .utf8) ?? ""
        var exitCode: Int32 = 1
        if codeLine.hasPrefix("__END__\t") {
            exitCode = Int32(codeLine.dropFirst("__END__\t".count).trimmingCharacters(in: .whitespaces)) ?? 1
        }
        let outputLines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return ProcessResult(exitCode: exitCode, output: outputLines.joined(separator: "\n"), error: "")
    }

    private func resetProcess() {
        process?.terminate()
        process = nil
        writeHandle = nil
        readHandle = nil
        lock.lock()
        outputBuffer.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// 每 60 秒发一次 probe，防止 helper 因 120 秒空闲而退出。
    private func scheduleKeepAlive() {
        guard !keepAliveScheduled else { return }
        keepAliveScheduled = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self else { return }
            self.queue.async {
                if self.process?.isRunning == true {
                    _ = self.syncRun(arguments: ["probe"], timeout: 15)
                }
                self.keepAliveScheduled = false
                self.scheduleKeepAlive()
            }
        }
    }
}

private enum MTPHelperError: LocalizedError {
    case helperMissing
    case notReady

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "没有找到 mtp-helper。请重新打包应用。"
        case .notReady:
            return "mtp-helper 管道未就绪。"
        }
    }
}
