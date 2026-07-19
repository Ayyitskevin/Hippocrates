import SwiftData
import SwiftUI

/// The capture-ready home. Ordinary launches land here directly (architecture:
/// no dashboard, no recurring welcome). Capture is the first tab; the recent
/// ledger and category settings are one tap away.
struct CaptureHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showsBackupReminder = false

    var body: some View {
        TabView {
            Tab("Capture", systemImage: "plus.circle.fill") {
                CaptureView()
            }
            Tab("Recent", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    RecentLedgerView()
                }
            }
            Tab("Summary", systemImage: "chart.bar.xaxis") {
                NavigationStack {
                    SummaryView()
                }
            }
            Tab("DI Vault", systemImage: "books.vertical") {
                NavigationStack {
                    DIVaultView()
                }
            }
            Tab("Categories", systemImage: "slider.horizontal.3") {
                TaxonomySettingsView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsBackupReminder {
                reminderBanner
            }
        }
        .onAppear(perform: refreshReminder)
    }

    /// I-011: dismissal is view-local for this session; the reminder returns
    /// on a later launch until a new backup is created. Copy says created,
    /// never delivered.
    private var reminderBanner: some View {
        HStack(spacing: 12) {
            Text("Your last backup was created over 90 days ago. Create a fresh one in Categories, under Backup.")
                .font(.footnote)
            Spacer()
            Button("Dismiss") {
                showsBackupReminder = false
            }
            .font(.footnote)
            .bold()
        }
        .padding(12)
        .background(.thinMaterial)
    }

    private func refreshReminder() {
        let lastExportAt = try? BackupExportService.lastExportAt(in: modelContext)
        showsBackupReminder = BackupReminderPolicy.shouldRemind(
            lastExportAt: lastExportAt ?? nil,
            now: .now
        )
    }
}
