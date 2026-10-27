import Foundation

/// Arranges a flat command list into the menu hierarchy shown in Finder.
///
/// Commands without a group stay at the first level of the context menu;
/// everything else nests below the fixed root menu. Depth is capped so a
/// hand-edited config cannot produce menus deeper than the UI allows.
struct MenuTree {
    /// One menu level: the commands that belong to it plus its submenus.
    struct Level {
        var commands: [QuickletCommand] = []
        var children: [Child] = []
    }

    struct Child {
        let name: String
        var level: Level
    }

    /// First-level commands and the tree below the Quicklet menu.
    struct Result {
        var topLevel: [QuickletCommand] = []
        var root = Level()
    }

    static func build(
        from commands: [QuickletCommand],
        maxDepth: Int = QuickletCommand.maxGroupDepth
    ) -> Result {
        var result = Result()
        for command in commands {
            let path = Array(command.group.prefix(maxDepth))
            if path.isEmpty {
                result.topLevel.append(command)
            } else {
                insert(command: command, path: path[...], into: &result.root)
            }
        }
        return result
    }

    private static func insert(
        command: QuickletCommand,
        path: ArraySlice<String>,
        into level: inout Level
    ) {
        guard let name = path.first else {
            level.commands.append(command)
            return
        }
        let remainder = path.dropFirst()
        if let index = level.children.firstIndex(where: { $0.name == name }) {
            insert(command: command, path: remainder, into: &level.children[index].level)
        } else {
            var child = Level()
            insert(command: command, path: remainder, into: &child)
            level.children.append(Child(name: name, level: child))
        }
    }

    /// Compact text form used in the diagnostics log, e.g.
    /// `open in terminal, Quicklet{dev{git{commit}}}`.
    static func describe(_ level: Level) -> String {
        var parts = level.commands.map(\.name)
        parts += level.children.map { "\($0.name){\(describe($0.level))}" }
        return parts.joined(separator: ", ")
    }
}
