import Foundation

extension URL {
    /// Absolute path with the home directory abbreviated to `~`, for display.
    ///
    /// Paths are resolved at runtime, so the home directory part is always
    /// the current account's; showing it in full just adds noise. The check
    /// keeps the separator so that `/Users/ice2` is not abbreviated to
    /// `~2`, which would happen with a plain prefix comparison.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = self.path
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
