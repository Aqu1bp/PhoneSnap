import Foundation
import Network

final class WirelessReceiver {
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

    typealias UploadHandler = (Data) -> Bool
    typealias StateHandler = (State) -> Void

    private let port: UInt16
    private let pairing: WirelessPairing
    private let uploadHandler: UploadHandler
    private let stateHandler: StateHandler
    private let queue = DispatchQueue(label: "phonesnap.wireless")
    private let maxBody = 32 * 1024 * 1024
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: WirelessHTTPSession] = [:]
    private let sessionsLock = NSLock()

    init(port: UInt16,
         pairing: WirelessPairing,
         uploadHandler: @escaping UploadHandler,
         stateHandler: @escaping StateHandler) {
        self.port = port
        self.pairing = pairing
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
        listener?.cancel()
        listener = nil
        sessionsLock.lock()
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        sessionsLock.unlock()
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
            primaryBaseURL: primaryBaseURL,
            uploadHandler: uploadHandler
        )
        retain(session)
        session.onFinished = { [weak self, weak session] in
            guard let session else { return }
            self?.release(session)
        }
        session.start()
    }

    private func retain(_ session: WirelessHTTPSession) {
        sessionsLock.lock()
        sessions[ObjectIdentifier(session)] = session
        sessionsLock.unlock()
    }

    private func release(_ session: WirelessHTTPSession) {
        sessionsLock.lock()
        sessions.removeValue(forKey: ObjectIdentifier(session))
        sessionsLock.unlock()
    }
}

private final class WirelessHTTPSession {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let maxBody: Int
    private let port: UInt16
    private let pairing: WirelessPairing
    private let primaryBaseURL: String
    private let uploadHandler: (Data) -> Bool
    private var buffer = Data()
    private var headersParsed = false
    private var method = ""
    private var target = ""
    private var headers: [String: String] = [:]
    private var contentLength = 0
    private var body = Data()
    private var didFinish = false
    private var responseQueued = false

    var onFinished: (() -> Void)?

    init(connection: NWConnection,
         queue: DispatchQueue,
         maxBody: Int,
         port: UInt16,
         pairing: WirelessPairing,
         primaryBaseURL: String,
         uploadHandler: @escaping (Data) -> Bool) {
        self.connection = connection
        self.queue = queue
        self.maxBody = maxBody
        self.port = port
        self.pairing = pairing
        self.primaryBaseURL = primaryBaseURL
        self.uploadHandler = uploadHandler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
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
        finishAndCancel()
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
                        self.respond(status: "400 Bad Request", text: "headers too large")
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
        guard parts.count >= 2 else {
            respond(status: "400 Bad Request", text: "bad request line")
            return true
        }

        method = String(parts[0])
        target = String(parts[1])
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if contentLength > maxBody {
            headersParsed = true
            contentLength = 0
            body = Data()
            respond(status: "413 Payload Too Large", text: "request body limit is 32 MB")
            return true
        }

        headersParsed = true
        return true
    }

