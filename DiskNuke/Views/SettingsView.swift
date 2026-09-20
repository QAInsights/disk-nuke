import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var coordinator: ScanCoordinator

    var body: some View {
        TabView {
            categoriesTab.tabItem { Label("Categories", systemImage: "checklist") }
            thresholdsTab.tabItem { Label("Thresholds", systemImage: "slider.horizontal.3") }
            customPathsTab.tabItem { Label("Custom Paths", systemImage: "folder.badge.plus") }
            exclusionsTab.tabItem { Label("Exclusions", systemImage: "eye.slash") }
            permissionsTab.tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 460)
    }

    private var settings: AppSettings { coordinator.settings }

    // MARK: Categories

    private var categoriesTab: some View {
        Form {
            ForEach(CategoryGroup.allCases) { group in
                Section(group.title) {
                    ForEach(CleanupCategory.allCases.filter { $0.group == group }) { cat in
                        Toggle(isOn: Binding(
                            get: { settings.isCategoryEnabled(cat) },
                            set: { settings.setCategory(cat, enabled: $0) })) {
                            HStack {
                                Text(cat.title)
                                if cat.isSafeForQuickClean {
                                    Text("safe for quick clean")
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15),
                                                    in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Thresholds

    private var thresholdsTab: some View {
        Form {
            Section("Item Filters") {
                Stepper("Downloads older than \(settings.downloadsAgeDays) days",
                        value: Binding(get: { settings.downloadsAgeDays },
                                       set: { settings.downloadsAgeDays = $0 }),
                        in: 1...365)
                Stepper("Minimum item size \(settings.minSizeMB) MB",
                        value: Binding(get: { settings.minSizeMB },
                                       set: { settings.minSizeMB = $0 }),
                        in: 0...10_000, step: 10)
                Stepper("Minimum item age \(settings.minAgeDays) days",
                        value: Binding(get: { settings.minAgeDays },
                                       set: { settings.minAgeDays = $0 }),
                        in: 0...365)
            }
            Section("Large Files") {
                Stepper("Threshold \(settings.largeFileThresholdMB) MB",
                        value: Binding(get: { settings.largeFileThresholdMB },
                                       set: { settings.largeFileThresholdMB = $0 }),
                        in: 10...10_000, step: 50)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Custom Paths

    private var customPathsTab: some View {
        VStack(spacing: 0) {
            List {
                ForEach(settings.customPaths) { cp in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { cp.enabled },
                            set: { newValue in update(cp) { $0.enabled = newValue } }))
                        .labelsHidden()
                        VStack(alignment: .leading) {
                            Text(cp.path).lineLimit(1).truncationMode(.middle)
                            Text(ruleLabel(cp.rule))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            settings.customPaths.removeAll { $0.id == cp.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                Button("Add Folder…") { pickFolder() }
                Spacer()
            }
            .padding(12)
        }
    }

    private func update(_ cp: CustomScanPath, _ mutate: (inout CustomScanPath) -> Void) {
        guard let idx = settings.customPaths.firstIndex(where: { $0.id == cp.id }) else { return }
        var copy = settings.customPaths[idx]
        mutate(&copy)
        settings.customPaths[idx] = copy
    }

    private func ruleLabel(_ rule: CustomPathRule) -> String {
        switch rule {
        case .wholeFolder: return "Delete whole folder"
        case .contents: return "Delete each item inside"
        case .olderThanDays(let d): return "Items older than \(d) days"
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.customPaths.append(
            CustomScanPath(path: url.path, rule: .contents, enabled: true))
    }

    // MARK: Exclusions

    private var exclusionsTab: some View {
        VStack(spacing: 0) {
            List {
                ForEach(settings.exclusions, id: \.self) { ex in
                    HStack {
                        Text(ex).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            settings.exclusions.removeAll { $0 == ex }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                Button("Add Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url {
                        settings.exclusions.append(url.path)
                    }
                }
                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: Permissions

    private var permissionsTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Full Disk Access")
                .font(.title2).fontWeight(.semibold)
            Text("Some locations (Mail, Safari, certain caches) require\nFull Disk Access. Without it, affected categories show\na lock icon and report what could not be read.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            if !coordinator.permissionSkipped.isEmpty {
                Text("Skipped: " + coordinator.permissionSkipped
                    .map(\.category.title).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(32)
    }
}
