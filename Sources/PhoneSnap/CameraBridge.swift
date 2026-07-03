import Foundation
import ImageCaptureCore

/// Watches for connected iPhones via Apple's `ImageCaptureCore` framework and
/// emits image bytes for each *new* item that lands in the camera roll after
/// startup. This is the cable-tethered path that gives us zero-tap screenshot
/// detection without iCloud or any iPhone-side app — pair via USB and the
/// iPhone publishes its camera roll to the Mac.
///
/// Why this works:
/// - `ICDeviceBrowser` enumerates camera-class devices (iPhones plugged in via
///   USB count as cameras to macOS).
/// - When a session opens, the device delivers its initial catalog via repeated
///   `cameraDevice(_:didAdd:)` callbacks. We snapshot those IDs as "already
///   seen" so we don't pop thumbnails for old photos.
/// - From then on, any further `didAdd` call is a genuinely new item — i.e.
///   a fresh screenshot or photo the user just took. We filter for likely
///   screenshots (PNG, or HEIC where the file name pattern + screen-shape
///   resolution match), download it, and hand it to the thumbnail pipeline.
final class CameraBridge: NSObject, ICCameraDeviceDownloadDelegate {
    typealias NewImageHandler = (Data, String) -> Void

    /// Called on device attach/detach so the UI can show live connection state.
    var onDevicesChanged: (([String]) -> Void)?

    /// Names of currently attached, session-opened iPhone/iPad devices.
    var connectedDeviceNames: [String] {
        devices.map { $0.name ?? "iPhone" }
    }

    private let browser = ICDeviceBrowser()
    private let onNewImage: NewImageHandler
    private var devices: [ICCameraDevice] = []
    /// Stable keys (name + creation date) of items we've already considered.
    /// ImageCaptureCore re-announces the catalog with *new* item objects every
    /// time the session reopens (e.g. after the iPhone locks and unlocks), so
    /// object identity is not a usable dedup key — the same screenshot would
    /// be re-delivered on every reconnect.
    private var processedItemKeys: Set<String> = []
    /// Only items whose `creationDate` is **after** this threshold qualify as
    /// "new screenshots". Set when CameraBridge starts. This decouples our
    /// "new vs old" test from ImageCaptureCore's delivery order — on modern
    /// iOS, `deviceDidBecomeReady` fires before the catalog has actually been
    /// delivered, so a snapshot-the-catalog-then-watch-for-new approach gets
    /// flooded by the catalog itself once it starts streaming in.
    private var newItemThreshold = Date.distantFuture
    private let downloadQueue = DispatchQueue(label: "phonesnap.camerabridge.download", qos: .userInitiated)

    init(onNewImage: @escaping NewImageHandler) {
        self.onNewImage = onNewImage
        super.init()
    }

    func start() {
        // Anything with a creationDate strictly newer than this counts as new.
        // 2 second grace window means we won't lose a screenshot the user
        // happens to take in the exact second the app launches.
        newItemThreshold = Date().addingTimeInterval(-2)
        browser.delegate = self
        let mask: UInt =
            UInt(ICDeviceTypeMask.camera.rawValue) |
            UInt(ICDeviceLocationTypeMask.local.rawValue)
        if let m = ICDeviceTypeMask(rawValue: mask) {
            browser.browsedDeviceTypeMask = m
        }
        browser.start()
        Log.info("CameraBridge: ICDeviceBrowser started (USB cable path) — newItemThreshold=\(newItemThreshold)")
    }

    func stop() {
        browser.stop()
        for d in devices { d.requestCloseSession() }
        devices.removeAll()
        processedItemKeys.removeAll()
        notifyDevicesChanged()
    }

