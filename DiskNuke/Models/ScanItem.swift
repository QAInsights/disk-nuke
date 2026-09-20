import Foundation

struct ScanItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let lastAccessed: Date?
    let modified: Date?
    let category: CleanupCategory?

    var lastAccessedInterval: TimeInterval {
        lastAccessed?.timeIntervalSince1970 ?? 0
    }

    func hash(into hasher: inout Hasher) { hasher.combine(url) }
    static func == (lhs: ScanItem, rhs: ScanItem) -> Bool { lhs.url == rhs.url }
}
