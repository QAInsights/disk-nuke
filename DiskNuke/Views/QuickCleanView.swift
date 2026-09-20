import SwiftUI

struct QuickCleanView: View {
    @EnvironmentObject private var coordinator: ScanCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var working = false
    @State private var workText = ""
    @State private var showConfirm = false
    @State private var showResult = false
    @State private var freedBytes: Int64 = 0
    @State private var failureCount = 0

    var body: some View {
        VStack(spacing: 12) {
            Text(Formatters.formatGB(coordinator.totalReclaimable))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 1, green: 0.48, blue: 0.1),
                                            Color(red: 1, green: 0.75, blue: 0.1)],
                                   startPoint: .leading, endPoint: .trailing))
                .contentTransition(.numericText())
            Text("reclaimable")
                .foregroundStyle(.secondary)
            if let d = coordinator.settings.lastScanDate {
                Text("Last scan \(Formatters.formatRelative(d))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if working {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(workText).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button("Scan") {
                    guard !working else { return }
                    working = true
                    Task {
                        await MainActor.run { coordinator.startScan() }
                        while coordinator.isScanning {
                            workText = coordinator.scanProgressText
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                        working = false
                    }
                }
                .disabled(working)

                Button("Quick Clean") {
                    showConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(working)
            }

            Divider()

            HStack {
                Button("Open Disk Nuke") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .alert("Quick Clean", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Now", role: .destructive) { runQuickClean() }
        } message: {
            Text("Scan safe categories (caches, logs, temp files, trash) and delete everything found. This is permanent.")
        }
        .alert("Quick Clean Done", isPresented: $showResult) {
            Button("OK") {}
        } message: {
            Text("Reclaimed \(Formatters.formatBytes(freedBytes))" +
                 (failureCount > 0 ? " — \(failureCount) items failed" : ""))
        }
    }

    private func runQuickClean() {
        working = true
        Task {
            let (freed, failed) = await coordinator.quickClean { text in
                Task { @MainActor in workText = text }
            }
            working = false
            freedBytes = freed
            failureCount = failed
            showResult = true
        }
    }
}
