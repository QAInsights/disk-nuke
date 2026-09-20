import Foundation

/// Walks the home directory and reports the largest files above a threshold.
final class LargeFilesScanner: @unchecked Sendable {
    private(set) var filesScanned = 0
    private(set) var currentDirectory = ""

    func scan(thresholdBytes: Int64, limit: Int = 200,
              progress: @escaping @Sendable (Int, String, Int) -> Void) async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var results: [ScanItem] = []
        var scanned = 0

        var stack: [URL] = [home]
        while let dir = stack.popLast() {
            if Task.isCancelled { break }
            let path = dir.standardizedFileURL.path
            // Skip iCloud Drive container and hidden VCS dirs; include .Trash.
            if path == home.appendingPathComponent("Library/Mobile Documents").path { continue }
            if dir.lastPathComponent == ".git" { continue }

            let children = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isRegularFileKey, .fileSizeKey,
                    .totalFileAllocatedSizeKey, .contentAccessDateKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsPackageDescendants])) ?? []

            for child in children {
                if Task.isCancelled { break }
                let v = try? child.resourceValues(forKeys: [
                    .isDirectoryKey, .isRegularFileKey, .fileSizeKey,
                    .totalFileAllocatedSizeKey, .contentAccessDateKey,
                    .contentModificationDateKey,
                ])
                if v?.isDirectory == true {
                    stack.append(child)
                } else if v?.isRegularFile == true {
                    scanned += 1
                    let size = Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
                    if size >= thresholdBytes {
                        results.append(ScanItem(
                            url: child, name: child.lastPathComponent, size: size,
                            isDirectory: false,
                            lastAccessed: v?.contentAccessDate,
                            modified: v?.contentModificationDate,
                            category: nil))
                    }
                }
            }
            if scanned % 500 == 0 {
                progress(scanned, dir.path, results.count)
            }
        }
        filesScanned = scanned
        currentDirectory = ""
        progress(scanned, "", results.count)
        return Array(results.sorted { $0.size > $1.size }.prefix(limit))
    }
}
