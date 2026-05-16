import Foundation
import Network

final class HTTPListener {
    typealias Handler = (Data) -> Bool

    private let port: UInt16
    private let handler: Handler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "screenshotcatch.net")
    private let maxBody = 32 * 1024 * 1024 // 32 MB cap
    private var sessions: [ObjectIdentifier: HTTPSession] = [:]
    private let sessionsLock = NSLock()

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    fileprivate func retain(_ session: HTTPSession) {
        sessionsLock.lock(); defer { sessionsLock.unlock() }
        sessions[ObjectIdentifier(session)] = session
    }
    fileprivate func release(_ session: HTTPSession) {
        sessionsLock.lock(); defer { sessionsLock.unlock() }
        sessions.removeValue(forKey: ObjectIdentifier(session))
    }

    func start() throws {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: Log.info("Listener ready")
            case .failed(let err): Log.error("Listener failed: \(err)")
            case .cancelled: Log.info("Listener cancelled")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    private func accept(_ conn: NWConnection) {
        let session = HTTPSession(connection: conn, queue: queue, maxBody: maxBody) { [weak self] data in
            self?.handler(data) ?? false
        }
        retain(session)
        session.onFinished = { [weak self, weak session] in
            if let session { self?.release(session) }
        }
        session.start()
    }
}

fileprivate final class HTTPSession {
    private let conn: NWConnection
    private let queue: DispatchQueue
    private let maxBody: Int
    private let handle: (Data) -> Bool
    var onFinished: (() -> Void)?
    private var buffer = Data()
    private var headersParsed = false
    private var method = ""
    private var path = ""
    private var headers: [String: String] = [:]
    private var contentLength = 0
    private var body = Data()
    private var didFinish = false

    init(connection: NWConnection, queue: DispatchQueue, maxBody: Int, handle: @escaping (Data) -> Bool) {
        self.conn = connection
        self.queue = queue
        self.maxBody = maxBody
        self.handle = handle
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive()
            case .failed(let err):
                Log.error("conn failed: \(err)")
                self?.conn.cancel()
            case .cancelled:
                self?.finishAndCancel()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                Log.error("recv error: \(error)")
                self.finish()
                return
            }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if !self.headersParsed {
                    if self.tryParseHeaders() {
                        // valid request, now read body
                    } else if self.buffer.count > 64 * 1024 {
                        Log.error("Headers too large")
                        self.respond(status: "400 Bad Request", body: "headers too large")
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
                    self.respond(status: "400 Bad Request", body: "incomplete request")
                }
                return
            }
            self.receive()
        }
    }

    private func tryParseHeaders() -> Bool {
        guard let endRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = buffer.prefix(upTo: endRange.lowerBound)
        buffer.removeSubrange(buffer.startIndex..<endRange.upperBound)
        guard let headStr = String(data: head, encoding: .utf8) else {
            respond(status: "400 Bad Request", body: "bad header bytes")
            return true
        }
        let lines = headStr.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            respond(status: "400 Bad Request", body: "no request line")
            return true
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(status: "400 Bad Request", body: "bad request line")
            return true
        }
        method = String(parts[0])
        path = String(parts[1])
        for line in lines.dropFirst() where !line.isEmpty {
            if let idx = line.firstIndex(of: ":") {
                let key = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if contentLength > maxBody {
            respond(status: "413 Payload Too Large", body: "max \(maxBody) bytes")
            headersParsed = true
            contentLength = 0
            body = Data()
            return true
        }
        headersParsed = true
        return true
    }

    private func handleRequest() {
        guard path == "/screenshot" else {
            respond(status: "404 Not Found", body: "use POST /screenshot")
            return
        }
        guard method == "POST" else {
            respond(status: "405 Method Not Allowed", body: "POST only")
            return
        }
        guard !body.isEmpty else {
            respond(status: "400 Bad Request", body: "empty body")
            return
        }
        let imageData: Data
        let contentType = headers["content-type"] ?? ""
        if contentType.lowercased().contains("multipart/form-data") {
            if let extracted = Self.extractFromMultipart(body: body, contentType: contentType) {
                imageData = extracted
            } else {
                imageData = body
            }
        } else {
            imageData = body
        }
        let ok = handle(imageData)
        if ok {
            let json = "{\"ok\":true,\"bytes\":\(imageData.count)}"
            respond(status: "200 OK", body: json, contentType: "application/json")
        } else {
            respond(status: "415 Unsupported Media Type", body: "could not decode image")
        }
    }

    private func respond(status: String, body: String, contentType: String = "text/plain; charset=utf-8") {
        let bodyData = Data(body.utf8)
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(bodyData)
        conn.send(content: packet, isComplete: true, completion: .contentProcessed { [weak self] error in
            if let error { Log.error("send error: \(error)") }
            self?.finishAndCancel()
        })
    }

    private func finishAndCancel() {
        if didFinish { return }
        didFinish = true
        conn.cancel()
        onFinished?()
    }

    private func finish() {
        finishAndCancel()
    }

    private static func extractFromMultipart(body: Data, contentType: String) -> Data? {
        // Pull boundary= value from content-type, supporting quoted and unquoted forms.
        guard let boundaryRange = contentType.range(of: "boundary=") else { return nil }
        var boundary = String(contentType[boundaryRange.upperBound...])
        if let semi = boundary.firstIndex(of: ";") { boundary = String(boundary[..<semi]) }
        boundary = boundary.trimmingCharacters(in: .whitespaces)
        if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") && boundary.count >= 2 {
            boundary = String(boundary.dropFirst().dropLast())
        }
        guard !boundary.isEmpty else { return nil }
        let delim = Data(("--" + boundary).utf8)
        var cursor = body.startIndex
        // Iterate parts.
        while let nextDelim = body.range(of: delim, in: cursor..<body.endIndex) {
            let afterDelim = nextDelim.upperBound
            // Termination "--boundary--" marker
            if afterDelim + 2 <= body.endIndex, body[afterDelim] == 0x2D, body[afterDelim + 1] == 0x2D {
                return nil
            }
            // Skip CRLF after boundary
            var partStart = afterDelim
            if partStart + 2 <= body.endIndex, body[partStart] == 0x0D, body[partStart + 1] == 0x0A {
                partStart += 2
            }
            guard let headerEnd = body.range(of: Data("\r\n\r\n".utf8), in: partStart..<body.endIndex) else {
                cursor = afterDelim
                continue
            }
            let partHeaders = body[partStart..<headerEnd.lowerBound]
            let partBodyStart = headerEnd.upperBound
            // Find next boundary
            let nextBoundary = body.range(of: delim, in: partBodyStart..<body.endIndex)?.lowerBound ?? body.endIndex
            // Strip trailing CRLF
            var partBodyEnd = nextBoundary
            if partBodyEnd >= 2,
               body[partBodyEnd - 1] == 0x0A,
               body[partBodyEnd - 2] == 0x0D {
                partBodyEnd -= 2
            }
            // If this part declares an image content-type, return it.
            if let headerStr = String(data: partHeaders, encoding: .utf8) {
                let lower = headerStr.lowercased()
                if lower.contains("content-type: image/") || lower.contains("filename=") {
                    return body.subdata(in: partBodyStart..<partBodyEnd)
                }
            }
            cursor = nextBoundary
        }
        return nil
    }
}
