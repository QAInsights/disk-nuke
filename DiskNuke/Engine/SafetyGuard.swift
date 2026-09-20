import Foundation

enum ProtectionReason: Equatable, CustomStringConvertible {
    case denylisted
    case systemPath
    case protectedRoot
    case insideAppBundle
    case userExcluded

    var description: String {
        switch self {
        case .denylisted: return "Path is on the built-in denylist"
        case .systemPath: return "System path"
        case .protectedRoot: return "Root directory itself is protected; only its children can be deleted"
        case .insideAppBundle: return "Inside an .app bundle"
        case .userExcluded: return "Excluded by user settings"
        }
    }
}

struct SafetyGuard {
    let userExclusions: [String]

    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    /// Exact-path denylist (standardized paths).
    private static var deniedRoots: Set<String> {
        let h = home
        return [
            h,
            "\(h)/Documents",
            "\(h)/Desktop",
            "\(h)/Pictures",
            "\(h)/Movies",
            "\(h)/Music",
            "\(h)/Library/Mobile Documents",
            "\(h)/Library/Keychains",
            "/System",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/private/etc",
            "/Applications",
        ]
    }

    /// /Library is protected except these subtrees.
    private static let libraryAllowPrefixes = ["/Library/Logs", "/Library/Caches"]

    /// Scan roots whose directory itself must never be deleted (only children).
    private static var protectedRoots: Set<String> {
        let h = home
        return [
            "\(h)/Library/Caches",
            "/Library/Caches",
            "\(h)/Library/Logs",
            "/Library/Logs",
            "/private/var/log",
            "/private/tmp",
            "\(h)/.Trash",
            "\(h)/Library/Developer/Xcode/DerivedData",
            "\(h)/Library/Developer/Xcode/Archives",
            "\(h)/Library/Developer/CoreSimulator/Devices",
            "\(h)/Library/Caches/Homebrew",
            "\(h)/Downloads",
        ]
    }

    /// Inside Caches/DerivedData roots, .app bundles may be deleted.
    private static var appBundleAllowPrefixes: [String] {
        let h = home
        return [
            "\(h)/Library/Caches",
            "/Library/Caches",
            "\(h)/Library/Developer/Xcode/DerivedData",
            "\(h)/Library/Containers/com.apple.Safari/Data/Library/Caches",
            "\(h)/Library/Caches/Google/Chrome",
        ]
    }

    init(userExclusions: [String] = []) {
        self.userExclusions = userExclusions
    }

    func isProtected(_ url: URL) -> ProtectionReason? {
        let path = url.standardizedFileURL.path

        for ex in userExclusions {
            let p = URL(fileURLWithPath: NSString(string: ex).expandingTildeInPath)
                .standardizedFileURL.path
            if path == p || path.hasPrefix(p + "/") { return .userExcluded }
        }

        if Self.deniedRoots.contains(path) { return .denylisted }
        for root in Self.deniedRoots where root.hasPrefix("/") && !root.hasPrefix(Self.home) {
            if path.hasPrefix(root + "/") { return .systemPath }
        }
        // Home-level denied dirs: anything *under* them is denied too.
        for root in Self.deniedRoots where root.hasPrefix(Self.home) && root != Self.home {
            if path.hasPrefix(root + "/") { return .denylisted }
        }

        if path.hasPrefix("/Library") {
            let allowed = Self.libraryAllowPrefixes.contains {
                path == $0 || path.hasPrefix($0 + "/")
            }
            if !allowed { return .systemPath }
        }

        if Self.protectedRoots.contains(path) { return .protectedRoot }

        if path.hasSuffix(".app") || path.contains(".app/") {
            let allowed = Self.appBundleAllowPrefixes.contains { path.hasPrefix($0 + "/") }
            if !allowed { return .insideAppBundle }
        }

        return nil
    }

    func isDeletable(_ url: URL) -> Bool { isProtected(url) == nil }
}
