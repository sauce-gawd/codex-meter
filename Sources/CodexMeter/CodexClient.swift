import Foundation

/// A short-lived metadata connection. Never starts a thread or model turn.
actor CodexClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

    func fetch(executable: URL) async throws -> UsageSnapshot {
        try start(executable)
        defer { stop() }
        let _: EmptyResponse = try await request("initialize", params: [
            "clientInfo": ["name": "codex_meter", "title": "Codex Meter", "version": "1.0.0"]
        ])
        try send(["method": "initialized", "params": [:]])
        let account: AccountResponse = try await request("account/read", params: ["refreshToken": false])
        guard let auth = account.account else { throw MeterError.signedOut }
        guard auth.type != "apiKey" && auth.type != "apikey" else { throw MeterError.apiKeyAccount }
        let limits: LimitsResponse = try await request("account/rateLimits/read", params: [:])
        var activity: TokenActivity?
        do { activity = try await request("account/usage/read", params: [:]) }
        catch { /* Limits remain usable if token activity is unsupported or unavailable. */ }
        return UsageSnapshot(limits: limits, activity: activity,
                             activityUnavailable: activity == nil, fetchedAt: Date())
    }

    private func start(_ executable: URL) throws {
        let child = Process()
        let stdin = Pipe(), stdout = Pipe()
        child.executableURL = executable
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        // Do not record server logs, credentials, or raw account responses.
        child.standardError = FileHandle.nullDevice
        child.standardInput = stdin
        child.standardOutput = stdout
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        process = child
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            Task { await self?.receive(bytes) }
        }
        child.terminationHandler = { [weak self] _ in
            Task { await self?.connectionClosed() }
        }
        do { try child.run() }
        catch { stop(); throw error }
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw MeterError.disconnected }
        var bytes = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        bytes.append(0x0A)
        try input.write(contentsOf: bytes)
    }

    private func request<T: Decodable>(_ method: String, params: [String: Any]) async throws -> T {
        nextID += 1
        let id = nextID
        let bytes: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                self.expire(id)
            }
        }
        do { return try JSONDecoder().decode(T.self, from: bytes) }
        catch { throw MeterError.invalidResponse }
    }

    private func receive(_ bytes: Data) {
        guard !bytes.isEmpty else { connectionClosed(); return }
        buffer.append(bytes)
        guard buffer.count <= 8_388_608 else { stop(); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            // Reject server-initiated requests; this utility only reads metadata.
            if message["method"] != nil, let id = message["id"] {
                try? send(["id": id, "error": ["code": -32601, "message": "Unsupported by usage reader"]])
                continue
            }
            guard let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) else { continue }
            if let error = message["error"] as? [String: Any] {
                // Keep arbitrary backend details out of the UI and diagnostic output.
                let code = error["code"] as? Int ?? -1
                continuation.resume(throwing: MeterError.remote("Usage request failed (code \(code)). Check Codex sign-in and try again."))
            } else if let result = message["result"],
                      let data = try? JSONSerialization.data(withJSONObject: result) {
                continuation.resume(returning: data)
            } else { continuation.resume(throwing: MeterError.invalidResponse) }
        }
    }

    private func expire(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: MeterError.timeout)
    }

    private func connectionClosed() {
        let waiting = pending.values
        pending.removeAll()
        for continuation in waiting { continuation.resume(throwing: MeterError.disconnected) }
    }

    private func stop() {
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        try? input?.close()
        if let child = process, child.isRunning { child.terminate() }
        input = nil; output = nil; process = nil
        buffer.removeAll()
        connectionClosed()
    }
}

private struct EmptyResponse: Decodable {}
private struct AccountResponse: Decodable {
    struct Account: Decodable { let type: String }
    let account: Account?
}
