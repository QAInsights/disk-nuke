import SwiftUI

@main
struct DiskNukeApp: App {
    @StateObject private var coordinator = ScanCoordinator()

    var body: some Scene {
        WindowGroup("Disk Nuke", id: "main") {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra("Disk Nuke", systemImage: "trash.circle") {
            QuickCleanView()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}
