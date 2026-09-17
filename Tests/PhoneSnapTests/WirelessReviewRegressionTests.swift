import XCTest
import AppKit
import Darwin
import ImageIO
import CLibIMobileDevice
@testable import PhoneSnap

final class WirelessReviewRegressionTests: XCTestCase {
    @MainActor
    func testDuplicatePhoneNamesRemainDistinctAndSelectionUsesIdentity() throws {
        _ = NSApplication.shared
        let phones = [
            PhoneDevice(id: "first-000001", name: "iPhone", isUSB: true),
            PhoneDevice(id: "second-000001", name: "iPhone", isUSB: true),
            PhoneDevice(id: "third", name: "Work", isUSB: false)
        ]
        let picker = NSPopUpButton()
        PhoneDevicePicker.populate(picker, phones: phones, selectedID: phones[1].id)
        XCTAssertEqual(picker.numberOfItems, 3)
        XCTAssertEqual(Set(picker.itemTitles).count, 3)
        XCTAssertEqual(PhoneDevicePicker.selectedPhone(in: picker, phones: phones)?.id, phones[1].id)
        for index in phones.indices {
            picker.selectItem(at: index)
            XCTAssertEqual(PhoneDevicePicker.selectedPhone(in: picker, phones: phones.reversed())?.id, phones[index].id)
        }
        XCTAssertNil(PhoneDevicePicker.selectedPhone(in: picker, phones: Array(phones.prefix(2))))
    }

