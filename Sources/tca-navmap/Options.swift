import Foundation

/// The command line, parsed. Paths are absolute.
struct Options: Equatable {

    /// The reducer at the top of the app.
    var appRoot: String
    /// The reducer to map, when it is not the whole app.
    var area: String?
    /// File paths in a map are written relative to this directory.
    var base: String
    var sources: [String]
    /// A file whose path contains one of these is skipped.
    var excludes: [String] = []
    /// Directories whose reducers are expanded; nil leaves the choice to the root being mapped.
    var boundaries: [String]?
    var ignoredReducers: Set<String> = []
    var conditionModifiers: Set<String> = ["if"]
    var screenNameModifiers: Set<String> = []
    var outDir: String

    /// The reducer the map is drawn from.
    var root: String { area ?? appRoot }

    var configuration: Configuration {
        Configuration(
            appRoot: appRoot,
            ignoredReducers: ignoredReducers,
            conditionModifiers: conditionModifiers,
            screenNameModifiers: screenNameModifiers
        )
    }

    static let usage = """
    usage: tca-navmap <AppRoot> [options]

      <AppRoot>                          the @Reducer at the top of the app
      --area <Reducer>                   map one area: only reducers under its directory are expanded
      --sources <dir>[,<dir>…]           directories to read (default: the current directory)
      --exclude <text>[,<text>…]         skip files whose path contains any of these
      --boundary <dir>[,<dir>…]          directories whose reducers are expanded, instead of the default
      --ignore <Reducer>[,<Reducer>…]    reducers that are not a place a user goes, such as a debug launcher
      --condition-modifier <name>[,…]    modifiers that apply their content conditionally (default: if)
      --screen-name-modifier <name>[,…]  modifiers that name a screen with a string literal
      --out <dir>                        where <Root>.md and <Root>.json are written (default: navigation-map)
      --help                             show this

    """
}

enum OptionsError: Error, Equatable {

    case help
    case invalid(String)
}

extension Options {

    /// Parses `arguments` (without the executable's name). Relative paths resolve against `directory`.
    init(arguments: [String], currentDirectory directory: String) throws {
        var remaining = arguments
        if remaining.contains("--help") || remaining.contains("-h") { throw OptionsError.help }

        func value(_ name: String) throws -> String? {
            guard let position = remaining.firstIndex(of: name) else { return nil }
            guard position + 1 < remaining.count, !remaining[position + 1].hasPrefix("--") else {
                throw OptionsError.invalid("\(name) needs a value")
            }

            let value = remaining[position + 1]
            remaining.removeSubrange(position...position + 1)
            return value
        }
        func list(_ name: String) throws -> [String]? {
            try value(name)?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        func absolute(_ path: String) -> String {
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: directory).appendingPathComponent(path)
            return url.standardizedFileURL.path
        }

        let area = try value("--area")
        let sources = try list("--sources")
        let excludes = try list("--exclude")
        let boundaries = try list("--boundary")
        let ignored = try list("--ignore")
        let conditions = try list("--condition-modifier")
        let screenNames = try list("--screen-name-modifier")
        let out = try value("--out")

        if let unknown = remaining.first(where: { $0.hasPrefix("-") }) { throw OptionsError.invalid("unknown option \(unknown)") }
        guard let appRoot = remaining.first else { throw OptionsError.invalid("name the reducer at the top of the app") }
        guard remaining.count == 1 else { throw OptionsError.invalid("unexpected argument \(remaining[1])") }

        self.init(
            appRoot: appRoot,
            area: area == appRoot ? nil : area,
            base: absolute("."),
            sources: (sources ?? ["."]).map(absolute),
            excludes: excludes ?? [],
            boundaries: boundaries.map { $0.map(absolute) },
            ignoredReducers: Set(ignored ?? []),
            conditionModifiers: Set(conditions ?? ["if"]),
            screenNameModifiers: Set(screenNames ?? []),
            outDir: absolute(out ?? "navigation-map")
        )
    }
}
