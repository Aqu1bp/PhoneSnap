import Foundation
import Darwin

// UsbmuxdProbe — talk directly to /var/run/usbmuxd over its documented Unix
// socket plist protocol and ask for the device list.
//
// Goal: determine whether Apple's system usbmuxd reports a Wi-Fi-paired iPhone
// (ConnectionType = "Network") when the iPhone is on the same Wi-Fi as the
// Mac but NOT plugged in via cable.
//
// Protocol (libusbmuxd / Apple usbmuxd, plist format):
//   Header (16 bytes, little-endian):
//     uint32 length        — total packet length including header
//     uint32 version       — 1 for plist-based protocol
//     uint32 messageType   — 8 (kPlistType)
//     uint32 tag           — request tag for matching responses
//   Body: XML plist
//
// Build: swift build --product UsbmuxdProbe
// Run:   .build/debug/UsbmuxdProbe

let SOCKET_PATH = "/var/run/usbmuxd"
let PLIST_VERSION: UInt32 = 1
let PLIST_MESSAGE_TYPE: UInt32 = 8

print("UsbmuxdProbe — direct usbmuxd Unix-socket query")
print("Talking to \(SOCKET_PATH)")
print(String(repeating: "─", count: 60))

// MARK: socket helpers

func openSocket() throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EINVAL)
    }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    // sun_path is a fixed-size CChar tuple; copy SOCKET_PATH bytes into it.
    let pathBytes = SOCKET_PATH.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
        tuplePtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { cPtr in
            for (i, b) in pathBytes.enumerated() { cPtr[i] = b }
        }
    }
    let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connectResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
            connect(fd, saPtr, addrSize)
        }
    }
    if connectResult != 0 {
        let err = errno
        close(fd)
        throw POSIXError(.init(rawValue: err) ?? .EINVAL)
    }
    return fd
}

func writeAll(_ fd: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
        var sent = 0
        let total = data.count
        while sent < total {
            let n = write(fd, raw.baseAddress!.advanced(by: sent), total - sent)
            if n <= 0 {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            sent += n
        }
    }
}

func readExactly(_ fd: Int32, _ count: Int) throws -> Data {
    var buf = Data(count: count)
    var got = 0
    try buf.withUnsafeMutableBytes { raw in
        while got < count {
            let n = read(fd, raw.baseAddress!.advanced(by: got), count - got)
            if n == 0 { throw POSIXError(.ECONNRESET) }
            if n < 0 { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            got += n
        }
    }
    return buf
}

// MARK: framing

func sendMessage(_ fd: Int32, body: Data, tag: UInt32) throws {
    let total = UInt32(16 + body.count)
    var header = Data()
    func appendLE(_ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { header.append(contentsOf: $0) }
    }
    appendLE(total)
    appendLE(PLIST_VERSION)
    appendLE(PLIST_MESSAGE_TYPE)
    appendLE(tag)
    var packet = header
    packet.append(body)
    try writeAll(fd, packet)
}

func receiveMessage(_ fd: Int32) throws -> (tag: UInt32, body: Data) {
    let head = try readExactly(fd, 16)
    let total = head.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }.littleEndian
    let version = head.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }.littleEndian
    let msgType = head.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }.littleEndian
    let tag = head.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }.littleEndian
    guard version == PLIST_VERSION else {
        throw NSError(domain: "Usbmuxd", code: 1, userInfo: [NSLocalizedDescriptionKey: "unexpected protocol version \(version)"])
    }
    guard msgType == PLIST_MESSAGE_TYPE else {
        throw NSError(domain: "Usbmuxd", code: 2, userInfo: [NSLocalizedDescriptionKey: "unexpected message type \(msgType)"])
    }
    let bodyLen = Int(total) - 16
    let body = bodyLen > 0 ? try readExactly(fd, bodyLen) : Data()
    return (tag, body)
}

// MARK: plist helpers

func plistData(_ dict: [String: Any]) throws -> Data {
    return try PropertyListSerialization.data(
        fromPropertyList: dict,
        format: .xml,
        options: 0
    )
}

func parsePlist(_ data: Data) throws -> Any {
    var fmt = PropertyListSerialization.PropertyListFormat.xml
    return try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
}

// MARK: probe

do {
    let fd = try openSocket()
    defer { close(fd) }

    let request: [String: Any] = [
        "MessageType": "ListDevices",
        "ClientVersionString": "ScreenshotCatch-Probe-0.1",
        "ProgName": "UsbmuxdProbe",
        "kLibUSBMuxVersion": 3
    ]
    let body = try plistData(request)
    try sendMessage(fd, body: body, tag: 1)

    let (_, respBody) = try receiveMessage(fd)
    guard let response = try parsePlist(respBody) as? [String: Any] else {
        print("ERROR: response was not a dictionary")
        exit(2)
    }

    if let deviceList = response["DeviceList"] as? [[String: Any]] {
        if deviceList.isEmpty {
            print("usbmuxd reports: 0 devices")
            print("→ iPhone is NOT visible (either off, off-LAN, or Wi-Fi sync disabled)")
        } else {
            print("usbmuxd reports \(deviceList.count) device(s):")
            for entry in deviceList {
                let props = entry["Properties"] as? [String: Any] ?? [:]
                let connType = props["ConnectionType"] as? String ?? "?"
                let serial = props["SerialNumber"] as? String ?? "?"
                let deviceID = props["DeviceID"] as? Int ?? -1
                let productID = props["ProductID"] as? Int ?? -1
                let extra: String = {
                    var bits: [String] = []
                    if let ip = props["NetworkAddress"] {
                        bits.append("NetworkAddress=\(ip)")
                    }
                    if let escapedAddr = props["EscapedFullServiceName"] as? String {
                        bits.append("svc=\(escapedAddr)")
                    }
                    if let usb = props["LocationID"] {
                        bits.append("LocationID=\(usb)")
                    }
                    return bits.joined(separator: " ")
                }()

                print("  • deviceID=\(deviceID)  ConnectionType=\(connType)  serial=\(serial)  productID=0x\(String(productID, radix: 16))")
                if !extra.isEmpty { print("    \(extra)") }
            }
            let networkCount = deviceList.filter {
                ($0["Properties"] as? [String: Any])?["ConnectionType"] as? String == "Network"
            }.count
            let usbCount = deviceList.filter {
                ($0["Properties"] as? [String: Any])?["ConnectionType"] as? String == "USB"
            }.count
            print(String(repeating: "─", count: 60))
            print("Summary: \(networkCount) wireless, \(usbCount) USB")
            if networkCount > 0 {
                print("✅ Apple's system usbmuxd EXPOSES Wi-Fi-paired iPhones via the public plist protocol.")
                print("   We can build a wireless screenshot-watcher with zero third-party deps.")
            } else {
                print("ℹ️  No 'Network' devices seen. If your iPhone is on the same Wi-Fi and paired,")
                print("   either Wi-Fi sync isn't enabled in Finder, or usbmuxd doesn't surface wireless")
                print("   iPhones via this protocol path on iOS 26 (we'd need to fall back to pymobiledevice3")
                print("   or private MobileDevice.framework for the wireless case).")
            }
        }
    } else {
        print("Unexpected response shape:")
        print(response)
    }
} catch let posix as POSIXError {
    print("POSIX error: \(posix) — make sure usbmuxd is running (it's a system service, always should be).")
    exit(1)
} catch {
    print("ERROR: \(error)")
    exit(1)
}
