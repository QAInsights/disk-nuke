import Foundation

actor ScanEngine {
    /// Scans the given categories with limited concurrency, reporting progress.
    func scan(categories: [CleanupCategory],
              settings: AppSettings,
              progress: @escaping @Sendable (CategoryResult) -> Void) async -> [CategoryResult] {
        var results = [CleanupCategory: CategoryResult]()
        for c in categories {
            var r = CategoryResult(category: c)
            r.status = settings.enabledCategories.contains(c) ? .pending : .skippedDisabled
            results[c] = r
            progress(r)
        }

        let enabled = categories.filter { settings.enabledCategories.contains($0) }
        await withTaskGroup(of: CategoryResult.self) { group in
            var iterator = enabled.makeIterator()
            var inFlight = 0
            let maxConcurrent = 4

            func enqueue() {
                while inFlight < maxConcurrent, let cat = iterator.next() {
                    inFlight += 1
                    let settingsCopy = settings
                    group.addTask {
                        await Self.scanCategory(cat, settings: settingsCopy, progress: progress)
                    }
                }
            }
            enqueue()
            while let result = await group.next() {
                inFlight -= 1
                results[result.category] = result
                progress(result)
                enqueue()
            }
        }
        return categories.compactMap { results[$0] }
    }

    private static func scanCategory(
        _ category: CleanupCategory,
        settings: AppSettings,
        progress: @escaping @Sendable (CategoryResult) -> Void
    ) async -> CategoryResult {
        var result = CategoryResult(category: category)
        result.status = .scanning
        result.progressText = "Scanning…"
        progress(result)

        do {
            try Task.checkCancellation()
            let urls = try await resolveURLs(for: category.rule)
            var items: [ScanItem] = []
            var permissionErrors = 0
            let minBytes = Int64(settings.minSizeMB) * 1_000_000
            let cutoff = settings.minAgeDays > 0
                ? Date().addingTimeInterval(-Double(settings.minAgeDays) * 86400)
                : nil

            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                var permCount = 0
                let size = SizeCalculator.size(of: url, permissionErrors: &permCount)
                permissionErrors += permCount

                let keys: Set<URLResourceKey> = [
                    .isDirectoryKey, .contentAccessDateKey, .contentModificationDateKey,
                ]
                let v = try? url.resourceValues(forKeys: keys)
                if size < minBytes { continue }
                if let cutoff, let mod = v?.contentModificationDate, mod > cutoff { continue }

                var name = url.lastPathComponent
                if category == .xcodeSimulators,
                   let deviceName = CleanupCategory.simulatorDeviceName(for: url) {
                    name = deviceName
                }
                items.append(ScanItem(
                    url: url, name: name, size: size,
                    isDirectory: v?.isDirectory ?? true,
                    lastAccessed: v?.contentAccessDate,
                    modified: v?.contentModificationDate,
                    category: category))

                result.items = items
                result.totalBytes = items.reduce(0) { $0 + $1.size }
                result.progressText = "Scanning \(index + 1)/\(urls.count)…"
                progress(result)
            }

            result.items = items.sorted { $0.size > $1.size }
            result.totalBytes = result.items.reduce(0) { $0 + $1.size }
            if permissionErrors > 0 {
                result.status = .skippedPermission("Needs Full Disk Access (\(permissionErrors) item\(permissionErrors == 1 ? "" : "s") unreadable)")
            } else {
                result.status = .done
            }
            result.progressText = "\(result.items.count) items"
        } catch is CancellationError {
            result.status = .pending
            result.progressText = "Cancelled"
        } catch {
            if SizeCalculator.isPermissionError(error) {
                result.status = .skippedPermission("Needs Full Disk Access")
            } else {
                result.status = .error(error.localizedDescription)
            }
            result.progressText = ""
        }
        progress(result)
        return result
    }

    /// Expands a ScanRule into the list of item URLs.
    private static func resolveURLs(for rule: ScanRule) async throws -> [URL] {
        switch rule {
        case .directoryContents(let paths):
            return paths.flatMap { dir in
                (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil)) ?? []
            }
        case .directories(let paths):
            return paths.filter { FileManager.default.fileExists(atPath: $0.path) }
        case .namedFolders(let name, let roots, let maxDepth):
            var found: [URL] = []
            for root in roots {
                try findFolders(named: name, under: root, depth: 0, maxDepth: maxDepth, into: &found)
            }
            return found
        case .filesNamed(let names, let roots, let maxDepth):
            var found: [URL] = []
            for root in roots {
                try findFiles(named: names, under: root, depth: 0, maxDepth: maxDepth, into: &found)
            }
            return found
        case .olderThan(let days, let path):
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: path, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return children.filter { child in
                guard let mod = try? child.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate else { return false }
                return mod < cutoff
            }
        case .command(let candidates, let arguments, let fallback):
            if let resolved = runCommand(candidates: candidates, arguments: arguments) {
                return [resolved]
            }
            return FileManager.default.fileExists(atPath: fallback.path) ? [fallback] : []
        }
    }

    private static func findFolders(named name: String, under dir: URL, depth: Int,
                                    maxDepth: Int, into out: inout [URL]) throws {
        try Task.checkCancellation()
        guard depth <= maxDepth else { return }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants])) ?? []
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if child.lastPathComponent == name {
                out.append(child)
            } else if !child.lastPathComponent.hasPrefix(".") || name.hasPrefix(".") {
                try findFolders(named: name, under: child, depth: depth + 1, maxDepth: maxDepth, into: &out)
            }
        }
    }

    private static func findFiles(named names: [String], under dir: URL, depth: Int,
                                  maxDepth: Int, into out: inout [URL]) throws {
        try Task.checkCancellation()
        guard depth <= maxDepth else { return }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants])) ?? []
        for child in children {
            let last = child.lastPathComponent
            if names.contains(last) || (names.contains("._*") && last.hasPrefix("._")) {
                out.append(child)
                continue
            }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir),
               isDir.boolValue, !last.hasPrefix(".") {
                try findFiles(named: names, under: child, depth: depth + 1, maxDepth: maxDepth, into: &out)
            }
        }
    }

    private static func runCommand(candidates: [URL], arguments: [String]) -> URL? {
        for exe in candidates where FileManager.default.isExecutableFile(atPath: exe.path) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = exe
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch { continue }
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate(); continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0,
                  let out = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !out.isEmpty else { continue }
            let url = URL(fileURLWithPath: out)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
