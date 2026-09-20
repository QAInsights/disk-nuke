import Foundation

enum CategoryGroup: String, CaseIterable, Identifiable {
    case system, xcode, developer, browsers, downloads, metadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .xcode: return "Xcode"
        case .developer: return "Developer"
        case .browsers: return "Browsers"
        case .downloads: return "Downloads"
        case .metadata: return "Metadata"
        }
    }
}

enum CleanupCategory: String, CaseIterable, Identifiable, Codable {
    case appCaches, logs, tempFiles, trash
    case xcodeDerivedData, xcodeDeviceSupport, xcodeSimulators, xcodeArchives
    case nodeModules, swiftBuild, gradle, homebrewCache
    case safariCache, chromeCache, firefoxCache
    case oldDownloads, mailDownloads
    case dsStore

    var id: String { rawValue }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static func library(_ path: String) -> URL {
        home.appendingPathComponent("Library").appendingPathComponent(path)
    }

    var title: String {
        switch self {
        case .appCaches: return "App Caches"
        case .logs: return "Logs"
        case .tempFiles: return "Temp Files"
        case .trash: return "Trash"
        case .xcodeDerivedData: return "Xcode DerivedData"
        case .xcodeDeviceSupport: return "Xcode Device Support"
        case .xcodeSimulators: return "Xcode Simulators"
        case .xcodeArchives: return "Xcode Archives"
        case .nodeModules: return "node_modules"
        case .swiftBuild: return "Swift .build"
        case .gradle: return "Gradle Caches"
        case .homebrewCache: return "Homebrew Cache"
        case .safariCache: return "Safari Cache"
        case .chromeCache: return "Chrome Cache"
        case .firefoxCache: return "Firefox Cache"
        case .oldDownloads: return "Old Downloads"
        case .mailDownloads: return "Mail Downloads"
        case .dsStore: return ".DS_Store Files"
        }
    }

    var subtitle: String {
        switch self {
        case .appCaches: return "~/Library/Caches and system caches"
        case .logs: return "User, system, and diagnostic logs"
        case .tempFiles: return "Temporary directories"
        case .trash: return "~/.Trash"
        case .xcodeDerivedData: return "Build intermediates and indexes"
        case .xcodeDeviceSupport: return "Symbols downloaded from devices"
        case .xcodeSimulators: return "Installed simulator devices"
        case .xcodeArchives: return "App archives"
        case .nodeModules: return "Node.js dependency folders"
        case .swiftBuild: return "SwiftPM build directories"
        case .gradle: return "~/.gradle and project .gradle folders"
        case .homebrewCache: return "Downloaded bottles and source tarballs"
        case .safariCache: return "Safari web caches"
        case .chromeCache: return "Chrome web caches"
        case .firefoxCache: return "Firefox web caches"
        case .oldDownloads: return "Stale files in ~/Downloads"
        case .mailDownloads: return "Saved Mail attachments"
        case .dsStore: return "Finder metadata files"
        }
    }

    var sfSymbol: String {
        switch self {
        case .appCaches: return "archivebox"
        case .logs: return "doc.text.magnifyingglass"
        case .tempFiles: return "clock.arrow.circlepath"
        case .trash: return "trash"
        case .xcodeDerivedData: return "hammer"
        case .xcodeDeviceSupport: return "iphone"
        case .xcodeSimulators: return "ipad.and.iphone"
        case .xcodeArchives: return "shippingbox"
        case .nodeModules: return "hexagon"
        case .swiftBuild: return "swift"
        case .gradle: return "elephant"
        case .homebrewCache: return "mug"
        case .safariCache: return "safari"
        case .chromeCache: return "globe"
        case .firefoxCache: return "flame"
        case .oldDownloads: return "arrow.down.circle"
        case .mailDownloads: return "envelope"
        case .dsStore: return "eye.slash"
        }
    }

    var group: CategoryGroup {
        switch self {
        case .appCaches, .logs, .tempFiles, .trash: return .system
        case .xcodeDerivedData, .xcodeDeviceSupport, .xcodeSimulators, .xcodeArchives: return .xcode
        case .nodeModules, .swiftBuild, .gradle, .homebrewCache: return .developer
        case .safariCache, .chromeCache, .firefoxCache: return .browsers
        case .oldDownloads, .mailDownloads: return .downloads
        case .dsStore: return .metadata
        }
    }

