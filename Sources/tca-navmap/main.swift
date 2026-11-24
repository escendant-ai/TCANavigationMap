// tca-navmap: derives a navigation map from the source of an app built on The Composable Architecture.
//
//   tca-navmap <AppRoot> [--area <Reducer>] [--sources <dir>[,<dir>…]] [--out <dir>] …
//
// Writes <out>/<Root>.md and <Root>.json, where <Root> is the area if one is named and the app's
// root reducer otherwise. `tca-navmap --help` lists every option.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tca-navmap: \(message)\n".utf8))
    exit(2)
}

let options: Options
do {
    options = try Options(arguments: Array(CommandLine.arguments.dropFirst()), currentDirectory: FileManager.default.currentDirectoryPath)
} catch OptionsError.help {
    print(Options.usage, terminator: "")
    exit(0)
} catch OptionsError.invalid(let message) {
    FileHandle.standardError.write(Data("tca-navmap: \(message)\n\n\(Options.usage)".utf8))
    exit(2)
}

for directory in options.sources {
    var isDirectory: ObjCBool = false
    if !FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) || !isDirectory.boolValue {
        fail("no directory at \(directory)")
    }
}
let files: [String]
do {
    files = try SourceFiles.find(in: options.sources, excluding: options.excludes)
} catch {
    fail("cannot list \(options.sources.joined(separator: ", ")): \(error)")
}
if files.isEmpty { fail("no Swift files under \(options.sources.joined(separator: ", "))") }

// An unreadable file must fail the run: parsed as empty, its reducers would silently vanish from
// the map.
let sources = files.map { file -> (file: String, text: String) in
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { fail("cannot read \(file)") }

    return (file, text)
}
let builder = GraphBuilder(sources: sources, configuration: options.configuration)
let index = builder.index
let root = options.root

for name in [options.appRoot, root] where index.reducers[name] == nil {
    fail("no @Reducer named \(name)")
}

// Default boundary: the area's own directory; none for the whole app.
let rootDirectory = URL(fileURLWithPath: index.reducers[root]!.file).deletingLastPathComponent().path
let boundaries = options.boundaries ?? (options.area == nil ? [] : [rootDirectory])
let map = builder.build(
    root: root,
    boundaries: boundaries,
    regenerate: (["tca-navmap"] + CommandLine.arguments.dropFirst()).joined(separator: " "),
    relativeTo: options.base
)

for warning in builder.warnings(relativeTo: options.base) {
    FileHandle.standardError.write(Data("tca-navmap: warning: \(warning)\n".utf8))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
guard let json = String(bytes: try encoder.encode(map), encoding: .utf8) else { fail("failed to encode JSON as UTF-8") }

let outputs = ["\(options.outDir)/\(root).json": json + "\n", "\(options.outDir)/\(root).md": map.markdown]
try FileManager.default.createDirectory(atPath: options.outDir, withIntermediateDirectories: true)
for (path, contents) in outputs.sorted(by: { $0.key < $1.key }) {
    try contents.write(toFile: path, atomically: true, encoding: .utf8)
    print("wrote \(path.relative(to: options.base))")
}
print("\(map.features.count) features reachable from \(root) (\(files.count) files, \(index.reducers.count) reducers indexed)")
