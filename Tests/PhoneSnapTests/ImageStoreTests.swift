import XCTest
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
