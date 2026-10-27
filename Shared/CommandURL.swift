import Foundation

/// Wire format used to hand a command invocation from the sandboxed
/// Finder Sync extension to the unsandboxed main app.
///
/// `quicklet://run?id=<UUID>&path=<path>&path=<path>...`
enum CommandURL {
    static let scheme = "quicklet"
    static let host = "run"

    static func make(commandID: UUID, paths: [String]) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var items = [URLQueryItem(name: "id", value: commandID.uuidString)]
        items.append(contentsOf: paths.map { URLQueryItem(name: "path", value: $0) })
        components.queryItems = items
        return components.url
    }

    static func parse(_ url: URL) -> (commandID: UUID, paths: [String])? {
        guard url.scheme == scheme,
              url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idValue)
        else { return nil }

        let paths = (components.queryItems ?? [])
            .filter { $0.name == "path" }
            .compactMap(\.value)
        return (id, paths)
    }
}
