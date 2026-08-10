import Foundation

/// Filesystem access behind a protocol so parsers and writers can be tested
/// without touching disk, and so every real write is atomic (spec §12.2).
public protocol FileSystemProviding: Sendable {
    func fileExists(atPath path: String) -> Bool
    func isDirectory(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func read(contentsOf url: URL) throws -> Data
    /// Writes atomically: content lands complete or not at all.
    func write(_ data: Data, to url: URL) throws
    func createDirectory(at url: URL) throws
}

/// The production filesystem.
public struct LiveFileSystem: FileSystemProviding {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    public func read(contentsOf url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
    }
}

/// Wall-clock access behind a protocol for deterministic tests.
public protocol ClockProviding: Sendable {
    func now() -> Date
}

public struct LiveClock: ClockProviding {
    public init() {}
    public func now() -> Date { Date() }
}

/// UUID generation behind a protocol for deterministic tests.
public protocol UUIDProviding: Sendable {
    func makeUUID() -> UUID
}

public struct LiveUUIDProvider: UUIDProviding {
    public init() {}
    public func makeUUID() -> UUID { UUID() }
}
