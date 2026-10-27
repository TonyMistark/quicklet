import Foundation

/// Loose semantic version, tolerant of the tags people actually write:
/// `v1.2.3`, `1.2`, `1.2.3-beta.2`, `1.2.3+build.7`.
///
/// Comparison follows semver's intent with the smallest useful
/// implementation: numeric segments compare one by one (missing segments
/// count as 0) and a prerelease sorts below the same core version
/// (`1.2.3-beta` < `1.2.3`).
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let core: [Int]
    let prerelease: [String]

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        // Build metadata does not participate in comparison.
        if let plus = trimmed.firstIndex(of: "+") {
            trimmed = String(trimmed[..<plus])
        }
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".").map { Int($0) }
        // A single non-numeric segment invalidates the whole string: better
        // to miss an update than to claim one that is not there.
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        core = numbers.compactMap { $0 }
        if parts.count > 1 {
            let identifiers = parts[1].split(separator: ".").map(String.init)
            guard !identifiers.isEmpty else { return nil }
            prerelease = identifiers
        } else {
            prerelease = []
        }
    }

    var description: String {
        let base = core.map(String.init).joined(separator: ".")
        return prerelease.isEmpty ? base : "\(base)-\(prerelease.joined(separator: "."))"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.core.count, rhs.core.count)
        for index in 0..<count {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right { return left < right }
        }
        // Same core: the one with a prerelease tag is the older build.
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (_?, nil):
                return true      // numeric identifiers sort before alphanumeric
            case (nil, _?):
                return false
            default:
                return left < right
            }
        }
        // Shared prefix: fewer identifiers is older (`1.2.3-beta` < `1.2.3-beta.1`).
        return lhs.prerelease.count < rhs.prerelease.count
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Facts about the running copy, used by the about page and the log header.
enum AppInfo {
    static var shortVersion: String {
        bundleString("CFBundleShortVersionString") ?? "0.0.0"
    }

    static var build: String {
        bundleString("CFBundleVersion") ?? "0"
    }

    /// Injected by scripts/build.sh before re-signing, so the about page can
    /// name the exact commit a build came from.
    static var commit: String? {
        guard let value = bundleString("QuickletGitCommit"), !value.isEmpty else { return nil }
        return value
    }

    static var buildDate: String? {
        bundleString("QuickletBuildDate")
    }

    static var bundlePath: String { Bundle.main.bundlePath }

    static var systemDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(architecture))"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "unknown"
        #endif
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
