import Foundation
import Network

final class WirelessReceiver {
    enum UploadResult {
        case accepted
        case invalidImage
        case storageFailure
    }

    enum State: Equatable {
        case stopped
        case starting
        case ready
        case failed(String)

        var menuTitle: String {
            switch self {
            case .stopped:
                return "Wireless Shortcut batch receiver: stopped"
            case .starting:
                return "Wireless Shortcut batch receiver: starting"
            case .ready:
                return "Wireless Shortcut batch receiver: ready"
            case .failed(let message):
                return "Wireless Shortcut batch receiver: unavailable - \(message)"
            }
        }
    }

    typealias UploadHandler = (Data) -> UploadResult
    typealias StateHandler = (State) -> Void

    private let port: UInt16
    private let pairing: WirelessPairing
    private let batchCount: Int
    private let uploadHandler: UploadHandler
    private let stateHandler: StateHandler
    private let queue = DispatchQueue(label: "phonesnap.wireless")
    private let maxBody = 32 * 1024 * 1024
    private let maxSessions = 4
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: WirelessHTTPSession] = [:]
    private let sessionsLock = NSLock()
    private var isAcceptingConnections = false

    init(port: UInt16,
         pairing: WirelessPairing,
         batchCount: Int = 10,
         uploadHandler: @escaping UploadHandler,
         stateHandler: @escaping StateHandler) {
        self.port = port
        self.pairing = pairing
        self.batchCount = batchCount
        self.uploadHandler = uploadHandler
        self.stateHandler = stateHandler
    }

    func start() throws {
        stateHandler(.starting)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        // Deliberately NOT advertised over Bonjour: broadcasting the pair ID
        // would let any LAN peer fetch the setup page and extract the bearer
        // token from the generated Shortcut. The QR code / setup URL is the
        // only distribution channel for the pair ID.
        self.listener = listener
        sessionsLock.lock()
        isAcceptingConnections = true
        sessionsLock.unlock()
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.info("Wireless receiver listening on \(self.primaryBaseURL)")
                self.stateHandler(.ready)
            case .failed(let error):
                Log.error("Wireless receiver failed: \(error)")
                self.sessionsLock.lock()
                self.isAcceptingConnections = false
                self.sessionsLock.unlock()
                self.stateHandler(.failed(error.localizedDescription))
            case .cancelled:
                self.stateHandler(.stopped)
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        sessionsLock.lock()
        isAcceptingConnections = false
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        sessionsLock.unlock()
        listener?.cancel()
        listener = nil
        activeSessions.forEach { $0.cancel() }
        stateHandler(.stopped)
    }

    private var primaryBaseURL: String {
        "http://\(LANAddress.bonjourHostName()):\(port)"
    }

    private func accept(_ connection: NWConnection) {
        let session = WirelessHTTPSession(
            connection: connection,
            queue: queue,
            maxBody: maxBody,
            port: port,
            pairing: pairing,
            batchCount: batchCount,
            primaryBaseURL: primaryBaseURL,
            uploadHandler: uploadHandler
        )
        session.onFinished = { [weak self, weak session] in
            guard let session else { return }
            self?.release(session)
        }
        guard retain(session) else {
            Log.error("Wireless receiver rejected a connection because the session limit was reached")
            session.cancel()
            return
        }
        session.start()
    }

    private func retain(_ session: WirelessHTTPSession) -> Bool {
        var evicted: WirelessHTTPSession?
        sessionsLock.lock()
        guard isAcceptingConnections else {
            sessionsLock.unlock()
            return false
        }
        if sessions.count >= maxSessions {
            guard let entry = sessions.first(where: { $0.value.isAwaitingHeaders }) else {
                sessionsLock.unlock()
                return false
            }
            sessions.removeValue(forKey: entry.key)
            evicted = entry.value
        }
        sessions[ObjectIdentifier(session)] = session
        sessionsLock.unlock()
        // A new connection must not be starved by idle unauthenticated peers.
        // Cancellation is marshalled back onto the receiver queue.
        evicted?.cancel()
        return true
    }

    private func release(_ session: WirelessHTTPSession) {
        sessionsLock.lock()
        sessions.removeValue(forKey: ObjectIdentifier(session))
        sessionsLock.unlock()
    }
}

private final class WirelessHTTPSession {
    private enum ProcessedUpload {
        case malformedMultipart
        case completed(WirelessReceiver.UploadResult, byteCount: Int)
    }

