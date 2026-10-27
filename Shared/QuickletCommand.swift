import Foundation

/// A user-defined Finder context menu command.
struct QuickletCommand: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Display name shown in the Finder context menu.
    var name: String = ""
    /// SF Symbol name used as the menu item icon.
    var icon: String = "terminal"
    /// Shell script template. Supported placeholders:
    ///   {paths} - all selected paths, shell-quoted, space separated
    ///   {path}  - first selected path, shell-quoted
    ///   {dir}   - parent directory of the first selected path, shell-quoted
    var script: String = ""
    /// Whether the command is shown at all.
    var enabled: Bool = true

    /// A command is only usable when both name and script are non-blank.
    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
