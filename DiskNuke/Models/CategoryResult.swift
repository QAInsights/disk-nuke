import Foundation

enum ScanStatus: Equatable {
    case pending
    case scanning
    case done
    case skippedPermission(String)
    case skippedDisabled
    case error(String)
}

struct CategoryResult: Identifiable, Equatable {
    var id: CleanupCategory { category }
    let category: CleanupCategory
    var items: [ScanItem] = []
    var totalBytes: Int64 = 0
    var status: ScanStatus = .pending
    var progressText: String = ""

    static func == (lhs: CategoryResult, rhs: CategoryResult) -> Bool {
        lhs.category == rhs.category && lhs.items == rhs.items &&
        lhs.totalBytes == rhs.totalBytes && lhs.status == rhs.status &&
        lhs.progressText == rhs.progressText
    }
}
