import Foundation

/// AFC size and modification time identify the version that failed validation.
struct PhoneFileRevision: Equatable {
    let size: String?
    let modifiedAt: String?
    init(_ metadata: [String: String]) {
        size = metadata["st_size"]; modifiedAt = metadata["st_mtime"]
    }
}

struct PhoneImage {
    let data: Data
    let capturedAt: Date?
    let revision: PhoneFileRevision

    /// A decoder rejection belongs to this file revision. Disk failures and
    /// cancellation remain retryable and must not consume its invalid-image budget.
    func deliver(_ handler: () throws -> Bool) throws -> Bool {
        do { return try handler() }
        catch ImageStore.SaveError.noImage { throw PhoneConnectionError.invalidImage(revision) }
        catch ImageStore.SaveError.imageTooLarge { throw PhoneConnectionError.unsupported }
    }
}

protocol PhonePhotoConnection: AnyObject {
    func openPhotos() throws
    func list(_ path: String) throws -> [String]
    func info(_ path: String) throws -> [String: String]
    func readFile(_ path: String, size: Int, deadline: TimeInterval, isCurrent: () -> Bool) throws -> Data
}

extension PhonePhotoConnection {
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

    func readImage(_ path: String, rejectedRevision: PhoneFileRevision? = nil, isCurrent: () -> Bool = { true }) throws -> PhoneImage {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        let before = try info(path)
        guard before["st_ifmt"] == "S_IFREG", let size = before["st_size"].flatMap(Int.init), size > 0 else {
            throw PhoneConnectionError.incomplete
        }
        guard size <= 32 * 1024 * 1024 else { throw PhoneConnectionError.unsupported }
        let revision = PhoneFileRevision(before)
        guard rejectedRevision != revision else { throw PhoneConnectionError.unchangedRejectedImage }
        let data = try readFile(path, size: size, deadline: deadline, isCurrent: isCurrent)
        let after = try info(path)
        guard data.count == size, revision == PhoneFileRevision(after) else { throw PhoneConnectionError.incomplete }
        guard CompleteImage.isComplete(data) else { throw PhoneConnectionError.invalidImage(revision) }
        let date = after["st_birthtime"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1_000_000_000) }
        return PhoneImage(data: data, capturedAt: date, revision: revision)
    }
}
