import XCTest
import AppKit
@testable import PhoneSnap

final class ImageStoreTests: XCTestCase {
    func testNormalizesAndSavesPNG() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ImageStore(folder: folder)

        let url = try store.save(data: Self.onePixelPNG)

        let saved = try Data(contentsOf: url)
        XCTAssertTrue(saved.starts(with: Self.pngSignature))
        XCTAssertEqual(url.deletingLastPathComponent(), folder)
    }

    func testRejectsNonImageData() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ImageStore(folder: folder)

        XCTAssertThrowsError(try store.save(data: Data("not an image".utf8))) { error in
            guard case ImageStore.SaveError.noImage = error else {
                return XCTFail("Expected noImage, got \(error)")
            }
        }
    }

    func testRejectsImageDimensionsAboveSafetyLimitBeforeDecode() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ImageStore(folder: folder)

        XCTAssertThrowsError(try store.save(data: Self.oversizedPNGHeader)) { error in
            guard case ImageStore.SaveError.imageTooLarge = error else {
                return XCTFail("Expected imageTooLarge, got \(error)")
            }
        }
    }

    func testRejectsVectorInputWithoutRasterizingIt() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ImageStore(folder: folder)

        XCTAssertThrowsError(try store.save(data: Self.oversizedPDF)) { error in
            guard case ImageStore.SaveError.noImage = error else {
                return XCTFail("Expected noImage, got \(error)")
            }
        }
    }

    func testConcurrentSavesNeverOverwriteOneAnother() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ImageStore(folder: folder)
        let savedURLs = LockedURLs()

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            if let url = try? store.save(data: Self.onePixelPNG) {
                savedURLs.append(url)
            }
        }

        let urls = savedURLs.values
        XCTAssertEqual(urls.count, 8)
        XCTAssertEqual(Set(urls).count, 8)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count,
            8
        )
    }

    func testIndependentStoresRacingAtSameTimeNeverOverwriteOrLoseData() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let saveCount = 16
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        // Each instance has its own in-memory lock, matching separate-process
        // filename allocation as closely as possible without subprocess timing.
        let stores = (0..<saveCount).map { _ in
            ImageStore(folder: folder, now: { fixedDate })
        }
        let inputs = try (1...saveCount).map(Self.png(width:))
        let savedURLs = LockedURLs()
        let failures = LockedStrings()
        let completed = DispatchGroup()
        let queue = DispatchQueue(
            label: "ImageStoreTests.independent-stores",
            attributes: .concurrent
        )

        queue.suspend()
        for index in 0..<saveCount {
            completed.enter()
            queue.async {
                defer { completed.leave() }
                do {
                    savedURLs.append(try stores[index].save(data: inputs[index]))
                } catch {
                    failures.append(String(describing: error))
                }
            }
        }
        queue.resume()

        XCTAssertEqual(completed.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(failures.values, [])

        let urls = savedURLs.values
        XCTAssertEqual(urls.count, saveCount)
        XCTAssertEqual(Set(urls).count, saveCount)

        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents.count, saveCount, "Staging files must always be cleaned up")

        let savedWidths = try Set(urls.map { url -> Int in
            guard let width = NSImage(contentsOf: url)?.representations.first?.pixelsWide else {
                throw TestError.couldNotDecode(url)
            }
            return width
        })
        XCTAssertEqual(savedWidths, Set(1...saveCount))
    }

    func testIndependentStoreNeverReplacesAnExistingDestination() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let firstStore = ImageStore(folder: folder, now: { fixedDate })
        let existingURL = try firstStore.save(data: Self.onePixelPNG)
        let existingData = try Data(contentsOf: existingURL)

        let secondStore = ImageStore(folder: folder, now: { fixedDate })
        let secondURL = try secondStore.save(data: Self.png(width: 2))

        XCTAssertNotEqual(secondURL, existingURL)
        XCTAssertEqual(try Data(contentsOf: existingURL), existingData)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            ).count,
            2
        )
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PhoneSnapTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    /// Structurally complete PNG with a 100,000 x 100,000 IHDR. ImageIO can
    /// inspect its dimensions without decoding the intentionally empty image.
    private static let oversizedPNGHeader = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgABhqAAAYagCAYAAACoUgvIAAAACElEQVR4nAMAAAAAAUgGidIAAAAASUVORK5CYII="
    )!

    private static let oversizedPDF = Data("""
        %PDF-1.4
        1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 8000 8000]>>endobj
        trailer<</Root 1 0 R>>
        %%EOF
        """.utf8)

    private static func png(width: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw TestError.couldNotCreatePNG(width)
        }
        return data
    }

    private enum TestError: Error {
        case couldNotCreatePNG(Int)
        case couldNotDecode(URL)
    }
}

private final class LockedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

private final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
