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
    ///   {dir}   - working directory: the selected folder itself, or the
    ///             folder containing the selection, shell-quoted
    ///   {parent} - folder containing the first selected path, shell-quoted
    ///   {input} - text the user typed into the prompt, shell-quoted
    var script: String = ""
    /// Whether the command is shown at all.
    var enabled: Bool = true
    /// When set, the app asks for one line of text before running the
    /// command and exposes it as {input}. Empty means "run immediately".
    var promptTitle: String?
    /// Placeholder text shown in the prompt's text field.
    var promptPlaceholder: String?

    /// True when running this command requires user input first.
    var needsInput: Bool {
        guard let promptTitle else { return false }
        return !promptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A command is only usable when both name and script are non-blank.
    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
