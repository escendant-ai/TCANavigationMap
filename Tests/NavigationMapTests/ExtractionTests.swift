import Testing
@testable import tca_navmap

@Suite("Extraction from TCA source")
struct ExtractionTests {

    @Test
    func destinationCarriesItsPresentationActionAndControl() throws {
        let child = try #require(map.features.first { $0.name == "Child" })
        let detail = try #require(child.destinations.first { $0.caseName == "detail" })

        #expect(detail.feature == "Detail")
        #expect(detail.presentedAs.contains(PresentedAs(style: "sheet", condition: nil)))
        #expect(detail.triggers.map(\.action) == ["open"])
        #expect(detail.triggers.first?.controls.map(\.control) == ["Button \"Open\""])
    }

    @Test
    func parentDrawnInlineDestinationIsCreditedToTheSlotOwner() throws {
        let child = try #require(map.features.first { $0.name == "Child" })
        let detail = try #require(child.destinations.first { $0.caseName == "detail" })

        #expect(detail.presentedAs.contains(PresentedAs(style: "inline in Root", condition: nil)))
    }

    @Test
    func entryPathRunsThroughTheEmbeddingParent() {
        #expect(map.entryPath.map(\.feature) == ["Root", "Child"])
        #expect(map.entryPath.last?.via == "embeds child")
    }

    @Test
    func unsentActionHasNoControl() throws {
        let child = try #require(map.features.first { $0.name == "Child" })
        let remove = try #require(child.destinations.first { $0.caseName == "remove" })

        #expect(remove.triggers.map(\.action) == ["remove"])
        #expect(remove.triggers.first?.controls.isEmpty == true)
    }

    @Test
    func outOfBoundaryChildIsExternalAndNotExpanded() throws {
        // Area maps list an out-of-boundary child as an edge (`isExternal`) and do not walk into it.
        let builder = GraphBuilder(sources: [
            (file: "/repo/App/Root.swift", text: rootSource),
            (file: "/repo/App/Child/Child.swift", text: childWithOutsideSource),
            (file: "/repo/App/Outside/Outside.swift", text: outsideSource)
        ], configuration: Configuration(appRoot: "Root"))
        let area = builder.build(
            root: "Child",
            boundaries: ["/repo/App/Child"],
            regenerate: "test",
            relativeTo: "/repo"
        )

        let outside = try #require(area.features.first { $0.name == "Outside" })
        #expect(outside.isExternal == true)
        #expect(area.features.contains { $0.name == "NestedOutside" } == false)
        #expect(area.unreachable.isEmpty)
    }

    // MARK: - Private

    private let map: NavigationMap = {
        let builder = GraphBuilder(sources: [
            (file: "/repo/App/Root.swift", text: rootSource),
            (file: "/repo/App/Child/Child.swift", text: childSource)
        ], configuration: Configuration(appRoot: "Root"))
        return builder.build(root: "Child", boundaries: ["/repo/App/Child"], regenerate: "test", relativeTo: "/repo")
    }()
}

private let rootSource = #"""
@Reducer
struct Root {
    @ObservableState
    struct State {
        var child = Child.State()
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.child, action: \.child) { Child() }
    }
}

struct RootView: View {
    let store: StoreOf<Root>
    var body: some View {
        if let detailStore = store.scope(state: \.child.destination?.detail, action: \.child.destination.detail) {
            DetailView(store: detailStore)
        }
    }
}
"""#

private let childSource = #"""
@Reducer
struct Child {
    @ObservableState
    struct State {
        @Presents var destination: Destination.State?
    }
    @Reducer
    enum Destination {
        case detail(Detail)
        case remove(Detail)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .open:
                state.destination = .detail(.init())
                return .none
            case .remove:
                state.destination = .remove(.init())
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

struct ChildView: View {
    @Bindable var store: StoreOf<Child>
    var body: some View {
        Button {
            store.send(.open)
        } label: {
            Text("Open")
        }.sheet(item: $store.scope(state: \.$destination, action: \.destination).detail) { DetailView(store: $0) }
    }
}
"""#

private let childWithOutsideSource = #"""
@Reducer
struct Child {
    @ObservableState
    struct State {
        @Presents var destination: Destination.State?
    }
    @Reducer
    enum Destination {
        case detail(Detail)
        case remove(Detail)
        case outside(Outside)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .open:
                state.destination = .detail(.init())
                return .none
            case .remove:
                state.destination = .remove(.init())
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

struct ChildView: View {
    @Bindable var store: StoreOf<Child>
    var body: some View {
        Button {
            store.send(.open)
        } label: {
            Text("Open")
        }.sheet(item: $store.scope(state: \.$destination, action: \.destination).detail) { DetailView(store: $0) }
    }
}
"""#

private let outsideSource = #"""
@Reducer
struct Outside {
    @ObservableState
    struct State {
        var nested = NestedOutside.State()
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.nested, action: \.nested) { NestedOutside() }
    }
}

@Reducer
struct NestedOutside {
    @ObservableState
    struct State {}
}
"""#
