import Testing
@testable import tca_navmap

@Suite("What the configuration changes, and the Markdown rendering")
struct ConfigurationTests {

    @Test
    func aConditionalModifierAroundAPresentationIsRecordedForBothBranches() throws {
        let destinations = try #require(map().features.first { $0.name == "Home" }).destinations

        #expect(destinations.first { $0.caseName == "detail" }?.presentedAs == [PresentedAs(style: "sheet", condition: "isCompact")])
        #expect(destinations.first { $0.caseName == "settings" }?.presentedAs == [PresentedAs(style: "popover", condition: "!(isCompact)")])
    }

    @Test
    func aConditionalModifierThatIsNotConfiguredRecordsNoCondition() throws {
        let destinations = try #require(map(Configuration(appRoot: "Home", conditionModifiers: [])).features.first { $0.name == "Home" }).destinations

        #expect(destinations.first { $0.caseName == "detail" }?.presentedAs == [PresentedAs(style: "sheet", condition: nil)])
    }

    @Test
    func screenNamesAreReadOnlyFromConfiguredModifiers() throws {
        #expect(try #require(map().features.first { $0.name == "Home" }).screenNames.isEmpty)

        let named = map(Configuration(appRoot: "Home", screenNameModifiers: ["trackScreen"]))
        #expect(try #require(named.features.first { $0.name == "Home" }).screenNames == ["Home"])
    }

    @Test
    func aControlIsTitledByAConfiguredTitleLabelAndNotByAConfiguredIconView() {
        let button = "Button {\n            store.send(.open)\n        } label: {\n            Text(\"Open\")\n        }"
        let card = #"Card(icon: Glyph("chevron"), badge: "New", heading: "Open detail") { store.send(.open) }"#
        let source = homeSource.replacingOccurrences(of: button, with: card)
        let markdown = { (configuration: Configuration) in
            GraphBuilder(sources: [(file: "/repo/App/Home.swift", text: source)], configuration: configuration)
                .build(root: "Home", boundaries: [], regenerate: "tca-navmap Home", relativeTo: "/repo").markdown
        }

        #expect(source.contains(card))
        #expect(markdown(Configuration(appRoot: "Home")).contains(#"via `.open` ← Card "chevron""#))
        #expect(markdown(Configuration(appRoot: "Home", iconViews: ["Glyph"])).contains(#"via `.open` ← Card "New""#))
        #expect(markdown(Configuration(appRoot: "Home", titleLabels: ["heading"])).contains(#"via `.open` ← Card "Open detail""#))
    }

    @Test
    func aStoreCreatedForTheAppRootOrAnIgnoredReducerIsNotAnotherRoot() {
        #expect(map().otherRoots == ["Playground"])
        #expect(map(Configuration(appRoot: "Home", ignoredReducers: ["Playground"])).otherRoots.isEmpty)
    }

    @Test
    func markdownListsTheTreeTheTableAndWhatNothingReaches() {
        let markdown = map(Configuration(appRoot: "Home", screenNameModifiers: ["trackScreen"])).markdown

        #expect(markdown.hasPrefix("# Navigation map: Home\n"))
        #expect(markdown.contains("Regenerate: `tca-navmap Home`"))
        #expect(markdown.contains("  - `destination.detail` → **Detail** · `sheet` when `isCompact` · via `.open` ← Button \"Open\""))
        #expect(markdown.contains("| `destination.settings` | Settings | `popover` when `!(isCompact)` | — | — |"))
        #expect(markdown.contains("- Screen names: Home"))
        #expect(markdown.contains("## Not reachable from the app"))
        #expect(markdown.contains("- **Orphan** (`App/Home.swift`)"))
    }

    // MARK: - Private

    @Test
    func aReducerDeclaredTwiceAndAnAmbiguousChildTypeAreWarnedAbout() {
        let builder = GraphBuilder(sources: [
            (file: "/repo/A/Home.swift", text: "@Reducer struct Home {}\n@Reducer struct A { @Reducer struct Detail {} }"),
            (file: "/repo/B/Home.swift", text: "@Reducer struct Home {}\n@Reducer struct B { @Reducer struct Detail {} }"),
            (file: "/repo/C/List.swift", text: """
            @Reducer
            struct List {
                @ObservableState
                struct State { @Presents var detail: Detail.State? }
            }
            """)
        ], configuration: Configuration(appRoot: "Home"))

        #expect(builder.warnings(relativeTo: "/repo") == [
            "Detail in List could be A.Detail or B.Detail; what it opens is not mapped",
            "Home is declared as a reducer in A/Home.swift and B/Home.swift; only the last one is mapped"
        ])
        #expect(GraphBuilder(sources: [(file: "/repo/App/Home.swift", text: homeSource)], configuration: Configuration(appRoot: "Home"))
            .warnings(relativeTo: "/repo").isEmpty)
    }

    private func map(_ configuration: Configuration = Configuration(appRoot: "Home")) -> NavigationMap {
        GraphBuilder(sources: [(file: "/repo/App/Home.swift", text: homeSource)], configuration: configuration)
            .build(root: "Home", boundaries: [], regenerate: "tca-navmap Home", relativeTo: "/repo")
    }
}

private let homeSource = #"""
@Reducer
struct Home {
    @ObservableState
    struct State {
        @Presents var destination: Destination.State?
    }
    @Reducer
    enum Destination {
        case detail(Detail)
        case settings(Settings)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .open:
                state.destination = .detail(.init())
                return .none
            }
        }
    }
}

@Reducer
struct Detail {
    @ObservableState
    struct State {}
}

@Reducer
struct Settings {
    @ObservableState
    struct State {}
}

@Reducer
struct Orphan {
    @ObservableState
    struct State {}
}

@Reducer
struct Playground {
    @ObservableState
    struct State {}
}

struct HomeView: View {
    @Bindable var store: StoreOf<Home>
    var body: some View {
        Button {
            store.send(.open)
        } label: {
            Text("Open")
        }.trackScreen("Home")
            .if(isCompact) { view in
                view.sheet(item: $store.scope(state: \.$destination, action: \.destination).detail) { DetailView(store: $0) }
            } else: { view in
                view.popover(item: $store.scope(state: \.$destination, action: \.destination).settings) { SettingsView(store: $0) }
            }
    }
}

@main
struct DemoApp: App {
    let store = Store(initialState: Home.State()) { Home() }
    let playground = Store(initialState: Playground.State()) { Playground() }
    var body: some Scene {
        WindowGroup { HomeView(store: store) }
    }
}
"""#
