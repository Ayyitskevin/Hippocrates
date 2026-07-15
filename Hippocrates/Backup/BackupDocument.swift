import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(archive: BackupArchive) throws {
        self.data = try BackupCodec.encode(archive)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Reject malformed JSON here. Format-version and relationship-graph
        // validation happens immediately before the restore transaction.
        _ = try BackupCodec.decode(data)
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// `ShareLink` shares this Data representation as a file-like JSON item. It does
/// not share a URL, so the system has no link-preview metadata to fetch.
struct BackupTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { transfer in
            transfer.data
        }
        .suggestedFileName("Hippocrates Backup.json")
    }
}
