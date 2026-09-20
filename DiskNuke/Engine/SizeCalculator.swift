import Foundation

enum SizeCalculator {
    /// Recursively sums allocated file size under `url`. Counts permission errors.
    static func size(of url: URL, permissionErrors: UnsafeMutablePointer<Int>? = nil) -> Int64 {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey,
        ]
        var values: URLResourceValues?
        do { values = try url.resourceValues(forKeys: Set(keys)) } catch {
            if isPermissionError(error) { permissionErrors?.pointee += 1 }
            return 0
        }
        if values?.isRegularFile == true {
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        guard values?.isDirectory == true else { return 0 }

        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, error in
                if isPermissionError(error) { permissionErrors?.pointee += 1 }
                return true
            }) else { return 0 }

        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            let v = try? child.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true {
                total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == 257 || ns.code == 256) { return true }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == 1 || ns.code == 13) { return true }
        return false
    }

    /// File count under a URL (files only).
    static func fileCount(of url: URL) -> Int {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return 1 }
        var count = 0
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let c as URL in e {
            if Task.isCancelled { break }
            if (try? c.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }
}
