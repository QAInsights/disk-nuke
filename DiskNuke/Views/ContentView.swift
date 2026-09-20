import SwiftUI

private enum SidebarSelection: Hashable {
    case overview
    case largeFiles
    case customPaths
    case category(CleanupCategory)
}

struct ContentView: View {
    @EnvironmentObject private var coordinator: ScanCoordinator
    @State private var selection: SidebarSelection? = .overview
    @State private var itemSortOrder = [KeyPathComparator(\ScanItem.size, order: .reverse)]

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detail
        }
        .sheet(isPresented: $coordinator.showConfirmSheet) {
            ConfirmNukeSheet()
                .environmentObject(coordinator)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Tools") {
                Label("Overview", systemImage: "chart.pie")
                    .tag(SidebarSelection.overview)
                Label("Large Files", systemImage: "doc.zipper")
                    .tag(SidebarSelection.largeFiles)
                Label("Custom Paths", systemImage: "folder.badge.plus")
                    .tag(SidebarSelection.customPaths)
            }
            ForEach(CategoryGroup.allCases) { group in
                Section(group.title) {
                    ForEach(categories(in: group)) { cat in
                        sidebarRow(for: cat)
                            .tag(SidebarSelection.category(cat))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func categories(in group: CategoryGroup) -> [CleanupCategory] {
        CleanupCategory.allCases.filter { $0.group == group }
    }

    @ViewBuilder
    private func sidebarRow(for cat: CleanupCategory) -> some View {
        let result = coordinator.result(for: cat)
        HStack(spacing: 8) {
            Image(systemName: cat.sfSymbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(cat.title)
                sidebarSubtitle(cat: cat, result: result)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            statusIndicator(cat: cat, result: result)
        }
        .contextMenu {
            if let result, !result.items.isEmpty {
                Button("Select All") { coordinator.selectAllInCategory(cat) }
            }
        }
    }

    @ViewBuilder
    private func sidebarSubtitle(cat: CleanupCategory, result: CategoryResult?) -> some View {
        switch result?.status {
        case .skippedPermission(let msg):
            Text(msg)
        case .skippedDisabled:
            Text("Disabled")
        case .done:
            Text(Formatters.formatBytes(result?.totalBytes ?? 0))
        case .scanning:
            Text(result?.progressText ?? "Scanning…")
        case .error(let msg):
            Text(msg)
        default:
            Text(cat.subtitle)
        }
    }

    @ViewBuilder
    private func statusIndicator(cat: CleanupCategory, result: CategoryResult?) -> some View {
        switch result?.status {
        case .scanning:
            ProgressView().controlSize(.small)
        case .skippedPermission:
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .help("Needs Full Disk Access — grant in Settings → Privacy & Security")
        case .skippedDisabled:
            Image(systemName: "circle.slash")
                .foregroundStyle(.tertiary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .done:
            Text(Formatters.formatBytes(result?.totalBytes ?? 0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            switch selection {
            case .largeFiles:
                LargeFilesView()
                    .environmentObject(coordinator)
            case .customPaths:
                customPathsDetail
            case .category(let cat):
                categoryDetail(cat)
            default:
                overviewDetail
            }
            Divider()
            bottomBar
        }
    }

    private var heroCard: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.formatGB(coordinator.totalReclaimable + customTotal))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(colors: [Color(red: 1, green: 0.48, blue: 0.1),
                                                Color(red: 1, green: 0.75, blue: 0.1)],
                                       startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
                    .animation(.default, value: coordinator.totalReclaimable)
                Text("Reclaimable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                statRow("Items", value: "\(allItemCount)")
                statRow("Selected", value: Formatters.formatBytes(coordinator.selectedBytes))
                statRow("Last freed", value: Formatters.formatBytes(coordinator.lastFreedBytes))
                if let d = coordinator.settings.lastScanDate {
                    statRow("Last scan", value: Formatters.formatRelative(d))
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top])
    }

    private var customTotal: Int64 {
        coordinator.customResults.values.flatMap { $0 }.reduce(0) { $0 + $1.size }
    }

    private var allItemCount: Int { coordinator.allItems.count }

    private func statRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.callout)
    }

    private var overviewDetail: some View {
        VStack(spacing: 0) {
            heroCard
            if coordinator.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(coordinator.scanProgressText).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { coordinator.cancel() }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            if coordinator.hasScanned {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                              spacing: 12) {
                        ForEach(coordinator.results) { r in
                            categoryCard(r)
                        }
                    }
                    .padding()
                }
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
                Image(systemName: "radiation")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                    .offset(y: 2)
            }
            Text("Scan your disk for junk")
                .font(.title2).fontWeight(.semibold)
            Text("Caches, logs, build artifacts, old downloads —\nfind what's eating your disk and nuke it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Scan") { coordinator.startScan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryCard(_ r: CategoryResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: r.category.sfSymbol)
                    .foregroundStyle(Color.accentColor)
                Text(r.category.title).fontWeight(.medium)
                Spacer()
                if r.status == .scanning {
                    ProgressView().controlSize(.small)
                }
            }
            Text(Formatters.formatBytes(r.totalBytes))
                .font(.title3.monospacedDigit())
            Text(cardStatusText(r))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onTapGesture { selection = .category(r.category) }
    }

    private func cardStatusText(_ r: CategoryResult) -> String {
        switch r.status {
        case .pending: return "Pending"
        case .scanning: return r.progressText
        case .done: return "\(r.items.count) items"
        case .skippedPermission(let m): return m
        case .skippedDisabled: return "Disabled"
        case .error(let m): return m
        }
    }

    private func categoryDetail(_ cat: CleanupCategory) -> some View {
        VStack(spacing: 0) {
            heroCard
            if let r = coordinator.result(for: cat) {
                itemsTable(r.items)
            }
        }
    }

    private var customPathsDetail: some View {
        VStack(spacing: 0) {
            heroCard
            if coordinator.customResults.isEmpty {
                ContentUnavailableView(
                    "No Custom Paths",
                    systemImage: "folder.badge.plus",
                    description: Text("Add folders in Settings → Custom Paths."))
            } else {
                itemsTable(coordinator.customResults.values.flatMap { $0 })
            }
        }
    }

    private func itemsTable(_ items: [ScanItem]) -> some View {
        let sorted = items.sorted(using: itemSortOrder)
        return Table(sorted, sortOrder: $itemSortOrder) {
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
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .foregroundStyle(.secondary)
                    Text(item.name)
                    if coordinator.guard_.isProtected(item.url) != nil {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .help("Protected path")
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
                Text(Formatters.formatBytes(item.size))
                    .monospacedDigit()
            }
            .width(90)
            TableColumn("Last Accessed", value: \.lastAccessedInterval) { item in
                Text(Formatters.formatRelative(item.lastAccessed))
                    .foregroundStyle(.secondary)
            }
            .width(110)
        }
        .contextMenu(forSelectionType: ScanItem.ID.self) { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Button("Exclude This Path") {
                    coordinator.settings.exclusions.append(item.url.path)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if coordinator.isScanning {
                ProgressView().controlSize(.small)
                Text(coordinator.scanProgressText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Select All Safe") { coordinator.selectAllSafe() }
                .disabled(coordinator.isScanning)
            if coordinator.isDeleting {
                ProgressView().controlSize(.small)
                Text(coordinator.deleteProgress).foregroundStyle(.secondary)
            }
            Button("Nuke Selected") { coordinator.buildPlan() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(coordinator.selection.isEmpty || coordinator.isScanning || coordinator.isDeleting)
            Button("Scan") { coordinator.startScan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(coordinator.isScanning)
        }
        .padding(12)
    }
}