    var isSafeForQuickClean: Bool {
        switch self {
        case .appCaches, .logs, .tempFiles, .trash, .xcodeDerivedData,
             .homebrewCache, .safariCache, .chromeCache, .firefoxCache, .dsStore:
            return true
        case .xcodeDeviceSupport, .xcodeSimulators, .xcodeArchives,
             .nodeModules, .swiftBuild, .gradle, .oldDownloads, .mailDownloads:
            return false
        }
    }

    /// Roots scanned by namedFolders / filesNamed rules. Documents and Desktop are
    /// deliberately excluded (denylisted).
    private static var searchRoots: [URL] {
        ["Developer", "Projects", "repos", "src", "code", "Sites"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var rule: ScanRule {
        switch self {
        case .appCaches:
            return .directoryContents(paths: [
                Self.library("Caches"),
                URL(fileURLWithPath: "/Library/Caches"),
            ])
        case .logs:
            return .directoryContents(paths: [
                Self.library("Logs"),
                URL(fileURLWithPath: "/Library/Logs"),
                URL(fileURLWithPath: "/private/var/log"),
            ])
        case .tempFiles:
            return .directoryContents(paths: [
                URL(fileURLWithPath: NSTemporaryDirectory()),
                URL(fileURLWithPath: "/private/tmp"),
            ])
        case .trash:
            return .directoryContents(paths: [Self.home.appendingPathComponent(".Trash")])
        case .xcodeDerivedData:
            return .directoryContents(paths: [Self.library("Developer/Xcode/DerivedData")])
        case .xcodeDeviceSupport:
            return .directoryContents(paths: [
                Self.library("Developer/Xcode/iOS DeviceSupport"),
                Self.library("Developer/Xcode/watchOS DeviceSupport"),
                Self.library("Developer/Xcode/tvOS DeviceSupport"),
            ])
        case .xcodeSimulators:
            return .directories(paths: simulatorDeviceDirs())
        case .xcodeArchives:
            return .directoryContents(paths: [Self.library("Developer/Xcode/Archives")])
        case .nodeModules:
            return .namedFolders(name: "node_modules", roots: Self.searchRoots, maxDepth: 4)
        case .swiftBuild:
            return .namedFolders(name: ".build", roots: Self.searchRoots, maxDepth: 4)
        case .gradle:
            return .directories(paths: [Self.home.appendingPathComponent(".gradle/caches")])
        case .homebrewCache:
            return .command(
                executableCandidates: [
                    URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
                    URL(fileURLWithPath: "/usr/local/bin/brew"),
                ],
                arguments: ["--cache"],
                fallback: Self.library("Caches/Homebrew")
            )
        case .safariCache:
            return .directoryContents(paths: [
                Self.library("Caches/com.apple.Safari"),
                Self.library("Containers/com.apple.Safari/Data/Library/Caches"),
            ])
        case .chromeCache:
            return .directoryContents(paths: [
                Self.library("Caches/Google/Chrome"),
                Self.library("Application Support/Google/Chrome/Default/Cache"),
            ])
        case .firefoxCache:
            let profilesDir = Self.library("Caches/Firefox/Profiles")
            let profiles = (try? FileManager.default.contentsOfDirectory(
                at: profilesDir, includingPropertiesForKeys: nil)) ?? []
            return .directoryContents(paths: profiles.isEmpty ? [profilesDir] : profiles)
        case .oldDownloads:
            return .olderThan(days: 30, path: Self.home.appendingPathComponent("Downloads"))
        case .mailDownloads:
            return .directoryContents(paths: [
                Self.library("Containers/com.apple.mail/Data/Library/Mail Downloads"),
                Self.library("Mail Downloads"),
            ])
        case .dsStore:
            return .filesNamed(
                names: [".DS_Store", "Thumbs.db"],
                roots: Self.searchRoots + [Self.home],
                maxDepth: 4)
        }
    }

    /// Each simulator device dir is one item; name is resolved from device.plist.
    private func simulatorDeviceDirs() -> [URL] {
        let devicesDir = Self.library("Developer/CoreSimulator/Devices")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: devicesDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    /// Friendly label for simulator device directories.
    static func simulatorDeviceName(for url: URL) -> String? {
        let plist = url.appendingPathComponent("device.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = dict["name"] as? String else { return nil }
        return name
    }
}
