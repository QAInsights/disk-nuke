import SwiftUI

struct LargeFilesView: View {
    @EnvironmentObject private var coordinator: ScanCoordinator
    @State private var sortOrder = [KeyPathComparator(\ScanItem.size, order: .reverse)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Large Files").font(.title2).fontWeight(.semibold)
                    Text("Find files ≥ \(coordinator.settings.largeFileThresholdMB) MB in your home folder.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Stepper("≥ \(coordinator.settings.largeFileThresholdMB) MB",
                        value: Binding(
                            get: { coordinator.settings.largeFileThresholdMB },
                            set: { coordinator.settings.largeFileThresholdMB = $0 }),
                        in: 10...10_000, step: 50)
                Button("Scan Home Folder") { coordinator.scanLargeFiles() }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.isScanningLargeFiles)
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding([.horizontal, .top])

            if coordinator.isScanningLargeFiles {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(coordinator.largeFilesProgressText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Cancel") { coordinator.cancel() }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if coordinator.largeFiles.isEmpty && !coordinator.isScanningLargeFiles {
                ContentUnavailableView(
                    "No Large Files Yet",
                    systemImage: "doc.zipper",
                    description: Text(coordinator.largeFilesProgressText.isEmpty
                        ? "Run a scan to find the biggest space hogs."
                        : coordinator.largeFilesProgressText))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(coordinator.largeFiles.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn("") { item in
                        Toggle("", isOn: Binding(
                            get: { coordinator.selection.contains(item.id) },
                            set: { _ in coordinator.toggleSelect(item) }))
                        .labelsHidden()
                        .disabled(coordinator.guard_.isProtected(item.url) != nil)
                    }
                    .width(28)
                    TableColumn("Name", value: \.name) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(item.name)
                            if coordinator.guard_.isProtected(item.url) != nil {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.orange)
                                    .help("Protected path — cannot be deleted")
                            }
                        }
                    }
                    TableColumn("Path", value: \.url.path) { item in
                        Text(item.url.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    }
                    TableColumn("Size", value: \.size) { item in
                        Text(Formatters.formatBytes(item.size)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Last Accessed", value: \.lastAccessedInterval) { item in
                        Text(Formatters.formatRelative(item.lastAccessed))
                            .foregroundStyle(.secondary)
                    }
                    .width(110)
                }
                .contextMenu(forSelectionType: ScanItem.ID.self) { ids in
                    if let id = ids.first,
                       let item = coordinator.largeFiles.first(where: { $0.id == id }) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        Button("Exclude This Path") {
                            coordinator.settings.exclusions.append(item.url.path)
                        }
                    }
                }
            }
        }
    }
}
