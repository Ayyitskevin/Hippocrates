import SwiftData
import SwiftUI

@main
@MainActor
struct HippocratesApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try HippocratesStore.makeContainer()
        } catch {
            // Silently deleting a store or falling back to memory would turn a
            // migration failure into data loss. Fail loudly so it can be fixed.
            fatalError("Unable to open the Hippocrates data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // The modifier puts this container's main ModelContext in the SwiftUI
        // environment. Future @Query properties observe that same context.
        .modelContainer(modelContainer)
    }
}
