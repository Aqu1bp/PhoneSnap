import XCTest
import Foundation
import Darwin
@testable import PhoneSnap

final class DirectWirelessTests: XCTestCase {
    private func address() -> Data {
        var value = sockaddr_in()
        value.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); value.sin_family = sa_family_t(AF_INET)
        value.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private func server(_ mode: String, body: (UInt16, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try XCTUnwrap(Bundle.module.url(forResource: "direct_phone_server", withExtension: "py"))
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, mode, directory.path]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        var line = Data()
        while line.count < 16 {
            let byte = output.fileHandleForReading.readData(ofLength: 1)
            if byte.isEmpty || byte == Data([10]) { break }; line.append(byte)
        }
        let port = try XCTUnwrap(UInt16(String(decoding: line, as: UTF8.self)))
        try body(port, directory)
    }

    private func pairing(_ directory: URL, wrongPin: Bool = false) throws -> PhonePairingRecord {
        try PhonePairingRecord(deviceID: "test-device", values: [
            "HostID": "test-host", "SystemBUID": "test-system",
            "HostCertificate": Data(contentsOf: directory.appendingPathComponent("host.pem")),
            "HostPrivateKey": Data(contentsOf: directory.appendingPathComponent("host.key")),
            "DeviceCertificate": Data(contentsOf: directory.appendingPathComponent(wrongPin ? "host.pem" : "device.pem"))
        ])
    }

    func testPlainAndPinnedTLSFragmentedReads() throws {
        for mode in ["plain", "tls"] {
            try server(mode) { port, directory in
                let socket = try DirectPhoneSocket(address: address(), port: port, isCurrent: { true })
                if mode == "tls" { try socket.startTLS(pairing(directory)) }
                try socket.write(Data("hello!".utf8))
                XCTAssertEqual(try socket.read(16), Data("fragmented reply".utf8))
            }
        }
    }

    func testWrongDeviceCertificateRejected() throws {
        try server("tls") { port, directory in
            let socket = try DirectPhoneSocket(address: address(), port: port, isCurrent: { true })
            XCTAssertThrowsError(try socket.startTLS(pairing(directory, wrongPin: true)))
        }
    }

    func testWiFiAuthenticatesBothSessionAndPhotoService() throws {
        try server("lockdown") { port, directory in
            let endpoint = DirectPhoneEndpoint(serviceName: "local fixture", addresses: [address()], txt: [:])
            let connection = try DirectPhoneConnection(endpoint: endpoint, pairing: pairing(directory), lockdownPort: port, isCurrent: { true })
            try connection.openPhotos()
            XCTAssertTrue(connection.photosUseTLS)
            XCTAssertEqual(try connection.list("/DCIM"), ["100APPLE"])
        }
    }

    func testWiFiRejectsWrongSessionCertificateOrDeviceIdentity() throws {
        for mode in ["lockdown", "lockdown-wrong-id"] {
            try server(mode) { port, directory in
                let endpoint = DirectPhoneEndpoint(serviceName: "local fixture", addresses: [address()], txt: [:])
                XCTAssertThrowsError(try DirectPhoneConnection(endpoint: endpoint,
                    pairing: pairing(directory, wrongPin: mode == "lockdown"), lockdownPort: port, isCurrent: { true })) { error in
                    if mode == "lockdown-wrong-id" {
                        guard case PhoneConnectionError.trustRequired = error else { return XCTFail("Unexpected error: \(error)") }
                    } else {
                        guard case PhoneConnectionError.failed("Verifying the trusted iPhone", _) = error else { return XCTFail("Unexpected error: \(error)") }
                    }
                }
            }
        }
    }