    // MARK: download
    private func download(_ file: ICCameraFile) {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "PhoneSnap-\(UUID().uuidString)-\(file.name ?? "image")"
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: tmpDir,
            .saveAsFilename: filename,
            .overwrite: true
        ]
        guard let cam = file.device else {
            Log.error("CameraBridge: file has no parent camera device")
            return
        }
        cam.requestDownloadFile(
            file,
            options: options,
            downloadDelegate: self,
            didDownloadSelector: #selector(didDownloadFile(_:error:options:contextInfo:)),
            contextInfo: nil
        )
        Log.info("CameraBridge: downloading \(file.name ?? "?") → \(tmpDir.appendingPathComponent(filename).path)")
    }

    @objc func didDownloadFile(_ file: ICCameraFile,
                               error: Error?,
                               options: [String: Any],
                               contextInfo: UnsafeMutableRawPointer?) {
        if let error {
            Log.error("CameraBridge: download failed for \(file.name ?? "?"): \(error)")
            return
        }
        let dir = (options[ICDownloadOption.downloadsDirectoryURL.rawValue] as? URL)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let name = options[ICDownloadOption.savedFilename.rawValue] as? String else {
            Log.error("CameraBridge: missing savedFilename in download completion")
            return
        }
        let url = dir.appendingPathComponent(name)
        downloadQueue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: url)
                Log.info("CameraBridge: downloaded \(data.count) bytes for \(file.name ?? "?")")
                try? FileManager.default.removeItem(at: url)
                self.onNewImage(data, file.name ?? "screenshot.png")
            } catch {
                Log.error("CameraBridge: read download failed: \(error)")
            }
        }
    }

    // MARK: screenshot heuristic
    /// An iPhone screenshot is a PNG (or HEIC on iOS 26 with certain settings),
    /// whose width:height aspect matches a phone screen (much taller than wide,
    /// or much wider than tall in landscape), AND whose pixel dimensions are
    /// small enough to be a screen capture (vs a camera photo which is usually
    /// ≥ 4000px on the long edge).
    private func looksLikeScreenshot(_ file: ICCameraFile) -> Bool {
        let w = file.width
        let h = file.height
        // Camera photos on modern iPhones: ~4032×3024 and up. Screenshots:
        // 1206×2622 (15 Pro), 1290×2796 (15 Pro Max), 1320×2868 (16 Pro Max),
        // etc. The long edge of any current iPhone screenshot is < 3500.
        let longEdge = max(w, h)
        if longEdge >= 3500 { return false }
        if longEdge < 800 { return false } // too small to be a phone screenshot
        // Aspect must be portrait-ish (or landscape if rotated). Tolerate
        // landscape too — some games / videos screenshot in landscape.
        let aspect = Double(max(w, h)) / Double(min(w, h))
        if aspect < 1.5 { return false }
        return true
    }
}

extension CameraBridge: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser,
                       didAdd device: ICDevice,
                       moreComing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        guard cam.productKind?.contains("iPhone") == true ||
              cam.productKind?.contains("iPad") == true else {
            Log.info("CameraBridge: ignoring non-iPhone device \(cam.productKind ?? "?")")
            return
        }
        cam.delegate = self
        devices.append(cam)
        Log.info("CameraBridge: \(cam.name ?? "?") attached (\(cam.transportType ?? "?")); opening session…")
        cam.requestOpenSession()
        notifyDevicesChanged()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser,
                       didRemove device: ICDevice,
                       moreGoing: Bool) {
        Log.info("CameraBridge: \(device.name ?? "?") detached")
        if let cam = device as? ICCameraDevice,
           let idx = devices.firstIndex(where: { $0 === cam }) {
            devices.remove(at: idx)
        }
        notifyDevicesChanged()
    }

    private func notifyDevicesChanged() {
        let names = connectedDeviceNames
        DispatchQueue.main.async { [weak self] in
            self?.onDevicesChanged?(names)
        }
    }
}

extension CameraBridge: ICCameraDeviceDelegate {
    func didRemove(_ device: ICDevice) {}

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            Log.error("CameraBridge: open session failed on \(device.name ?? "?"): \(error)")
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        // nothing per-device to reset here; processedItemIDs is global
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        // On modern iOS this fires BEFORE the catalog has actually been
        // delivered (mediaFiles is typically empty here). So we don't snapshot
        // — instead we filter every incoming item by creationDate against the
        // threshold we set at start().
        Log.info("CameraBridge: session ready on \(device.name ?? "?") — watching for items created after \(newItemThreshold)")
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        for item in items {
            guard let file = item as? ICCameraFile else { continue }

            // Filter by creation date: anything from before the app started is
            // part of the existing camera roll, not a new screenshot.
            guard let created = file.creationDate else {
                continue
            }
            guard created > newItemThreshold else {
                continue
            }

            let key = Self.itemKey(file)
            if processedItemKeys.contains(key) { continue }
            processedItemKeys.insert(key)

            guard looksLikeScreenshot(file) else {
                Log.info("CameraBridge: skipping non-screenshot \(file.name ?? "?") \(file.width)x\(file.height)")
                continue
            }
            Log.info("CameraBridge: NEW screenshot \(file.name ?? "?") \(file.width)x\(file.height) created=\(created)")
            download(file)
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        for item in items {
            if let file = item as? ICCameraFile {
                processedItemKeys.remove(Self.itemKey(file))
            }
        }
    }

    private static func itemKey(_ file: ICCameraFile) -> String {
        let created = file.creationDate?.timeIntervalSince1970 ?? 0
        return "\(file.name ?? "?")|\(created)"
    }

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    func cameraDevice(_ camera: ICCameraDevice,
                      didReceiveThumbnail thumbnail: CGImage?,
                      for item: ICCameraItem,
                      error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice,
                      didReceiveMetadata metadata: [AnyHashable: Any]?,
                      for item: ICCameraItem,
                      error: Error?) {}
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Log.info("CameraBridge: access restricted on \(device.name ?? "?") — unlock the iPhone")
    }
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        Log.info("CameraBridge: access restored on \(device.name ?? "?")")
    }
}
