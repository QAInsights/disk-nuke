import Foundation

enum DebugSupport {
    /// Extra scan root provided via `-extraScanRoot /path` launch argument or
    /// `DISK_NUKE_EXTRA_ROOT` environment variable. Consumed by AppSettings.
    static var extraScanRoot: String? {
        UserDefaults.standard.string(forKey: "extraScanRoot")
            ?? ProcessInfo.processInfo.environment["DISK_NUKE_EXTRA_ROOT"]
    }
}
