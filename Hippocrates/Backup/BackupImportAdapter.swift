import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// I-010: the one reviewed local-file ingress path. It presents the system file
/// importer for a single JSON backup, requires a local file, acquires and
/// releases security-scoped access around one immediate read into app-owned
/// Data, and exposes no URL-opening, remote-scheme, or sharing behavior. The
/// boundary scanner pins this exact body; any drift fails the build. All
/// validation and the de-identification gate run on the returned Data before
/// any store mutation.
struct BackupImportAdapter: ViewModifier {
    @Binding var isPresented: Bool
    let onData: (Data) -> Void
    let onFailure: () -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(selection) = result,
                let file = selection.first,
                file.isFileURL else {
                onFailure()
                return
            }
            let didAccess = file.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    file.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: file) else {
                onFailure()
                return
            }
            onData(data)
        }
    }
}
