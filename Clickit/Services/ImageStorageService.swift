import Foundation

enum ImageStorageError: LocalizedError {
    case directoryUnavailable(underlying: Error)
    case writeFailed(underlying: Error)
    case missingFile(path: String)

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let underlying):
            "Could not prepare the Clickit image directory: \(underlying.localizedDescription)"
        case .writeFailed(let underlying):
            "Could not write the clipboard image: \(underlying.localizedDescription)"
        case .missingFile(let path):
            "The stored image \(path) is no longer on disk."
        }
    }
}

/// Reads and writes the image blobs that back `.image` history entries.
///
/// Records in the store hold only a relative filename; the bytes live on disk
/// under Application Support. Keeping the two apart means the history can be
/// loaded and searched without paging megabytes of screenshots into memory.
protocol ImageStoring: Sendable {
    /// Persists PNG data and returns the relative filename to record.
    func store(data: Data) throws -> String
    func loadData(relativePath: String) throws -> Data
    func delete(relativePath: String) throws
    func byteSize(relativePath: String) -> Int
    func url(forRelativePath relativePath: String) -> URL

    /// Every file currently held. Used to find images left behind by records
    /// that no longer exist. Exposed here rather than having callers read the
    /// directory themselves, so the storage location stays owned by one type.
    func storedFilenames() throws -> [String]
}

struct ImageStorageService: ImageStoring {
    let directory: URL

    /// `~/Library/Application Support/Clickit/Images`
    static func defaultDirectory() throws -> URL {
        try ClickitDirectories.images()
    }

    init(directory: URL) {
        self.directory = directory
    }

    init() throws {
        do {
            self.directory = try Self.defaultDirectory()
        } catch {
            throw ImageStorageError.directoryUnavailable(underlying: error)
        }
    }

    private func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ImageStorageError.directoryUnavailable(underlying: error)
        }
    }

    func store(data: Data) throws -> String {
        try ensureDirectoryExists()
        let filename = "\(UUID().uuidString).png"
        do {
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        } catch {
            throw ImageStorageError.writeFailed(underlying: error)
        }
        return filename
    }

    func loadData(relativePath: String) throws -> Data {
        let fileURL = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ImageStorageError.missingFile(path: relativePath)
        }
        return try Data(contentsOf: fileURL)
    }

    func delete(relativePath: String) throws {
        let fileURL = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func byteSize(relativePath: String) -> Int {
        let fileURL = url(forRelativePath: relativePath)
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return size
    }

    func url(forRelativePath relativePath: String) -> URL {
        directory.appendingPathComponent(relativePath)
    }

    func storedFilenames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }
}
