import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The backup file leaves the app only as app-owned bytes.
struct BackupTransferable: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { transferable in
            transferable.data
        }
    }
}

/// Full-backup export (Milestone 7). Generating an archive records the I-011
/// timestamp; sharing hands the bytes to the system sheet. Restore joins the
/// first-run gate in the next build step (I-003, I-010).
struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var lastCreated: Date?
    @State private var backupData: Data?
    @State private var failureText: String?

    var body: some View {
        List {
            Section("Full backup") {
                LabeledContent("Last backup created") {
                    if let lastCreated {
                        Text(lastCreated, format: .dateTime.year().month().day())
                    } else {
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Generate backup") {
                    generate()
                }
                if let backupData {
                    ShareLink(
                        item: BackupTransferable(data: backupData),
                        preview: SharePreview("Hippocrates backup")
                    ) {
                        Text("Share backup file")
                    }
                }
            }
            Section {
                Text("The backup is a complete copy of your records as one file. Save it somewhere you control, such as your files or another device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Created means the file was generated and offered to the share sheet. The app cannot confirm where it was saved or delivered.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("iOS does not reliably report whether device or iCloud backup is enabled, so this app makes no claim about it either way.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Restoring a backup into a fresh installation arrives in an upcoming build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Backup")
        .alert("Could not create the backup", isPresented: failureAlertBinding) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(failureText ?? "Try again.")
        }
        .onAppear(perform: reload)
    }

    private var failureAlertBinding: Binding<Bool> {
        Binding(
            get: { failureText != nil },
            set: { isPresented in
                if isPresented == false {
                    failureText = nil
                }
            }
        )
    }

    private func reload() {
        lastCreated = try? BackupExportService.lastExportAt(in: modelContext)
    }

    private func generate() {
        do {
            backupData = try BackupExportService.makeBackupData(in: modelContext)
            try BackupExportService.recordBackupCreated(in: modelContext)
            reload()
        } catch {
            failureText = "The backup could not be generated. Try again."
        }
    }
}
