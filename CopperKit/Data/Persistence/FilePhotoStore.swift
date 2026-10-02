import Foundation

/// Tool photos as individual JPEG files, referenced from the document by name, so
/// editing a tool rewrites a few kilobytes rather than every image.
final class FilePhotoStore: PhotoStoring {
    private let folder: URL
    private let cache = NSCache<NSString, NSData>()

    init(paths: StoragePaths = .standard()) {
        folder = paths.photos
    }

    func save(_ jpegData: Data) throws -> String {
        let id = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #if os(iOS)
            try jpegData.write(to: folder.appendingPathComponent(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try jpegData.write(to: folder.appendingPathComponent(id), options: [.atomic])
            #endif
        } catch {
            throw DomainError("The photo could not be saved (\(error.localizedDescription)).")
        }
        cache.setObject(jpegData as NSData, forKey: id as NSString)
        return id
    }

    func load(_ id: String) -> Data? {
        if let cached = cache.object(forKey: id as NSString) { return cached as Data }
        guard isSafe(id), let data = try? Data(contentsOf: folder.appendingPathComponent(id)) else { return nil }
        cache.setObject(data as NSData, forKey: id as NSString)
        return data
    }

    func delete(_ ids: [String]) {
        for id in ids where isSafe(id) {
            cache.removeObject(forKey: id as NSString)
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(id))
        }
    }

    func deleteAll() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Photo ids are file names we generated; anything with a path component is refused.
    private func isSafe(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("/") && !id.contains("..")
    }
}
