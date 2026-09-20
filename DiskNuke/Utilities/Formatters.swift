import Foundation

enum Formatters {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = true
        return f
    }()

    static func formatBytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func formatRelative(_ date: Date?) -> String {
        guard let date else { return "—" }
        if abs(date.timeIntervalSinceNow) < 5 { return "just now" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return formatBytes(bytes)
    }
}