    private func handleRequest() {
        let path = Self.pathOnly(from: target)
        Log.info("Wireless HTTP \(method) \(path) (\(body.count) body bytes)")
        if method == "GET" || method == "HEAD" {
            if path == "/pair/\(pairing.pairID)" || path == "/pair/\(pairing.pairID)/" {
                handleSetupPage()
                return
            }
            if path == "/pair/\(pairing.pairID)/PhoneSnap.shortcut" {
                handleShortcutDownload()
                return
            }
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
        let body = method == "HEAD" ? Data() : Data(setupHTML().utf8)
        respondData(
            status: "200 OK",
            body: body,
            contentType: "text/html; charset=utf-8"
        )
    }

    private func handleShortcutDownload() {
        guard method == "GET" || method == "HEAD" else {
            respond(status: "405 Method Not Allowed", text: "GET only")
            return
        }
        do {
            let uploadURL = "\(requestBaseURL())/api/v1/upload/\(pairing.pairID)"
            let bytes = method == "HEAD"
                ? Data()
                : try WirelessShortcutGenerator.makeSigned(uploadURL: uploadURL, token: pairing.token)
            Log.info("Generated PhoneSnap.shortcut for \(uploadURL) (\(bytes.count) bytes)")
            respondData(
                status: "200 OK",
                body: bytes,
                contentType: "application/x-apple-shortcut",
                extraHeaders: ["Cache-Control": "no-store"]
            )
        } catch {
            let message = error.localizedDescription
            Log.error("Shortcut generation failed: \(message)")
            respond(status: "500 Internal Server Error", text: "PhoneSnap could not generate the Shortcut.\n\n\(message)")
        }
    }

    private func handleUpload() {
        guard method == "POST" else {
            respond(status: "405 Method Not Allowed", text: "POST only")
            return
        }
        guard isAuthorized() else {
            respond(status: "401 Unauthorized", text: "missing or invalid PhoneSnap token", extraHeaders: [
                "WWW-Authenticate": "Bearer"
            ])
            return
        }
        guard !body.isEmpty else {
            respond(status: "400 Bad Request", text: "empty upload body")
            return
        }

        let contentType = headers["content-type"] ?? ""
        let imageData: Data
        if contentType.lowercased().contains("multipart/form-data"),
           let extracted = Self.extractImageFromMultipart(body: body, contentType: contentType) {
            imageData = extracted
        } else {
            imageData = body
        }

        let ok = uploadHandler(imageData)
        if ok {
            respond(
                status: "200 OK",
                text: "{\"ok\":true,\"bytes\":\(imageData.count)}",
                contentType: "application/json"
            )
        } else {
            respond(status: "415 Unsupported Media Type", text: "PhoneSnap could not decode an image from the upload")
        }
    }

    private func isAuthorized() -> Bool {
        guard let authorization = headers["authorization"] else { return false }
        return Self.constantTimeEquals(authorization, "Bearer \(pairing.token)")
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
        let setupURL = "\(requestBaseURL())/pair/\(pairing.pairID)"
        let shortcutURL = "\(setupURL)/PhoneSnap.shortcut"
        let escapedSetupURL = Self.htmlEscape(setupURL)
        let escapedShortcutURL = Self.htmlEscape(shortcutURL)
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
            <p class="note">Setup page: <code>\(escapedSetupURL)</code></p>
          </main>
        </body>
        </html>
        """
    }

    private func requestBaseURL() -> String {
        guard let host = headers["host"].flatMap(Self.safeHostHeader), !host.isEmpty else {
            return primaryBaseURL
        }
        if host.contains(":") || host.hasPrefix("[") {
            return "http://\(host)"
        }
        return "http://\(host):\(port)"
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
                             extraHeaders: [String: String] = [:]) {
        guard !responseQueued else { return }
        responseQueued = true
        Log.info("Wireless HTTP → \(status) for \(method) \(Self.pathOnly(from: target))")
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
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
        connection.cancel()
        onFinished?()
    }

    private func finish() {
        if didFinish { return }
        didFinish = true
        onFinished?()
    }

    private static func pathOnly(from target: String) -> String {
        let rawPath = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? target
        return rawPath.removingPercentEncoding ?? rawPath
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
        guard let boundaryRange = contentType.range(of: "boundary=") else { return nil }
        var boundary = String(contentType[boundaryRange.upperBound...])
        if let separator = boundary.firstIndex(of: ";") {
            boundary = String(boundary[..<separator])
        }
        boundary = boundary.trimmingCharacters(in: .whitespaces)
        if boundary.hasPrefix("\""), boundary.hasSuffix("\""), boundary.count >= 2 {
            boundary = String(boundary.dropFirst().dropLast())
        }
        guard !boundary.isEmpty else { return nil }

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
}
