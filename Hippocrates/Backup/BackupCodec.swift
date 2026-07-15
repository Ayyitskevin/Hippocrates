import Foundation

enum BackupCodec {
    static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        // sortedKeys makes human inspection and diffs stable. The default Date
        // representation preserves subsecond values used by the round-trip test.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(BackupArchive.self, from: data)
    }
}
