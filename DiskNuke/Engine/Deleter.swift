import Foundation

struct DeletionPlan {
    let items: [ScanItem]
    let fileCount: Int
    let totalBytes: Int64
}

struct DeletionReport {
    var deleted: [URL] = []
    var failed: [(URL, String)] = []
    var bytesFreed: Int64 = 0
}

enum Deleter {
    static func makePlan(items: [ScanItem]) -> DeletionPlan {
        var fileCount = 0
        var bytes: Int64 = 0
        for item in items {
            fileCount += SizeCalculator.fileCount(of: item.url)
            bytes += item.size
        }
        return DeletionPlan(items: items, fileCount: fileCount, totalBytes: bytes)
    }

    /// Deletes plan items one by one; never throws out of the loop.
    static func performDelete(
        plan: DeletionPlan,
        guard guardObj: SafetyGuard,
        progress: @escaping @Sendable (Int, Int, URL) -> Void
    ) async -> DeletionReport {
        var report = DeletionReport()
        let total = plan.items.count
        for (index, item) in plan.items.enumerated() {
            if Task.isCancelled { break }
            progress(index, total, item.url)

            if let reason = guardObj.isProtected(item.url) {
                report.failed.append((item.url, reason.description))
                continue
            }
            do {
                try FileManager.default.removeItem(at: item.url)
                report.deleted.append(item.url)
                report.bytesFreed += item.size
            } catch {
                report.failed.append((item.url, error.localizedDescription))
            }
        }
        progress(total, total, URL(fileURLWithPath: "/"))
        return report
    }
}