    /// Raster decoding and disk I/O never run on the network callback queue.
    /// Serial execution also bounds aggregate decoder memory.
    private static let uploadQueue = DispatchQueue(label: "phonesnap.upload-processing", qos: .userInitiated)

    private static let signingQueue = DispatchQueue(label: "phonesnap.shortcut-signing")
    private static let signingLock = NSLock()
    private static var signingInProgress = false

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let maxBody: Int
    private let port: UInt16
    private let pairing: WirelessPairing
    private let batchCount: Int
    private let primaryBaseURL: String
    private let uploadHandler: (Data) -> WirelessReceiver.UploadResult
    private var buffer = Data()
    private var headersParsed = false
    private var method = ""
    private var target = ""
    private var headers: [String: String] = [:]
    private var contentLength = 0
    private var body = Data()
    private var didFinish = false
    private var responseQueued = false
    private var requestTimeout: DispatchWorkItem?

    var onFinished: (() -> Void)?

    /// Read only by WirelessReceiver on the same serial network queue.
    var isAwaitingHeaders: Bool {
        !headersParsed && !responseQueued && !didFinish
    }

    init(connection: NWConnection,
         queue: DispatchQueue,
         maxBody: Int,
         port: UInt16,
         pairing: WirelessPairing,
         batchCount: Int,
         primaryBaseURL: String,
         uploadHandler: @escaping (Data) -> WirelessReceiver.UploadResult) {
        self.connection = connection
        self.queue = queue
        self.maxBody = maxBody
        self.port = port
        self.pairing = pairing
        self.batchCount = batchCount
        self.primaryBaseURL = primaryBaseURL
        self.uploadHandler = uploadHandler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.scheduleRequestTimeout(after: 5, message: "request headers did not arrive within 5 seconds")
                self?.receive()
            case .failed(let error):
                Log.error("Wireless HTTP connection failed: \(error)")
                self?.finishAndCancel()
            case .cancelled:
                self?.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        queue.async { [self] in finishAndCancel() }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                Log.error("Wireless HTTP receive failed: \(error)")
                self.finishAndCancel()
                return
            }

            if let data, !data.isEmpty {
                self.buffer.append(data)
                if !self.headersParsed {
                    if !self.tryParseHeaders(), self.buffer.count > 64 * 1024 {
                        self.respond(status: "431 Request Header Fields Too Large", text: "headers too large")
                        return
                    }
                    if self.responseQueued {
                        return
                    }
                }

                if self.headersParsed {
                    let needed = self.contentLength - self.body.count
                    if needed > 0 {
                        let take = min(self.buffer.count, needed)
                        self.body.append(self.buffer.prefix(take))
                        self.buffer.removeFirst(take)
                    }
                    if self.body.count >= self.contentLength {
                        self.handleRequest()
                        return
                    }
                }
            }

