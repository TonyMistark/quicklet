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
    /// Menu placement. Empty means the item sits at the first level of the
    /// Finder context menu; otherwise the names are nested submenus below
    /// the fixed "Quicklet" menu, at most `maxGroupDepth` levels deep.
    var group: [String] = []

    /// The "Quicklet" menu is fixed: commands can be organised underneath it
    /// but the entry itself cannot be renamed or removed.
    static let rootMenuTitle = "Quicklet"
    /// Depth limit below the root menu for now.
    static let maxGroupDepth = 2

    /// True when running this command requires user input first.
    var needsInput: Bool {
        guard let promptTitle else { return false }
        return !promptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the command lives under the Quicklet menu instead of the
    /// context menu's first level.
    var isGrouped: Bool { !group.isEmpty }

    /// Human readable placement, for the settings window.
    var menuPath: String {
        isGrouped ? ([Self.rootMenuTitle] + group).joined(separator: " › ") : "右键第一层"
    }

    /// A command is only usable when both name and script are non-blank.
    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension QuickletCommand {
    private enum CodingKeys: String, CodingKey {
        case id, name, icon, script, enabled, promptTitle, promptPlaceholder, group
    }

    // Custom decoding rather than the synthesised one: configs written by
    // older versions have no `group` key, and a synthesised init would fail
    // on the whole file instead of defaulting that one field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "terminal"
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        promptTitle = try container.decodeIfPresent(String.self, forKey: .promptTitle)
        promptPlaceholder = try container.decodeIfPresent(String.self, forKey: .promptPlaceholder)
        group = try container.decodeIfPresent([String].self, forKey: .group) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(script, forKey: .script)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(promptTitle, forKey: .promptTitle)
        try container.encodeIfPresent(promptPlaceholder, forKey: .promptPlaceholder)
        try container.encode(group, forKey: .group)
    }
}
