import Foundation
import SwiftUI

@MainActor
final class ScanCoordinator: ObservableObject {
    @Published var results: [CategoryResult] = []
    @Published var largeFiles: [ScanItem] = []
    @Published var customResults: [CustomScanPath: [ScanItem]] = [:]
    @Published var selection = Set<ScanItem.ID>()
    @Published var isScanning = false
    @Published var isScanningLargeFiles = false
    @Published var scanProgressText = ""
    @Published var largeFilesProgressText = ""
    @Published var lastFreedBytes: Int64 = 0
    @Published var pendingPlan: DeletionPlan?
    @Published var isBuildingPlan = false
    @Published var isDeleting = false
    @Published var deleteProgress = ""
    @Published var lastReport: DeletionReport?
    @Published var showConfirmSheet = false

    let settings = AppSettings.shared
    private let engine = ScanEngine()
    private var scanTask: Task<Void, Never>?
    private var largeFilesTask: Task<Void, Never>?

    var guard_: SafetyGuard { SafetyGuard(userExclusions: settings.exclusions) }

    var totalReclaimable: Int64 {
        results.filter {
            switch $0.status {
            case .done, .skippedPermission: return true
            default: return false
            }
        }.reduce(0) { $0 + $1.totalBytes }
    }

    var permissionSkipped: [CategoryResult] {
        results.filter { if case .skippedPermission = $0.status { true } else { false } }
    }

    var allItems: [ScanItem] {
        results.flatMap(\.items) + customResults.values.flatMap { $0 }
    }

    var selectedItems: [ScanItem] {
        allItems.filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var hasScanned: Bool {
        results.contains { $0.status == .done || $0.status == .scanning }
            || !customResults.isEmpty
    }

    init() {
        results = CleanupCategory.allCases.map { CategoryResult(category: $0) }
    }

    func result(for category: CleanupCategory) -> CategoryResult? {
        results.first { $0.category == category }
    }

    func startScan() {
        cancel()
        isScanning = true
        scanProgressText = "Starting scan…"
        selection.removeAll()
        let settings = self.settings
        scanTask = Task {
            let cats = CleanupCategory.allCases
            let finalResults = await engine.scan(categories: cats, settings: settings) { [weak self] partial in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let idx = self.results.firstIndex(where: { $0.category == partial.category }) {
                        self.results[idx] = partial
                    }
                    self.scanProgressText = "\(partial.category.title): \(partial.progressText)"
                }
            }
            self.results = finalResults
            await scanCustomPaths()
            self.isScanning = false
            self.scanProgressText = ""
            self.settings.lastScanDate = Date()
        }
    }

