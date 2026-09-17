import Foundation
import CLibIMobileDevice
import CUsbmuxd

struct PhoneDevice: Equatable {
    let id: String
    let name: String
    let isUSB: Bool
}

enum PhoneConnectionError: LocalizedError {
    case unavailable, trustRequired, failed(String, Int32), incomplete, unsupported, cancelled, transportLost(Int32)
    var errorDescription: String? {
        switch self {
        case .transportLost: return "Wi-Fi connection interrupted. Reconnecting…"
        case .unsupported: return "This image is outside the supported screenshot size."
        case .cancelled: return "Capture stopped."
        case .unavailable: return "Connect your iPhone by cable, unlock it, and trust this Mac."
        case .trustRequired: return "Unlock your iPhone and approve Trust in Finder and on the iPhone, then try again."
        case .failed(let operation, let code): return "\(operation) failed (\(code)). Keep the iPhone unlocked and on the same Wi-Fi as this Mac."
        case .incomplete: return "The image is still being saved. PhoneSnap will retry."
        }
    }
}

/// Confined to the watcher's serial queue. Never creates or replaces pairing records.
final class PhoneDeviceConnection {
    private var device: idevice_t?
    private var lockdown: lockdownd_client_t?
    private var afc: afc_client_t?
    let phone: PhoneDevice

    static func devices(resolveNames: Bool = false) throws -> [PhoneDevice] {
        var list: UnsafeMutablePointer<idevice_info_t?>?
        var count: Int32 = 0
        let result = idevice_get_device_list_extended(&list, &count)
        guard result == IDEVICE_E_SUCCESS else { throw PhoneConnectionError.unavailable }
        defer { idevice_device_list_extended_free(list) }
        return (0..<Int(count)).compactMap { index in
            guard let info = list?[index], let udid = info.pointee.udid else { return nil }
            let id = String(cString: udid)
            let usb = info.pointee.conn_type == CONNECTION_USBMUXD
            var name = "iPhone"
            if resolveNames {
                var raw: idevice_t?
                var client: lockdownd_client_t?
                if idevice_new_with_options(&raw, id, usb ? IDEVICE_LOOKUP_USBMUX : IDEVICE_LOOKUP_NETWORK) == IDEVICE_E_SUCCESS {
                    if lockdownd_client_new(raw, &client, "PhoneSnap") == LOCKDOWN_E_SUCCESS {
                        var value: UnsafeMutablePointer<CChar>?
                        if lockdownd_get_device_name(client, &value) == LOCKDOWN_E_SUCCESS, let value {
                            name = String(cString: value)
                            free(value)
                        }
                        lockdownd_client_free(client)
                    }
                    idevice_free(raw)
                }
            }
            return PhoneDevice(id: id, name: name, isUSB: usb)
        }
    }

