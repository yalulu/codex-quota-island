import Foundation

@MainActor
final class AppServerClient {
    enum ClientError: LocalizedError {
        case codexNotFound
        case connectionClosed
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .codexNotFound: "未找到 Codex 命令行程序。请安装或更新 Codex 桌面应用。"
            case .connectionClosed: "与 Codex 额度服务的本地连接已关闭。"
            case .invalidResponse: "Codex 返回了无法识别的数据。"
            case let .server(message): "Codex 返回错误：\(message)"
            }
        }
    }

    var onDisconnected: ((Error) -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: (Result<Data, Error>) -> Void] = [:]
    private var initialized = false

    var isConnected: Bool { process?.isRunning == true && initialized }

    func connect() async throws {
        if isConnected { return }
        disconnect(notify: false)

        guard let executableURL = Self.codexExecutableURL() else {
            throw ClientError.codexNotFound
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice

        guard let stdin = (process.standardInput as? Pipe)?.fileHandleForWriting,
              let stdout = (process.standardOutput as? Pipe)?.fileHandleForReading else {
            throw ClientError.connectionClosed
        }

        self.process = process
        input = stdin
        output = stdout
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.disconnect(notify: true) }
        }

        try process.run()
        let _: EmptyResult = try await request(
            method: "initialize",
            params: [
                "clientInfo": ["name": "Codex Quota Island", "version": "0.1.0"],
                "capabilities": [:],
            ]
        )
        sendNotification(method: "initialized", params: [:])
        initialized = true
    }

    func readQuotaSnapshot() async throws -> QuotaSnapshot {
        if !isConnected { try await connect() }
        let response: RateLimitResponse = try await request(method: "account/rateLimits/read")
        return try response.quotaSnapshot()
    }

    func disconnect(notify: Bool = false) {
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        input?.closeFile()
        output?.closeFile()
        process?.terminate()
        process = nil
        input = nil
        output = nil
        initialized = false
        let callbacks = pending
        pending.removeAll()
        callbacks.values.forEach { $0(.failure(ClientError.connectionClosed)) }
        if notify { onDisconnected?(ClientError.connectionClosed) }
    }

    private func request<T: Decodable>(method: String, params: [String: Any] = [:]) async throws -> T {
        let id = nextRequestID
        nextRequestID += 1
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = { result in continuation.resume(with: result) }
            do {
                try send(["method": method, "id": id, "params": params])
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendNotification(method: String, params: [String: Any]) {
        try? send(["method": method, "params": params])
    }

    private func send(_ dictionary: [String: Any]) throws {
        guard let input else { throw ClientError.connectionClosed }
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        input.write(data)
        input.write(Data([0x0A]))
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let id = object["id"] as? Int, let callback = pending.removeValue(forKey: id) {
            if let error = object["error"] as? [String: Any] {
                callback(.failure(ClientError.server(error["message"] as? String ?? "未知错误")))
            } else if let result = object["result"] {
                do { callback(.success(try JSONSerialization.data(withJSONObject: result))) }
                catch { callback(.failure(error)) }
            } else {
                callback(.failure(ClientError.invalidResponse))
            }
            return
        }
    }

    private struct EmptyResult: Decodable {}

    private static func codexExecutableURL() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
}