    private func scanCustomPaths() async {
        var map: [CustomScanPath: [ScanItem]] = [:]
        for cp in settings.customPaths where cp.enabled {
            let url = URL(fileURLWithPath: NSString(string: cp.path).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let urls: [URL]
            switch cp.rule {
            case .wholeFolder:
                urls = [url]
            case .contents:
                urls = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil)) ?? []
            case .olderThanDays(let days):
                let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                urls = children.filter {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date()) < cutoff
                }
            }
            var items: [ScanItem] = []
            for child in urls {
                if Task.isCancelled { break }
                let size = SizeCalculator.size(of: child)
                let v = try? child.resourceValues(forKeys: [
                    .isDirectoryKey, .contentAccessDateKey, .contentModificationDateKey])
                items.append(ScanItem(
                    url: child, name: child.lastPathComponent, size: size,
                    isDirectory: v?.isDirectory ?? false,
                    lastAccessed: v?.contentAccessDate,
                    modified: v?.contentModificationDate,
                    category: nil))
            }
            map[cp] = items.sorted { $0.size > $1.size }
        }
        customResults = map
    }

    func cancel() {
        scanTask?.cancel()
        largeFilesTask?.cancel()
        isScanning = false
        isScanningLargeFiles = false
    }

    func toggleSelect(_ item: ScanItem) {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
    }

    func selectAllInCategory(_ category: CleanupCategory) {
        guard let r = result(for: category) else { return }
        for item in r.items where guard_.isDeletable(item.url) {
            selection.insert(item.id)
        }
    }

    func selectAllSafe() {
        for r in results where r.category.isSafeForQuickClean && r.status == .done {
            for item in r.items where guard_.isDeletable(item.url) {
                selection.insert(item.id)
            }
        }
    }

    func buildPlan() {
        let items = selectedItems.filter { guard_.isDeletable($0.url) }
        guard !items.isEmpty else { return }
        isBuildingPlan = true
        Task {
            let plan = await Task.detached { Deleter.makePlan(items: items) }.value
            self.pendingPlan = plan
            self.isBuildingPlan = false
            self.showConfirmSheet = true
        }
    }

    func nuke() {
        guard let plan = pendingPlan else { return }
        showConfirmSheet = false
        isDeleting = true
        deleteProgress = "Deleting…"
        let g = guard_
        Task {
            let report = await Task.detached {
                await Deleter.performDelete(plan: plan, guard: g) { done, total, _ in
                    Task { @MainActor [weak self] in
                        self?.deleteProgress = "Deleting \(done)/\(total)…"
                    }
                }
            }.value
            self.lastReport = report
            self.lastFreedBytes = report.bytesFreed
            self.isDeleting = false
            self.pendingPlan = nil
            self.selection.subtract(report.deleted)
            // Rescan affected categories.
            self.startScan()
        }
    }

    /// Scans safe enabled categories, then deletes every item found.
    func quickClean(progressText: @escaping @Sendable (String) -> Void) async -> (Int64, Int) {
        let settings = self.settings
        let safe = CleanupCategory.allCases.filter {
            $0.isSafeForQuickClean && settings.enabledCategories.contains($0)
        }
        progressText("Scanning…")
        let scanResults = await engine.scan(categories: safe, settings: settings) { [weak self] r in
            progressText("\(r.category.title): \(r.progressText)")
            Task { @MainActor [weak self] in
                if let idx = self?.results.firstIndex(where: { $0.category == r.category }) {
                    self?.results[idx] = r
                }
            }
        }
        await MainActor.run { self.results = mergeResults(scanResults) }
        let items = scanResults.flatMap(\.items)
        let g = guard_
        let plan = await Task.detached { Deleter.makePlan(items: items) }.value
        progressText("Deleting \(plan.fileCount) files…")
        let report = await Task.detached {
            await Deleter.performDelete(plan: plan, guard: g) { done, total, _ in
                progressText("Deleting \(done)/\(total)…")
            }
        }.value
        await MainActor.run {
            self.lastFreedBytes = report.bytesFreed
            self.lastReport = report
            self.settings.lastScanDate = Date()
        }
        return (report.bytesFreed, report.failed.count)
    }

    private func mergeResults(_ scanned: [CategoryResult]) -> [CategoryResult] {
        var merged = results
        for r in scanned {
            if let idx = merged.firstIndex(where: { $0.category == r.category }) {
                merged[idx] = r
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    func scanLargeFiles() {
        largeFilesTask?.cancel()
        isScanningLargeFiles = true
        let threshold = Int64(settings.largeFileThresholdMB) * 1_000_000
        let scanner = LargeFilesScanner()
        largeFilesTask = Task {
            let found = await scanner.scan(thresholdBytes: threshold) { scanned, dir, hits in
                Task { @MainActor [weak self] in
                    if dir.isEmpty {
                        self?.largeFilesProgressText = "\(scanned) files scanned"
                    } else {
                        self?.largeFilesProgressText =
                            "\(scanned) files scanned · \(hits) found · \(URL(fileURLWithPath: dir).lastPathComponent)"
                    }
                }
            }
            self.largeFiles = found
            self.isScanningLargeFiles = false
            self.largeFilesProgressText = "\(scanner.filesScanned) files scanned"
        }
    }
}