    func testNativeTransportCannotOpenAWiFiSession() {
        let phone = PhoneDevice(id: "synthetic-no-device-lookup", name: "iPhone", isUSB: false)
        XCTAssertThrowsError(try PhoneDeviceConnection(phone: phone)) {
            guard case PhoneConnectionError.secureWiFiRequired = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
    }

    func testNativeAddressesUseVerifiedRouteAndPreserveIPv6Scope() throws {
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_scope_id = 7
        let endpoint = try XCTUnwrap(withUnsafePointer(to: &address) { PhoneDeviceConnection.networkEndpoint(address: $0) })
        XCTAssertEqual(endpoint.addresses.first, withUnsafeBytes(of: address) { Data($0) })
        let phone = PhoneDevice(id: "selected", name: "iPhone", isUSB: false, directEndpoint: endpoint)
        let bonjour = DirectPhoneEndpoint(serviceName: "bonjour", addresses: [Data([42])], txt: [:])
        let route = try XCTUnwrap(PhoneWiFiRoute.endpoint(phoneID: phone.id, devices: [phone], bonjour: bonjour))
        XCTAssertEqual(route.addresses, endpoint.addresses + bonjour.addresses)
        XCTAssertNil(PhoneWiFiRoute.endpoint(phoneID: "other", devices: [phone], bonjour: nil))
        XCTAssertEqual(PhoneWiFiRoute.endpoint(phoneID: phone.id, devices: [phone], bonjour: bonjour, bonjourOnly: true)?.addresses, bonjour.addresses)
        let usb = PhoneDevice(id: phone.id, name: "iPhone", isUSB: true)
        XCTAssertNil(PhoneWiFiRoute.endpoint(phoneID: phone.id, devices: [phone, usb], bonjour: bonjour))
        XCTAssertNil(PhoneDeviceConnection.networkEndpoint(address: nil))
    }

    func testNativeTrustAndLockedErrorsProvideSpecificRecovery() throws {
        for code in [LOCKDOWN_E_INVALID_HOST_ID, LOCKDOWN_E_INVALID_CONF, LOCKDOWN_E_USER_DENIED_PAIRING,
                     LOCKDOWN_E_PAIRING_DIALOG_RESPONSE_PENDING, LOCKDOWN_E_PAIRING_FAILED, LOCKDOWN_E_MISSING_HOST_ID] {
            XCTAssertThrowsError(try PhoneDeviceConnection.checkLockdown(code, "Connecting")) {
                guard case PhoneConnectionError.trustRequired = $0 else { return XCTFail("Unexpected error: \($0)") }
            }
        }
        for code in [LOCKDOWN_E_PASSWORD_PROTECTED, LOCKDOWN_E_SERVICE_PROHIBITED, LOCKDOWN_E_ESCROW_LOCKED] {
            XCTAssertThrowsError(try PhoneDeviceConnection.checkLockdown(code, "Connecting")) {
                guard case PhoneConnectionError.locked = $0 else { return XCTFail("Unexpected error: \($0)") }
            }
        }
        XCTAssertThrowsError(try PhoneDeviceConnection.checkLockdown(LOCKDOWN_E_MUX_ERROR, "Connecting")) {
            guard case PhoneConnectionError.failed("Connecting", LOCKDOWN_E_MUX_ERROR.rawValue) = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        try PhoneDeviceConnection.checkLockdown(LOCKDOWN_E_SUCCESS, "Connecting")
    }

    func testUnchangedInvalidFilesStopDownloadingAndChangedFilesRecover() throws {
        let good = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        var bad = good; bad[bad.count - 5] ^= 1
        let phone = PhotoFixture(data: bad)
        var catalog = AutomaticCaptureCatalog()
        let path = "/DCIM/100APPLE/bad.png"
        let now = Date(timeIntervalSince1970: 1000)
        _ = catalog.observe([], now: now)
        _ = catalog.observe([path, "later-capture"], now: now)
        for attempt in 0..<20 {
            let time = now.addingTimeInterval(Double(attempt) * 61)
            do {
                _ = try phone.readImage(path, rejectedRevision: catalog.suspendedRevision(for: path))
                XCTFail("Corrupt image must not be accepted")
            } catch PhoneConnectionError.invalidImage(let revision) {
                catalog.rejectedImage(path, revision: revision, now: time)
            } catch PhoneConnectionError.unchangedRejectedImage {
                catalog.retry(path, after: time.addingTimeInterval(60))
            }
            // Reconnects retain the rejection version and other captures stay due.
            _ = catalog.observe([path, "later-capture"], now: time)
            XCTAssertTrue(catalog.due(at: time).contains("later-capture"))
        }
        XCTAssertEqual(phone.downloads, AutomaticCaptureCatalog.invalidImageAttemptLimit)
        XCTAssertNotNil(catalog.suspendedRevision(for: path))

        // Same size, new modification time: a repaired file must be read again.
        phone.data = good; phone.modifiedAt = "2"
        let image = try phone.readImage(path, rejectedRevision: catalog.suspendedRevision(for: path))
        XCTAssertEqual(image.data, good)
        XCTAssertEqual(phone.downloads, AutomaticCaptureCatalog.invalidImageAttemptLimit + 1)
        catalog.completed(path)
        XCTAssertNil(catalog.suspendedRevision(for: path))
    }

    func testAChangedInvalidRevisionGetsAFreshRetryBudget() {
        var catalog = AutomaticCaptureCatalog()
        _ = catalog.observe([]); _ = catalog.observe(["image"])
        let first = PhoneFileRevision(["st_size": "10", "st_mtime": "1"])
        let second = PhoneFileRevision(["st_size": "10", "st_mtime": "2"])
        for _ in 0..<3 { catalog.rejectedImage("image", revision: first) }
        XCTAssertEqual(catalog.suspendedRevision(for: "image"), first)
        catalog.rejectedImage("image", revision: second)
        XCTAssertNil(catalog.suspendedRevision(for: "image"))
        for _ in 0..<2 { catalog.rejectedImage("image", revision: second) }
        XCTAssertEqual(catalog.suspendedRevision(for: "image"), second)
        _ = catalog.observe([])
        XCTAssertNil(catalog.suspendedRevision(for: "image"))
    }

    func testCorruptHEICPixelsConsumeTheRevisionBudgetAndRepairRecovers() throws {
        let (valid, corrupt) = try makeHEICWithCorruptPixels()
        // ImageIO exposes dimensions and a lazy CGImage for this damaged file.
        // Only normalizing its pixels detects the failure, after container checks.
        XCTAssertTrue(CompleteImage.isComplete(corrupt))
        XCTAssertTrue(CompleteImage.looksLikeScreenshot(corrupt))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ImageStore(folder: directory)
        let phone = PhotoFixture(data: corrupt)
        let path = "/DCIM/100APPLE/corrupt-pixels.HEIC"
        let now = Date(timeIntervalSince1970: 1000)
        var catalog = AutomaticCaptureCatalog()
        _ = catalog.observe([], now: now)
        _ = catalog.observe([path], now: now)

        for attempt in 0..<8 {
            let time = now.addingTimeInterval(Double(attempt) * 61)
            do {
                let image = try phone.readImage(path, rejectedRevision: catalog.suspendedRevision(for: path))
                _ = try image.deliver { _ = try store.save(data: image.data); return true }
                XCTFail("Corrupt HEIC pixels must fail normalization")
            } catch PhoneConnectionError.invalidImage(let revision) {
                catalog.rejectedImage(path, revision: revision, now: time)
            } catch PhoneConnectionError.unchangedRejectedImage {
                catalog.retry(path, after: time.addingTimeInterval(60))
            }
        }
        XCTAssertEqual(phone.downloads, AutomaticCaptureCatalog.invalidImageAttemptLimit)
        XCTAssertNotNil(catalog.suspendedRevision(for: path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        // Repair the payload in place without changing size; modification time
        // permits another download and the real ImageStore now saves the image.
        XCTAssertEqual(valid.count, corrupt.count)
        phone.data = valid; phone.modifiedAt = "2"
        let repaired = try phone.readImage(path, rejectedRevision: catalog.suspendedRevision(for: path))
        XCTAssertTrue(try repaired.deliver { _ = try store.save(data: repaired.data); return true })
        XCTAssertEqual(phone.downloads, AutomaticCaptureCatalog.invalidImageAttemptLimit + 1)
    }

    func testDeliveryDiskFailureStaysRetryableAndRecoversWithoutAFileRevisionChange() throws {
        let (valid, _) = try makeHEICWithCorruptPixels()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("save-location")
        try Data("A file blocks the output directory".utf8).write(to: destination)
        let store = ImageStore(folder: destination)
        let phone = PhotoFixture(data: valid)
        let path = "/DCIM/100APPLE/valid.HEIC"
        let now = Date(timeIntervalSince1970: 1000)
        var catalog = AutomaticCaptureCatalog()
        _ = catalog.observe([], now: now)
        _ = catalog.observe([path], now: now)

        for attempt in 0..<(AutomaticCaptureCatalog.invalidImageAttemptLimit + 1) {
            let time = now.addingTimeInterval(Double(attempt) * 61)
            let image = try phone.readImage(path, rejectedRevision: catalog.suspendedRevision(for: path))
            XCTAssertThrowsError(try image.deliver { _ = try store.save(data: image.data); return true }) { error in
                XCTAssertFalse(error is PhoneConnectionError, "A disk error must not become an image rejection")
                XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            }
            catalog.backOff(path, now: time)
            XCTAssertNil(catalog.suspendedRevision(for: path))
            XCTAssertTrue(catalog.due(at: time.addingTimeInterval(33)).contains(path))
        }

        // Make the destination writable. The unchanged source must remain eligible.
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let image = try phone.readImage(path, rejectedRevision: catalog.suspendedRevision(for: path))
        XCTAssertTrue(try image.deliver { _ = try store.save(data: image.data); return true })
        XCTAssertEqual(phone.downloads, AutomaticCaptureCatalog.invalidImageAttemptLimit + 2)
    }

    private func makeHEICWithCorruptPixels() throws -> (valid: Data, corrupt: Data) {
        let pixels = Data(repeating: 127, count: 1000 * 2000 * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(width: 1000, height: 2000, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.heic" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let valid = output as Data
        var corrupt = valid
        var offset = 0
        var replacedPixels = false
        while offset < corrupt.count {
            var size = corrupt[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            let type = String(data: corrupt[(offset + 4)..<(offset + 8)], encoding: .ascii)
            var header = 8
            if size == 1 {
                size = corrupt[(offset + 8)..<(offset + 16)].reduce(0) { ($0 << 8) | Int($1) }
                header = 16
            }
            guard size >= header, size <= corrupt.count - offset else {
                throw NSError(domain: "HEICFixture", code: 1)
            }
            if type == "mdat" {
                corrupt.replaceSubrange((offset + header)..<(offset + size), with: Data(repeating: 0, count: size - header))
                replacedPixels = true
            }
            offset += size
        }
        XCTAssertTrue(replacedPixels)
        return (valid, corrupt)
    }
}

private final class PhotoFixture: PhonePhotoConnection {
    var data: Data
    var modifiedAt = "1"
    var downloads = 0
    init(data: Data) { self.data = data }
    func openPhotos() throws {}
    func list(_ path: String) throws -> [String] { [] }
    func info(_ path: String) throws -> [String: String] {
        ["st_ifmt": "S_IFREG", "st_size": String(data.count), "st_mtime": modifiedAt]
    }
    func readFile(_ path: String, size: Int, deadline: TimeInterval, isCurrent: () -> Bool) throws -> Data {
        downloads += 1
        return data
    }
}
