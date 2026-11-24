import Foundation

enum SourceFilesError: Error, Equatable {

    case cannotList(String)
}

enum SourceFiles {

    /// Directories that hold no app code: build output, dependency checkouts, and test targets
    /// (any directory whose name ends in `Tests`).
    static let skippedDirectories: Set<String> = [".build", ".git", ".swiftpm", "Carthage", "DerivedData", "Pods"]

    /// Every `.swift` file under `directories`, sorted, without the ones in skipped directories or
    /// whose path contains one of `excludes`.
    /// A directory that cannot be listed fails the search: skipped, its reducers would silently
    /// vanish from the map.
    static func find(
        in directories: [String],
        excluding excludes: [String] = [],
        fileManager: FileManager = .default
    ) throws -> [String] {
        var files: Set<String> = []
        for directory in directories {
            guard let enumerator = fileManager.enumerator(atPath: directory) else { throw SourceFilesError.cannotList(directory) }

            for case let path as String in enumerator {
                let name = path.split(separator: "/").last.map(String.init) ?? path
                if skippedDirectories.contains(name) || name.hasSuffix("Tests") {
                    enumerator.skipDescendants()
                    continue
                }
                let file = "\(directory)/\(path)"
                if path.hasSuffix(".swift"), !excludes.contains(where: file.contains) { files.insert(file) }
            }
        }
        return files.sorted()
    }
}