    func testWiFiRejectsPlaintextSessionAndUnauthenticatedPhotoService() throws {
        for mode in ["lockdown-plaintext-session", "lockdown-plaintext-afc", "lockdown-wrong-afc-cert"] {
            try server(mode) { port, directory in
                let endpoint = DirectPhoneEndpoint(serviceName: "local fixture", addresses: [address()], txt: [:])
                if mode == "lockdown-plaintext-session" {
                    XCTAssertThrowsError(try DirectPhoneConnection(endpoint: endpoint, pairing: pairing(directory), lockdownPort: port, isCurrent: { true })) {
                        guard case PhoneConnectionError.secureWiFiRequired = $0 else { return XCTFail("Unexpected error: \($0)") }
                    }
                } else {
                    let connection = try DirectPhoneConnection(endpoint: endpoint, pairing: pairing(directory), lockdownPort: port, isCurrent: { true })
                    XCTAssertThrowsError(try connection.openPhotos()) { error in
                        if mode == "lockdown-plaintext-afc" {
                            guard case PhoneConnectionError.secureWiFiRequired = error else { return XCTFail("Unexpected error: \(error)") }
                        } else {
                            guard case PhoneConnectionError.failed("Verifying the trusted iPhone", _) = error else { return XCTFail("Unexpected error: \(error)") }
                        }
                    }
                    XCTAssertFalse(connection.photosUseTLS)
                    XCTAssertThrowsError(try connection.list("/DCIM"))
                }
            }
        }
    }

    func testTruncatedReadRejected() throws {
        try server("truncated") { port, _ in
            let socket = try DirectPhoneSocket(address: address(), port: port, isCurrent: { true })
            XCTAssertThrowsError(try socket.read(16))
        }
    }

    func testPlistUsesOneDeadlineAcrossHeaderAndBody() throws {
        try server("slow-plist") { port, _ in
            let socket = try DirectPhoneSocket(address: address(), port: port, isCurrent: { true })
            let began = ProcessInfo.processInfo.systemUptime
            XCTAssertThrowsError(try socket.plist(["Request": "GetValue"], deadline: began + 0.25))
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 1)
            XCTAssertFalse(socket.isUsable)
        }
    }

    func testStalledReadCancelsPromptly() throws {
        final class Flag: @unchecked Sendable {
            let lock = NSLock(); var current = true
            func read() -> Bool { lock.lock(); defer { lock.unlock() }; return current }
            func stop() { lock.lock(); current = false; lock.unlock() }
        }
        try server("stall") { port, _ in
            let flag = Flag()
            let socket = try DirectPhoneSocket(address: address(), port: port, isCurrent: { flag.read() })
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { flag.stop() }
            let began = ProcessInfo.processInfo.systemUptime
            XCTAssertThrowsError(try socket.read(1))
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 1.5)
        }
    }

    func testAFCRejectsMalformedFramesBeforeAllocation() throws {
        let correct = AFCFrame.request(sequence: 7, operation: 2, payload: Data([1, 2]))
        XCTAssertEqual(try AFCFrame.responseHeader(Data(correct.prefix(40)), sequence: 7).length, 2)
        XCTAssertThrowsError(try AFCFrame.responseHeader(Data(correct.prefix(40)), sequence: 8))
        for offset in [0, 8, 16] {
            var corrupt = Data(correct.prefix(40)); corrupt.replaceSubrange(offset..<offset + 8, with: Data(repeating: 255, count: 8))
            XCTAssertThrowsError(try AFCFrame.responseHeader(corrupt, sequence: 7))
        }
        XCTAssertThrowsError(try AFCFrame.strings(Data("unterminated".utf8)))
    }

    func testAdvertisementIdentityAndNoLegacyDowngrade() {
        // Independent Python hashlib/hmac HKDF-SHA512 + HMAC-SHA256 fixture.
        let txt = ["identifier": Data("sample-identifier".utf8), "authTag": Data("bcdOgOt9E2I=".utf8)]
        XCTAssertTrue(PhoneAdvertisement.matches(name: "random-mac@phone", txt: txt, hostID: "sample-host", wifiMAC: nil))
        XCTAssertFalse(PhoneAdvertisement.matches(name: "aa:bb@phone", txt: txt, hostID: "wrong-host", wifiMAC: "aa:bb"))
        XCTAssertFalse(PhoneAdvertisement.matches(name: "aa:bb@phone", txt: ["identifier": Data([1])], hostID: "sample-host", wifiMAC: "aa:bb"))
        XCTAssertTrue(PhoneAdvertisement.matches(name: "AA:BB@phone", txt: [:], hostID: "sample-host", wifiMAC: "aa:bb"))
    }
}
