import XCTest
import AppKit
import ImageIO
@testable import PhoneSnap

final class AutomaticWirelessTests: XCTestCase {
    func testBaselineReconnectRetryAndNoReplay() {
        var catalog = AutomaticCaptureCatalog()
        let now = Date()
        XCTAssertTrue(catalog.observe(["old"], now: now))
        XCTAssertTrue(catalog.due(at: now).isEmpty)
        XCTAssertFalse(catalog.observe(["old", "new"], now: now))
        XCTAssertEqual(catalog.due(at: now), ["new"])
        catalog.retry("new", after: now.addingTimeInterval(5))
        // A reconnect repeats the catalog without resetting pending reads or their backoff.
        _ = catalog.observe(["old", "new", "while-offline"], now: now.addingTimeInterval(1))
        XCTAssertEqual(catalog.due(at: now.addingTimeInterval(2)), ["while-offline"])
        XCTAssertEqual(catalog.due(at: now.addingTimeInterval(6)), ["new", "while-offline"])
        catalog.completed("new")
        catalog.completed("while-offline")
        _ = catalog.observe(["old", "new", "while-offline"], now: now.addingTimeInterval(8))
        XCTAssertTrue(catalog.due(at: now.addingTimeInterval(8)).isEmpty)
    }

    func testSameSecondCapturesUseDeviceSequenceRegardlessOfArrivalOrder() {
        let older = URL(fileURLWithPath: "/tmp/saved-first.png")
        let newer = URL(fileURLWithPath: "/tmp/saved-second.png")
        for reverse in [false, true] {
            var recent = RecentScreenshots()
            let entries = [(older, "/DCIM/100APPLE/IMG_0099.HEIC"), (newer, "/DCIM/100APPLE/IMG_0100.HEIC")]
            for (url, sequence) in reverse ? entries.reversed() : entries {
                recent.insert(fileURL: url, date: Date(timeIntervalSince1970: 1234567890), captureOrder: sequence)
            }
            XCTAssertEqual(recent.fileURLs, [newer, older])
        }
    }

    func testUnreadableFirstFileBacksOffAndLaterCaptureRemainsDue() {
        var catalog = AutomaticCaptureCatalog()
        let now = Date()
        _ = catalog.observe([], now: now)
        _ = catalog.observe(["A-unreadable", "B-screenshot"], now: now)
        catalog.backOff("A-unreadable", now: now)
        XCTAssertEqual(catalog.due(at: now.addingTimeInterval(1)), ["B-screenshot"])
        for _ in 0..<50 { catalog.backOff("A-unreadable", now: now) }
        XCTAssertEqual(catalog.pending["A-unreadable"], now.addingTimeInterval(32))
    }

    func testDeletedPendingImageDoesNotBlockLaterCaptures() {
        var catalog = AutomaticCaptureCatalog()
        _ = catalog.observe([])
        _ = catalog.observe(["deleted", "kept"])
        _ = catalog.observe(["kept"])
        XCTAssertEqual(Set(catalog.pending.keys), ["kept"])
    }

    func testCaptureIdentitySurvivesTransportConversionButPreservesNewCaptures() {
        let date = Date(timeIntervalSince1970: 1234567890)
        let wireless = AutomaticCaptureDelivery.key(deviceID: "1234-abcd", name: "IMG_0001.HEIC", capturedAt: date, data: Data([1]))
        let wired = AutomaticCaptureDelivery.key(deviceID: "1234ABCD", name: "IMG_0001.JPG", capturedAt: date, data: Data([2]))
        XCTAssertEqual(wireless, wired)
        XCTAssertNotEqual(wireless, AutomaticCaptureDelivery.key(deviceID: "other", name: "IMG_0001.HEIC", capturedAt: date, data: Data([1])))
        XCTAssertNotEqual(wireless, AutomaticCaptureDelivery.key(deviceID: "1234-abcd", name: "IMG_0002.HEIC", capturedAt: date, data: Data([1])))
        var delivery = AutomaticCaptureDelivery()
        XCTAssertFalse(delivery.contains(wireless))
        delivery.record(wireless)
        XCTAssertTrue(delivery.contains(wired))
    }

    func testCompleteContainersAndTruncatedImageIOInputs() throws {
        let pixels = [UInt8](repeating: 127, count: 100 * 100 * 4)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 400,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        for type in ["public.png", "public.heic"] {
            let output = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let data = output as Data
            XCTAssertTrue(CompleteImage.isComplete(data), type)
            for fraction in [0.99, 0.75, 0.50, 0.25] {
                XCTAssertFalse(CompleteImage.isComplete(Data(data.prefix(Int(Double(data.count) * fraction)))), "\(type) \(fraction)")
            }
            if type == "public.png" {
                var corrupt = data
                corrupt[corrupt.count - 5] ^= 1
                XCTAssertFalse(CompleteImage.isComplete(corrupt))
            }
        }
    }

    func testVerifiedWiFiConnectionWhenExplicitlyRequested() throws {
        guard ProcessInfo.processInfo.environment["PHONESNAP_LIVE_DEVICE_TEST"] == "1" else {
            throw XCTSkip("Opt-in physical device check; not run in CI")
        }
        let devices = try PhoneDeviceConnection.devices()
        XCTAssertFalse(devices.contains { $0.isUSB }, "Unplug the phone to prove network-only transport")
        let phone = try XCTUnwrap(devices.first { !$0.isUSB })
        let endpoint = try XCTUnwrap(phone.directEndpoint)
        let pairing = try PhonePairingRecord(deviceID: phone.id)
        let connection = try DirectPhoneConnection(endpoint: endpoint, pairing: pairing, isCurrent: { true })
        try connection.openPhotos()
        let paths = try connection.imagePaths()
        print("Verified Wi-Fi: pinned identity accepted; \(paths.count) image paths; no downloads or device writes")
    }
}
