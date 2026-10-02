import Foundation

/// Where Copper Kit keeps its files: one JSON document and a folder of photos under
/// Application Support.
struct StoragePaths {
    let root: URL

    static func standard(folderName: String = "CopperKit") -> StoragePaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StoragePaths(root: base.appendingPathComponent(folderName, isDirectory: true))
    }

    var document: URL { root.appendingPathComponent("workshop.json") }
    var photos: URL { root.appendingPathComponent("Photos", isDirectory: true) }
}

/// The workshop, held in memory and written through to disk.
///
/// `transact` is the whole transaction story: the change runs against a copy, the copy
/// is written atomically, and only a successful write becomes the workshop the app
/// reads. A rule that throws — or a disk that refuses — leaves memory and file exactly
/// as they were.
final class FileWorkshopRepository: WorkshopRepository {
    private(set) var workshop: Workshop
    private let paths: StoragePaths
    private let clock: Clock

    /// Called after every successful change so the presentation layer can refresh.
    var onChange: ((Workshop) -> Void)?

    /// A problem found while opening, surfaced once the interface is on screen.
    private(set) var loadProblem: String?
    /// Set when the file belongs to a newer build: it is left untouched and nothing is written.
    private(set) var isReadOnly = false

    init(paths: StoragePaths = .standard(), clock: Clock = SystemClock()) {
        self.paths = paths
        self.clock = clock
        workshop = Workshop()
        load()
    }

    @discardableResult
    func transact<T>(_ change: (inout Workshop) throws -> T) throws -> T {
        guard !isReadOnly else {
            throw DomainError("Your workshop was saved by a newer version of Copper Kit. Update the app to make changes.")
        }
        var candidate = workshop
        let result = try change(&candidate)
        if candidate != workshop {
            try write(candidate)
            workshop = candidate
            onChange?(candidate)
        }
        return result
    }

    func replaceAll(with workshop: Workshop) throws {
        guard !isReadOnly else {
            throw DomainError("Your workshop was saved by a newer version of Copper Kit. Update the app to make changes.")
        }
        try write(workshop)
        self.workshop = workshop
        onChange?(workshop)
    }

    // MARK: - Disk

    private func load() {
        let url = paths.document
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let dto = try Self.decoder.decode(WorkshopDocumentDTO.self, from: data)
            if let version = dto.schemaVersion, version > Workshop.currentSchemaVersion {
                isReadOnly = true
                loadProblem = WorkshopVersionError(found: version).errorDescription
                return
            }
            workshop = WorkshopMapper.workshop(from: dto)
        } catch {
            // Keep the unreadable file beside the new one instead of destroying it.
            let stamp = Int(clock.now.timeIntervalSince1970)
            let aside = paths.root.appendingPathComponent("workshop-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            loadProblem = "Your saved workshop could not be read, so Copper Kit started empty. The old file was kept as \(aside.lastPathComponent)."
        }
    }

    private func write(_ workshop: Workshop) throws {
        do {
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(WorkshopMapper.dto(from: workshop, savedAt: clock.now))
            #if os(iOS)
            try data.write(to: paths.document, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: paths.document, options: [.atomic])
            #endif
        } catch {
            throw DomainError("Copper Kit could not save this change (\(error.localizedDescription)). Nothing was changed.")
        }
    }

    // MARK: - Coding

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let text = try container.decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date \(text)")
        }
        return decoder
    }()
}