            if isComplete {
                if self.headersParsed && self.body.count >= self.contentLength {
                    self.handleRequest()
                } else {
                    self.respond(status: "400 Bad Request", text: "incomplete request")
                }
                return
            }
            self.receive()
        }
    }

    @discardableResult
    private func tryParseHeaders() -> Bool {
        guard let endRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return false
        }
        guard endRange.upperBound <= 64 * 1024 else {
            headersParsed = true
            respond(status: "431 Request Header Fields Too Large", text: "headers too large")
            return true
        }
        let head = buffer.prefix(upTo: endRange.lowerBound)
        buffer.removeSubrange(buffer.startIndex..<endRange.upperBound)
        guard let headString = String(data: head, encoding: .utf8) else {
            respond(status: "400 Bad Request", text: "bad header bytes")
            return true
        }

        let lines = headString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            respond(status: "400 Bad Request", text: "missing request line")
            return true
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else {
            respond(status: "400 Bad Request", text: "bad request line")
            return true
        }

        method = String(parts[0])
        target = String(parts[1])
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if key == "content-length", headers[key] != nil {
                headersParsed = true
                respond(status: "400 Bad Request", text: "duplicate Content-Length")
                return true
            }
            headers[key] = value
        }

        if let rawLength = headers["content-length"] {
            guard !rawLength.isEmpty,
                  rawLength.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  let parsed = Int(rawLength) else {
                headersParsed = true
                respond(status: "400 Bad Request", text: "invalid Content-Length")
                return true
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        headersParsed = true

        guard validateRequestHeaders() else { return true }

        if let transferEncoding = headers["transfer-encoding"],
           transferEncoding.lowercased() != "identity" {
            contentLength = 0
            body = Data()
            respond(status: "501 Not Implemented", text: "Transfer-Encoding is not supported; send a Content-Length body")
            return true
        }

        if Self.pathOnly(from: target) == "/api/v1/upload/\(pairing.pairID)",
           headers["content-length"] == nil {
            respond(status: "411 Length Required", text: "POST requests must include Content-Length")
            return true
        }

        if contentLength > maxBody {
            contentLength = 0
            body = Data()
            respond(status: "413 Payload Too Large", text: "request body limit is 32 MB")
            return true
        }

        if Self.pathOnly(from: target) == "/api/v1/upload/\(pairing.pairID)" {
            let mediaType = Self.mediaType(from: headers["content-type"] ?? "")
            guard mediaType.hasPrefix("image/") || mediaType == "multipart/form-data" else {
                respond(status: "415 Unsupported Media Type", text: "upload Content-Type must be image/* or multipart/form-data")
                return true
            }
        }

        if let expectation = headers["expect"] {
            guard expectation.caseInsensitiveCompare("100-continue") == .orderedSame else {
                respond(status: "417 Expectation Failed", text: "unsupported Expect header")
                return true
            }
            sendContinue()
        }
        scheduleRequestTimeout(after: 30, message: "request did not complete within 30 seconds")
        return true
    }

    private func validateRequestHeaders() -> Bool {
        let path = Self.pathOnly(from: target)
        let setupPath = "/pair/\(pairing.pairID)"
        let shortcutPath = "\(setupPath)/PhoneSnap.shortcut"
        let uploadPath = "/api/v1/upload/\(pairing.pairID)"

        if path == setupPath || path == "\(setupPath)/" || path == shortcutPath {
            guard method == "GET" || method == "HEAD" else {
                respond(status: "405 Method Not Allowed", text: "GET or HEAD only", extraHeaders: ["Allow": "GET, HEAD"])
                return false
            }
            return true
        }

        if path == uploadPath {
            guard method == "POST" else {
                respond(status: "405 Method Not Allowed", text: "POST only", extraHeaders: ["Allow": "POST"])
                return false
            }
            guard isAuthorized() else {
                respond(status: "401 Unauthorized", text: "missing or invalid PhoneSnap token", extraHeaders: [
                    "WWW-Authenticate": "Bearer"
                ])
                return false
            }
            return true
        }

        respond(status: "404 Not Found", text: "PhoneSnap wireless route not found")
        return false
    }

    private func handleRequest() {
        // The read deadline has done its job once the complete request is in
        // memory. Processing has separately bounded resources; leaving this
        // timer armed could return 408 and then save an upload afterwards.
        requestTimeout?.cancel()
        requestTimeout = nil
        let path = Self.pathOnly(from: target)
        Log.info("Wireless HTTP \(Self.logMethod(method)) \(Self.logPath(path)) (\(body.count) body bytes)")
        if path == "/pair/\(pairing.pairID)" || path == "/pair/\(pairing.pairID)/" {
            handleSetupPage()
            return
        }
        if path == "/pair/\(pairing.pairID)/PhoneSnap.shortcut" {
            handleShortcutDownload()
            return
        }

        if path == "/api/v1/upload/\(pairing.pairID)" {
            handleUpload()
            return
        }

        respond(status: "404 Not Found", text: "PhoneSnap wireless route not found")
    }

    private func handleSetupPage() {
        guard method == "GET" || method == "HEAD" else {
            respond(status: "405 Method Not Allowed", text: "GET only")
            return
        }
        let representation = Data(setupHTML().utf8)
        let body = method == "HEAD" ? Data() : representation
        respondData(
            status: "200 OK",
            body: body,
            contentType: "text/html; charset=utf-8",
            contentLength: representation.count,
            extraHeaders: [
                "Cache-Control": "no-store",
                "Referrer-Policy": "no-referrer",
                "X-Content-Type-Options": "nosniff"
            ]
        )
    }

    private func handleShortcutDownload() {
        guard method == "GET" || method == "HEAD" else {
            respond(status: "405 Method Not Allowed", text: "GET only")
            return
        }
        let uploadURL = "\(requestBaseURL())/api/v1/upload/\(pairing.pairID)"
        if method == "HEAD" {
            respondData(
                status: "200 OK",
                body: Data(),
                contentType: "application/x-apple-shortcut",
                extraHeaders: ["Cache-Control": "no-store"]
            )
            return
        }
        guard Self.beginSigning() else {
            respond(
                status: "503 Service Unavailable",
                text: "PhoneSnap is already generating a Shortcut; try again shortly",
                extraHeaders: ["Retry-After": "5"]
            )
            return
        }
        // The generator has its own 30-second process timeout plus a short
        // termination/drain grace period. Keep the HTTP deadline outside it
        // so the useful generator error remains visible to the client.
        scheduleRequestTimeout(after: 40, message: "Shortcut generation did not complete within 40 seconds")
        let token = pairing.token
        let batchCount = self.batchCount
        Self.signingQueue.async { [weak self] in
            defer { Self.endSigning() }
            guard let self else { return }
            let result = Result {
                try WirelessShortcutGenerator.makeSigned(uploadURL: uploadURL, token: token, batchCount: batchCount)
            }
            self.queue.async {
                switch result {
                case .success(let bytes):
                    Log.info("Generated PhoneSnap.shortcut for paired receiver (\(bytes.count) bytes)")
                    self.respondData(
                        status: "200 OK",
                        body: bytes,
                        contentType: "application/x-apple-shortcut",
                        extraHeaders: ["Cache-Control": "no-store"]
                    )
                case .failure(let error):
                    let message = error.localizedDescription
                    Log.error("Shortcut generation failed: \(message)")
                    self.respond(status: "500 Internal Server Error", text: "PhoneSnap could not generate the Shortcut.\n\n\(message)")
                }
            }
        }
    }

    private func handleUpload() {
        guard !body.isEmpty else {
            respond(status: "400 Bad Request", text: "empty upload body")
            return
        }

        let requestBody = body
        let contentType = headers["content-type"] ?? ""
        let uploadHandler = self.uploadHandler
        Self.uploadQueue.async { [weak self] in
            guard let self else { return }
            let processed: ProcessedUpload
            if Self.mediaType(from: contentType) == "multipart/form-data" {
                guard let extracted = Self.extractImageFromMultipart(body: requestBody, contentType: contentType) else {
                    self.queue.async { self.finishUpload(.malformedMultipart) }
                    return
                }
                processed = .completed(uploadHandler(extracted), byteCount: extracted.count)
            } else {
                processed = .completed(uploadHandler(requestBody), byteCount: requestBody.count)
            }
            self.queue.async { self.finishUpload(processed) }
        }
    }

    private func finishUpload(_ processed: ProcessedUpload) {
        switch processed {
        case .malformedMultipart:
            respond(status: "415 Unsupported Media Type", text: "multipart upload did not contain a valid image part")
        case .completed(.accepted, let byteCount):
            respond(
                status: "200 OK",
                text: "{\"ok\":true,\"bytes\":\(byteCount)}",
                contentType: "application/json"
            )
        case .completed(.invalidImage, _):
            respond(status: "415 Unsupported Media Type", text: "PhoneSnap could not decode an image from the upload")
        case .completed(.storageFailure, _):
            respond(status: "500 Internal Server Error", text: "PhoneSnap could not store the uploaded image")
        }
    }

    private func isAuthorized() -> Bool {
        guard let authorization = headers["authorization"] else { return false }
        let parts = authorization.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2,
              String(parts[0]).caseInsensitiveCompare("Bearer") == .orderedSame else { return false }
        return Self.constantTimeEquals(String(parts[1]), pairing.token)
    }

    /// Compares the full strings even on early mismatch so response timing
    /// does not leak how many leading characters of the token were correct.
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }

    private func setupHTML() -> String {
        let baseURL = requestBaseURL()
        let setupURL = "\(baseURL)/pair/\(pairing.pairID)"
        let shortcutURL = "\(setupURL)/PhoneSnap.shortcut"
        let escapedSetupURL = Self.htmlEscape(setupURL)
        let escapedShortcutURL = Self.htmlEscape(shortcutURL)
        // The Shortcut bakes in the host this page was reached through. A raw
        // IP stops working when the Mac's address changes, so warn up front.
        let ipNote = Self.isIPBaseURL(baseURL)
            ? """
            <p class="note"><strong>Heads up:</strong> you opened this page with the Mac\u{2019}s IP address, so the Shortcut will use that IP. If the Mac\u{2019}s IP changes (for example after a router restart), rerun setup from PhoneSnap\u{2019}s QR code and re-add the Shortcut.</p>
            """
            : ""
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Set Up PhoneSnap</title>
          <style>
            body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; color: #111; background: #f6f6f6; }
            main { max-width: 520px; margin: 0 auto; padding: 28px 20px 40px; }
            h1 { font-size: 26px; margin: 0 0 12px; }
            p { font-size: 16px; line-height: 1.45; color: #333; }
            a.button { display: block; margin: 24px 0 16px; padding: 14px 18px; border-radius: 10px; background: #111; color: white; text-align: center; text-decoration: none; font-weight: 650; }
            code { word-break: break-all; font-size: 12px; color: #555; }
            .note { font-size: 14px; color: #666; }
          </style>
        </head>
        <body>
          <main>
            <h1>Set Up PhoneSnap</h1>
            <p>Open the signed PhoneSnap Shortcut on this iPhone, then tap Add Shortcut in Shortcuts. It sends the recent screenshot batch to this Mac.</p>
            <a class="button" href="\(escapedShortcutURL)">Open PhoneSnap Shortcut</a>
            <p class="note">iOS will still ask you to add the Shortcut. The first run may also ask for Photos or local-network permission.</p>
            \(ipNote)
            <p class="note">Setup page: <code>\(escapedSetupURL)</code></p>
          </main>
        </body>
        </html>
        """
    }

    private func requestBaseURL() -> String {
        guard let host = headers["host"].flatMap(trustedHostHeader), !host.isEmpty else {
            return primaryBaseURL
        }
        if host.hasPrefix("[") {
            // Bracketed IPv6 literal: colons inside the brackets are not a
            // port, so only reuse the host as-is when "]:port" is present.
            return host.contains("]:") ? "http://\(host)" : "http://\(host):\(port)"
        }
        if host.contains(":") {
            return "http://\(host)"
        }
        return "http://\(host):\(port)"
    }

    /// Only the hostnames PhoneSnap itself offers in the setup window may be
    /// reflected into a token-bearing Shortcut. Accepting an arbitrary Host
    /// header here would turn DNS rebinding into credential exfiltration.
    private func trustedHostHeader(_ value: String) -> String? {
        guard let safe = Self.safeHostHeader(value) else { return nil }

        let host: String
        let explicitPort: UInt16?
        if safe.hasPrefix("["), let closing = safe.firstIndex(of: "]") {
            host = String(safe[safe.index(after: safe.startIndex)..<closing])
            let remainder = safe[safe.index(after: closing)...]
            if remainder.isEmpty {
                explicitPort = nil
            } else if remainder.hasPrefix(":"), let parsed = UInt16(remainder.dropFirst()) {
                explicitPort = parsed
            } else {
                return nil
            }
        } else if let separator = safe.lastIndex(of: ":") {
            host = String(safe[..<separator])
            guard let parsed = UInt16(safe[safe.index(after: separator)...]) else { return nil }
            explicitPort = parsed
        } else {
            host = safe
            explicitPort = nil
        }

        guard explicitPort == nil || explicitPort == port else { return nil }
        let allowed = [
            LANAddress.bonjourHostName(),
            LANAddress.currentIPv4(),
            "localhost",
            "127.0.0.1",
            "::1"
        ].compactMap { $0?.lowercased() }
        guard allowed.contains(host.lowercased()) else { return nil }
        return safe
    }

    private func respond(status: String,
                         text: String,
                         contentType: String = "text/plain; charset=utf-8",
                         extraHeaders: [String: String] = [:]) {
        respondData(
            status: status,
            body: Data(text.utf8),
            contentType: contentType,
            extraHeaders: extraHeaders
        )
    }

    private func respondData(status: String,
                             body: Data,
                             contentType: String,
                             contentLength: Int? = nil,
                             extraHeaders: [String: String] = [:]) {
        guard !responseQueued, !didFinish else { return }
        responseQueued = true
        requestTimeout?.cancel()
        requestTimeout = nil
        Log.info("Wireless HTTP → \(status) for \(Self.logMethod(method)) \(Self.logPath(Self.pathOnly(from: target)))")
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(contentLength ?? body.count)\r\n"
        for (key, value) in extraHeaders {
            header += "\(key): \(value)\r\n"
        }
        header += "Connection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, isComplete: true, completion: .contentProcessed { [weak self] error in
            if let error {
                Log.error("Wireless HTTP send failed: \(error)")
            }
            self?.finishAndCancel()
        })
    }

    private func finishAndCancel() {
        if didFinish { return }
        didFinish = true
        requestTimeout?.cancel()
        requestTimeout = nil
        connection.cancel()
        onFinished?()
    }

    private func finish() {
        if didFinish { return }
        didFinish = true
        requestTimeout?.cancel()
        requestTimeout = nil
        onFinished?()
    }

    private func scheduleRequestTimeout(after interval: TimeInterval, message: String) {
        requestTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.responseQueued, !self.didFinish else { return }
            self.respond(status: "408 Request Timeout", text: message)
        }
        requestTimeout = work
        queue.asyncAfter(deadline: .now() + interval, execute: work)
    }

    private func sendContinue() {
        let packet = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error {
                Log.error("Wireless HTTP 100 Continue send failed: \(error)")
            }
        })
    }

    private static func pathOnly(from target: String) -> String {
        let rawPath = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? target
        return rawPath.removingPercentEncoding ?? rawPath
    }

    private static func logPath(_ path: String) -> String {
        if path.hasPrefix("/api/v1/upload/") { return "/api/v1/upload/<redacted>" }
        if path.hasPrefix("/pair/") {
            return path.hasSuffix("/PhoneSnap.shortcut")
                ? "/pair/<redacted>/PhoneSnap.shortcut"
                : "/pair/<redacted>"
        }
        return "<unknown>"
    }

    private static func logMethod(_ method: String) -> String {
        switch method {
        case "GET", "HEAD", "POST": return method
        default: return "<unknown>"
        }
    }

    private static func beginSigning() -> Bool {
        signingLock.lock()
        defer { signingLock.unlock() }
        guard !signingInProgress else { return false }
        signingInProgress = true
        return true
    }

    private static func endSigning() {
        signingLock.lock()
        signingInProgress = false
        signingLock.unlock()
    }

    private static func mediaType(from contentType: String) -> String {
        contentType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            ?? ""
    }

    private static func isIPBaseURL(_ base: String) -> Bool {
        var host = base
        if let schemeRange = host.range(of: "://") {
            host = String(host[schemeRange.upperBound...])
        }
        if host.hasPrefix("[") {
            return true // bracketed IPv6 literal
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        let octets = host.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func safeHostHeader(_ value: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_:[]"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return value
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func extractImageFromMultipart(body: Data, contentType: String) -> Data? {
        guard let boundary = multipartBoundary(from: contentType) else { return nil }

        let delimiter = Data(("--" + boundary).utf8)
        var cursor = body.startIndex
        while let nextDelimiter = body.range(of: delimiter, in: cursor..<body.endIndex) {
            let afterDelimiter = nextDelimiter.upperBound
            if afterDelimiter + 2 <= body.endIndex,
               body[afterDelimiter] == 0x2D,
               body[afterDelimiter + 1] == 0x2D {
                return nil
            }

            var partStart = afterDelimiter
            if partStart + 2 <= body.endIndex,
               body[partStart] == 0x0D,
               body[partStart + 1] == 0x0A {
                partStart += 2
            }
            guard let headerEnd = body.range(of: Data("\r\n\r\n".utf8), in: partStart..<body.endIndex) else {
                cursor = afterDelimiter
                continue
            }

            let partHeaders = body[partStart..<headerEnd.lowerBound]
            let partBodyStart = headerEnd.upperBound
            let nextBoundary = body.range(of: delimiter, in: partBodyStart..<body.endIndex)?.lowerBound ?? body.endIndex
            var partBodyEnd = nextBoundary
            if partBodyEnd >= 2,
               body[partBodyEnd - 1] == 0x0A,
               body[partBodyEnd - 2] == 0x0D {
                partBodyEnd -= 2
            }

            if let headerString = String(data: partHeaders, encoding: .utf8) {
                let lower = headerString.lowercased()
                if lower.contains("content-type: image/") || lower.contains("filename=") {
                    return body.subdata(in: partBodyStart..<partBodyEnd)
                }
            }
            cursor = nextBoundary
        }
        return nil
    }

    private static func multipartBoundary(from contentType: String) -> String? {
        let components = contentType.split(separator: ";", omittingEmptySubsequences: false)
        guard components.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("multipart/form-data") == .orderedSame else { return nil }

        for component in components.dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("boundary") == .orderedSame else { continue }
            var boundary = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if boundary.hasPrefix("\""), boundary.hasSuffix("\""), boundary.count >= 2 {
                boundary = String(boundary.dropFirst().dropLast())
            }
            guard !boundary.isEmpty, boundary.utf8.count <= 200 else { return nil }
            return boundary
        }
        return nil
    }
}
