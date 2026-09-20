import Foundation

enum ScanRule {
    /// Every child of these directories is one item.
    case directoryContents(paths: [URL])
    /// Each path itself is one item.
    case directories(paths: [URL])
    /// Find folders with `name` under `roots`, descending at most `maxDepth` levels.
    case namedFolders(name: String, roots: [URL], maxDepth: Int)
    /// Find files with names in `names` under `roots`, descending at most `maxDepth` levels.
    case filesNamed(names: [String], roots: [URL], maxDepth: Int)
    /// Direct children of `path` not modified within `days`.
    case olderThan(days: Int, path: URL)
    /// Resolve a directory by running a command (e.g. `brew --cache`) with a fallback.
    case command(executableCandidates: [URL], arguments: [String], fallback: URL)
}