    init(phone: PhoneDevice) throws {
        self.phone = phone
        // Exact transport only. Network capture must never fall back to USB.
        let result = idevice_new_with_options(&device, phone.id, phone.isUSB ? IDEVICE_LOOKUP_USBMUX : IDEVICE_LOOKUP_NETWORK)
        guard result == IDEVICE_E_SUCCESS else { throw PhoneConnectionError.unavailable }
        do {
            var recordData: UnsafeMutablePointer<CChar>?
            var recordSize: UInt32 = 0
            guard usbmuxd_read_pair_record(phone.id, &recordData, &recordSize) == 0, let recordData else {
                throw PhoneConnectionError.trustRequired
            }
            defer { free(recordData) }
            let data = Data(bytes: recordData, count: Int(recordSize))
            guard let record = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let hostID = record["HostID"] as? String else { throw PhoneConnectionError.trustRequired }
            try check(lockdownd_client_new(device, &lockdown, "PhoneSnap"), "Connecting")
            // The convenience new_with_handshake API may Pair. StartSession only uses existing trust.
            try check(lockdownd_start_session(lockdown, hostID, nil, nil), "Opening the trusted connection")
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    private func close() {
        if let afc { afc_client_free(afc); self.afc = nil }
        if let lockdown { lockdownd_client_free(lockdown); self.lockdown = nil }
        if let device { idevice_free(device); self.device = nil }
    }

    func enableWiFi() throws {
        guard phone.isUSB else { return }
        guard let lockdown else { throw PhoneConnectionError.unavailable }
        // SetValue takes ownership of this node and frees it with its request.
        // GetValue below returns a separate node owned by the caller.
        let value = plist_new_bool(1)
        try check(lockdownd_set_value(lockdown, "com.apple.mobile.wireless_lockdown", "EnableWifiConnections", value), "Enabling wireless access")
        var readback: plist_t?
        try check(lockdownd_get_value(lockdown, "com.apple.mobile.wireless_lockdown", "EnableWifiConnections", &readback), "Checking wireless access")
        defer { plist_free(readback) }
        var enabled: UInt8 = 0
        plist_get_bool_val(readback, &enabled)
        guard enabled == 1 else { throw PhoneConnectionError.failed("Enabling wireless access", -1) }
    }

    func openPhotos() throws {
        var service: lockdownd_service_descriptor_t?
        try check(lockdownd_start_service(lockdown, "com.apple.afc", &service), "Opening photo access")
        defer { lockdownd_service_descriptor_free(service) }
        try checkAFC(afc_client_new(device, service, &afc), "Opening photo access")
        // AFC owns its connection; release the short-lived lockdown connection.
        lockdownd_client_free(lockdown)
        lockdown = nil
    }

    func list(_ path: String) throws -> [String] {
        var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        try checkAFC(afc_read_directory(afc, path, &entries), "Reading the photo folder")
        defer { afc_dictionary_free(entries) }
        return strings(entries).filter { $0 != "." && $0 != ".." && !$0.contains("/") }
    }

    func imagePaths(isCurrent: () -> Bool = { true }) throws -> Set<String> {
        var paths = Set<String>()
        for directory in try list("/DCIM") {
            guard isCurrent() else { throw PhoneConnectionError.cancelled }
            let path = "/DCIM/" + directory
            guard try info(path)["st_ifmt"] == "S_IFDIR" else { continue }
            for file in try list(path) where ["png", "heic", "heif", "jpg", "jpeg"].contains((file as NSString).pathExtension.lowercased()) {
                paths.insert(path + "/" + file)
            }
        }
        return paths
    }

    func info(_ path: String) throws -> [String: String] {
        var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        try checkAFC(afc_get_file_info(afc, path, &entries), "Reading photo details")
        defer { afc_dictionary_free(entries) }
        let values = strings(entries)
        var result: [String: String] = [:]
        for i in stride(from: 0, to: values.count - 1, by: 2) { result[values[i]] = values[i + 1] }
        return result
    }

    func readImage(_ path: String, isCurrent: () -> Bool = { true }) throws -> (Data, Date?) {
        let deadline = Date().addingTimeInterval(30)
        let before = try info(path)
        guard before["st_ifmt"] == "S_IFREG", let size = before["st_size"].flatMap(Int.init), size > 0 else { throw PhoneConnectionError.incomplete }
        guard size <= 32 * 1024 * 1024 else { throw PhoneConnectionError.unsupported }
        var handle: UInt64 = 0
        try checkAFC(afc_file_open(afc, path, AFC_FOPEN_RDONLY, &handle), "Reading the screenshot")
        defer { afc_file_close(afc, handle) }
        var data = Data(count: size)
        var offset = 0
        try data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            while offset < size {
                guard isCurrent() else { throw PhoneConnectionError.cancelled }
                guard Date() < deadline else { throw PhoneConnectionError.incomplete }
                var received: UInt32 = 0
                let length = UInt32(min(256 * 1024, size - offset))
                try checkAFC(afc_file_read(afc, handle, buffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: CChar.self), length, &received), "Downloading the screenshot")
                guard received > 0, received <= length else { throw PhoneConnectionError.incomplete }
                offset += Int(received)
            }
        }
        let after = try info(path)
        guard before["st_size"] == after["st_size"], before["st_mtime"] == after["st_mtime"],
              CompleteImage.isComplete(data) else { throw PhoneConnectionError.incomplete }
        let date = after["st_birthtime"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1_000_000_000) }
        return (data, date)
    }

    private func strings(_ pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> [String] {
        var values: [String] = []
        var index = 0
        while let value = pointer?[index] { values.append(String(cString: value)); index += 1 }
        return values
    }

    private func check(_ result: lockdownd_error_t, _ operation: String) throws {
        guard result == LOCKDOWN_E_SUCCESS else { throw PhoneConnectionError.failed(operation, result.rawValue) }
    }
    private func checkAFC(_ result: afc_error_t, _ operation: String) throws {
        if [AFC_E_SERVICE_NOT_CONNECTED, AFC_E_MUX_ERROR, AFC_E_OP_TIMEOUT, AFC_E_NOT_ENOUGH_DATA].contains(result) {
            throw PhoneConnectionError.transportLost(result.rawValue)
        }
        guard result == AFC_E_SUCCESS else { throw PhoneConnectionError.failed(operation, result.rawValue) }
    }
}
