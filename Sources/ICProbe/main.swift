import Foundation
import ImageCaptureCore

// Standalone probe: enumerate ICDeviceBrowser and report what's found.
// Run with an iPhone plugged in via cable to confirm ImageCaptureCore can see
// the device and stream newly added camera-roll items.
//
// Build:  swift build --target ICProbe
// Run:    .build/debug/ICProbe [--watch] [--seconds N]
//   --watch    : keep running and stream new ICCameraItem events
//   --seconds  : how long to watch (default 30)

let args = Array(CommandLine.arguments.dropFirst())
let watch = args.contains("--watch")
let seconds: TimeInterval = {
    if let idx = args.firstIndex(of: "--seconds"),
       idx + 1 < args.count,
       let n = TimeInterval(args[idx + 1]) {
        return n
    }
    return 30
}()

print("ICProbe — ICDeviceBrowser enumeration test")
print("Args: watch=\(watch) seconds=\(Int(seconds))")
print(String(repeating: "─", count: 60))

final class Probe: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    let browser = ICDeviceBrowser()
    var cameras: [ICCameraDevice] = []

    func start() {
        browser.delegate = self
        // Look in every location. The .raw mask lets us OR together both
        // device-type and location bits.
        let mask: UInt =
            UInt(ICDeviceTypeMask.camera.rawValue) |
            UInt(ICDeviceLocationTypeMask.local.rawValue) |
            UInt(ICDeviceLocationTypeMask.shared.rawValue) |
            UInt(ICDeviceLocationTypeMask.bonjour.rawValue) |
            UInt(ICDeviceLocationTypeMask.bluetooth.rawValue)
        if let m = ICDeviceTypeMask(rawValue: mask) {
            browser.browsedDeviceTypeMask = m
        }
        print("[browse] starting ICDeviceBrowser…")
        browser.start()
    }

    func stop() { browser.stop() }

    // MARK: ICDeviceBrowserDelegate

    func deviceBrowser(_ browser: ICDeviceBrowser,
                       didAdd device: ICDevice,
                       moreComing: Bool) {
        print("[+] device added")
        print("    kind:        \(type(of: device))")
        print("    name:        \(device.name ?? "<nil>")")
        print("    transport:   \(device.transportType ?? "<nil>")")
        print("    location:    \(device.locationDescription ?? "<nil>")")
        print("    type:        \(device.type)")
        print("    serial:      \(device.serialNumberString ?? "<nil>")")
        print("    productKind: \(device.productKind ?? "<nil>")")
        print("    usbVendorID:0x\(String(device.usbVendorID, radix: 16))  productID:0x\(String(device.usbProductID, radix: 16))")
        if let cam = device as? ICCameraDevice {
            cameras.append(cam)
            cam.delegate = self
            print("    → requesting open session…")
            cam.requestOpenSession()
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser,
                       didRemove device: ICDevice,
                       moreGoing: Bool) {
        print("[-] device removed: \(device.name ?? "<nil>")")
    }

    // MARK: ICDeviceDelegate

    func didRemove(_ device: ICDevice) {
        print("[device] removed: \(device.name ?? "?")")
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            print("[session] open FAILED for \(device.name ?? "?"): \(error)")
            return
        }
        print("[session] opened on \(device.name ?? "?")")
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        print("[session] closed on \(device.name ?? "?") err=\(String(describing: error))")
    }

    // MARK: ICCameraDeviceDelegate

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        print("[ready] catalog complete on \(device.name ?? "?")")
        let files = device.mediaFiles ?? []
        print("[catalog] \(files.count) media file(s) visible")
        // Show the 5 most recent so we can confirm screenshots are reachable.
        let sorted = files.sorted { a, b in
            (a.creationDate ?? .distantPast) > (b.creationDate ?? .distantPast)
        }
        for f in sorted.prefix(5) {
            let name = f.name ?? "?"
            let date = f.creationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
            print("        \(date)  \(name)")
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        // Real-time delivery: this is what would fire on a new screenshot.
        for item in items {
            let name = item.name ?? "?"
            let date = item.creationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
            print("[NEW ITEM] \(date)  \(name)")
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice,
                      didReceiveThumbnail thumbnail: CGImage?,
                      for item: ICCameraItem,
                      error: Error?) {}

    func cameraDevice(_ camera: ICCameraDevice,
                      didReceiveMetadata metadata: [AnyHashable: Any]?,
                      for item: ICCameraItem,
                      error: Error?) {}

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        print("[access] restriction ENABLED on \(device.name ?? "?") — unlock the iPhone")
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        print("[access] restriction REMOVED on \(device.name ?? "?") — content available")
    }
}

let probe = Probe()
probe.start()

let deadline = Date().addingTimeInterval(watch ? seconds : 12)
let runLoop = RunLoop.current
while Date() < deadline {
    runLoop.run(mode: .default, before: Date().addingTimeInterval(0.5))
}

print(String(repeating: "─", count: 60))
print("ICProbe: \(probe.cameras.count) camera device(s) found")
for cam in probe.cameras {
    let xport = cam.transportType ?? "?"
    let loc = cam.locationDescription ?? "?"
    print("  - \(cam.name ?? "?")  transport=\(xport)  location=\(loc)")
}
probe.stop()
