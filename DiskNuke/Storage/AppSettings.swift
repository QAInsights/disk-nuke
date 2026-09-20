import Foundation
import SwiftUI

enum CustomPathRule: Codable, Hashable {
    case wholeFolder
    case contents
    case olderThanDays(Int)
}

struct CustomScanPath: Identifiable, Codable, Hashable {
    var id = UUID()
    var path: String
    var rule: CustomPathRule
    var enabled: Bool = true
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var enabledCategories: Set<CleanupCategory> {
        didSet { save(enabledCategories.map(\.rawValue), forKey: "enabledCategories") }
    }
    @Published var downloadsAgeDays: Int {
        didSet { defaults.set(downloadsAgeDays, forKey: "downloadsAgeDays") }
    }
    @Published var minSizeMB: Int {
        didSet { defaults.set(minSizeMB, forKey: "minSizeMB") }
    }
    @Published var minAgeDays: Int {
        didSet { defaults.set(minAgeDays, forKey: "minAgeDays") }
    }
    @Published var largeFileThresholdMB: Int {
        didSet { defaults.set(largeFileThresholdMB, forKey: "largeFileThresholdMB") }
    }
    @Published var exclusions: [String] {
        didSet { defaults.set(exclusions, forKey: "exclusions") }
    }
    @Published var customPaths: [CustomScanPath] {
        didSet {
            if let data = try? JSONEncoder().encode(customPaths) {
                defaults.set(String(data: data, encoding: .utf8), forKey: "customPaths")
            }
        }
    }
    @Published var lastScanDate: Date? {
        didSet { defaults.set(lastScanDate, forKey: "lastScanDate") }
    }

    private init() {
        let d = UserDefaults.standard
        if let arr = d.stringArray(forKey: "enabledCategories") {
            enabledCategories = Set(arr.compactMap { CleanupCategory(rawValue: $0) })
        } else {
            enabledCategories = Set(CleanupCategory.allCases.filter { $0.isSafeForQuickClean })
        }
        downloadsAgeDays = d.object(forKey: "downloadsAgeDays") as? Int ?? 30
        minSizeMB = d.object(forKey: "minSizeMB") as? Int ?? 0
        minAgeDays = d.object(forKey: "minAgeDays") as? Int ?? 0
        largeFileThresholdMB = d.object(forKey: "largeFileThresholdMB") as? Int ?? 100
        exclusions = d.stringArray(forKey: "exclusions") ?? []
        if let s = d.string(forKey: "customPaths"), let data = s.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([CustomScanPath].self, from: data) {
            customPaths = decoded
        } else {
            customPaths = []
        }
        lastScanDate = d.object(forKey: "lastScanDate") as? Date

        applyExtraScanRoot()
    }

    private func save(_ rawValues: [String], forKey key: String) {
        defaults.set(rawValues, forKey: key)
    }

    /// Launch argument `-extraScanRoot /path` (or env DISK_NUKE_EXTRA_ROOT) seeds a
    /// custom scan path for testing.
    private func applyExtraScanRoot() {
        let root = defaults.string(forKey: "extraScanRoot")
            ?? ProcessInfo.processInfo.environment["DISK_NUKE_EXTRA_ROOT"]
        guard let root, !root.isEmpty,
              !customPaths.contains(where: { $0.path == root }) else { return }
        customPaths.append(CustomScanPath(path: root, rule: .contents, enabled: true))
    }

    func isCategoryEnabled(_ c: CleanupCategory) -> Bool { enabledCategories.contains(c) }

    func setCategory(_ c: CleanupCategory, enabled: Bool) {
        if enabled { enabledCategories.insert(c) } else { enabledCategories.remove(c) }
    }
}
