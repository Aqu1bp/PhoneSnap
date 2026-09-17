import Foundation

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

    func readImage(_ path: String, isCurrent: () -> Bool = { true }) throws -> (Data, Date?) {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        let before = try info(path)
        guard before["st_ifmt"] == "S_IFREG", let size = before["st_size"].flatMap(Int.init), size > 0 else {
            throw PhoneConnectionError.incomplete
        }
        guard size <= 32 * 1024 * 1024 else { throw PhoneConnectionError.unsupported }
        let data = try readFile(path, size: size, deadline: deadline, isCurrent: isCurrent)
        let after = try info(path)
        guard data.count == size, before["st_size"] == after["st_size"], before["st_mtime"] == after["st_mtime"],
              CompleteImage.isComplete(data) else { throw PhoneConnectionError.incomplete }
        let date = after["st_birthtime"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1_000_000_000) }
        return (data, date)
    }
}
