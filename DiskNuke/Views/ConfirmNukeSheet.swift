import SwiftUI

struct ConfirmNukeSheet: View {
    @EnvironmentObject private var coordinator: ScanCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .confirm

    private enum Phase { case confirm, deleting, done }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .confirm: confirmView
            case .deleting: deletingView
            case .done: doneView
            }
        }
        .frame(width: 520, height: 480)
    }

    private var confirmView: some View {
        VStack(spacing: 16) {
            Image(systemName: "radiation")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            if let plan = coordinator.pendingPlan {
                Text("Delete \(Formatters.plural(plan.items.count, "item")) (\(Formatters.plural(plan.fileCount, "file"))) — \(Formatters.formatBytes(plan.totalBytes))")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Permanent. Cannot be undone.")
                    .foregroundStyle(.red)
                    .font(.callout)
                List(plan.items) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                        Text(item.url.path(percentEncoded: false))
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Spacer()
                        Text(Formatters.formatBytes(item.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Nuke") {
                    phase = .deleting
                    runDelete()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var deletingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(coordinator.deleteProgress)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            if let report = coordinator.lastReport {
                Text("Reclaimed \(Formatters.formatBytes(report.bytesFreed))")
                    .font(.title2).fontWeight(.semibold)
                Text("\(Formatters.plural(report.deleted.count, "item")) deleted")
                    .foregroundStyle(.secondary)
                if !report.failed.isEmpty {
                    DisclosureGroup("\(report.failed.count) failures") {
                        List(Array(report.failed.enumerated()), id: \.offset) { _, failure in
                            VStack(alignment: .leading) {
                                Text(failure.0.path(percentEncoded: false))
                                    .truncationMode(.middle)
                                    .lineLimit(1)
                                Text(failure.1).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func runDelete() {
        guard let plan = coordinator.pendingPlan else { return }
        let g = coordinator.guard_
        let coord = coordinator
        Task {
            let report = await Task.detached {
                await Deleter.performDelete(plan: plan, guard: g) { done, total, _ in
                    Task { @MainActor [weak coord] in
                        coord?.deleteProgress = "Deleting \(done)/\(total)…"
                    }
                }
            }.value
            await MainActor.run {
                coord.lastReport = report
                coord.lastFreedBytes = report.bytesFreed
                coord.pendingPlan = nil
                coord.selection.subtract(report.deleted)
                phase = .done
                coord.startScan()
            }
        }
    }
}
