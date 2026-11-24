import Foundation
import Testing
@testable import tca_navmap

@Suite("Command line and source discovery")
struct OptionsTests {

    @Test
    func theAppRootAloneMapsTheWholeAppFromTheCurrentDirectory() throws {
        let options = try Options(arguments: ["AppFeature"], currentDirectory: "/work/app")

        #expect(options.appRoot == "AppFeature")
        #expect(options.root == "AppFeature")
        #expect(options.area == nil)
        #expect(options.base == "/work/app")
        #expect(options.sources == ["/work/app"])
        #expect(options.boundaries == nil)
        #expect(options.outDir == "/work/app/navigation-map")
        #expect(options.conditionModifiers == ["if"])
    }

    @Test
    func listsSplitOnCommasAndRelativePathsResolveAgainstTheCurrentDirectory() throws {
        let options = try Options(
            arguments: [
                "--area", "Contacts", "AppFeature", "--sources", "App,Packages/Features", "--boundary", "/abs/Contacts,App/Shared",
                "--ignore", "Launcher, Playground", "--screen-name-modifier", "trackScreen", "--condition-modifier", "when",
                "--exclude", "Generated,/Mocks/", "--out", "../maps"
            ],
            currentDirectory: "/work/app"
        )

        #expect(options.root == "Contacts")
        #expect(options.sources == ["/work/app/App", "/work/app/Packages/Features"])
        #expect(options.boundaries == ["/abs/Contacts", "/work/app/App/Shared"])
        #expect(options.ignoredReducers == ["Launcher", "Playground"])
        #expect(options.configuration.screenNameModifiers == ["trackScreen"])
        #expect(options.configuration.conditionModifiers == ["when"])
        #expect(options.excludes == ["Generated", "/Mocks/"])
        #expect(options.outDir == "/work/maps")
    }

    @Test
    func anAreaThatIsTheAppRootIsTheWholeApp() throws {
        #expect(try Options(arguments: ["AppFeature", "--area", "AppFeature"], currentDirectory: "/work").area == nil)
    }

    @Test
    func badCommandLinesAreRejected() {
        #expect(throws: OptionsError.help) { try Options(arguments: ["AppFeature", "--help"], currentDirectory: "/") }
        #expect(throws: OptionsError.invalid("name the reducer at the top of the app")) { try Options(arguments: [], currentDirectory: "/") }
        #expect(throws: OptionsError.invalid("unknown option --nope")) { try Options(arguments: ["A", "--nope"], currentDirectory: "/") }
        #expect(throws: OptionsError.invalid("unexpected argument B")) { try Options(arguments: ["A", "B"], currentDirectory: "/") }
        #expect(throws: OptionsError.invalid("--out needs a value")) { try Options(arguments: ["A", "--out"], currentDirectory: "/") }
        #expect(throws: OptionsError.invalid("--area needs a value")) { try Options(arguments: ["A", "--area", "--out", "x"], currentDirectory: "/") }
    }

    @Test
    func sourceDiscoverySkipsBuildOutputTestTargetsAndExcludedPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tca-navmap-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let kept = ["App/Root.swift", "App/Contacts/Contacts.swift", "Packages/Core/Sources/Core/Core.swift"]
        let skipped = [
            "App/Generated/API.swift", "AppTests/RootTests.swift", "Packages/Core/Tests/CoreTests/CoreTests.swift",
            ".build/checkouts/Dep/Dep.swift", "Pods/Lib/Lib.swift", "App/README.md"
        ]
        for file in kept + skipped {
            let path = "\(root)/\(file)"
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try "".write(toFile: path, atomically: true, encoding: .utf8)
        }

        let found = try SourceFiles.find(in: [root, "\(root)/App"], excluding: ["/Generated/"])

        // A directory listed twice, or inside another, yields each file once.
        #expect(found == kept.map { "\(root)/\($0)" }.sorted())
    }

    @Test
    func aDirectoryThatCannotBeListedFailsTheSearch() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("tca-navmap-\(UUID().uuidString)").path

        #expect(throws: SourceFilesError.cannotList(missing)) { try SourceFiles.find(in: [missing]) }
    }
}
