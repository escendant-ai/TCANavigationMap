import Testing
@testable import tca_navmap

@Suite("Whole-app coverage and how a control reaches a destination")
struct WholeAppMapTests {

    @Test
    func anIgnoredReducerIsNotAnEntryPathAndItsOnlyChildIsUnreachable() {
        #expect(!Self.map.features.contains { $0.name == "Launcher" || $0.name == "Hidden" })
        #expect(Self.map.unreachable.map(\.name) == ["Hidden"])
    }

    @Test
    func aStoreTheAppCreatesIsAnotherRootAndAViewCreatedStoreIsAChild() throws {
        #expect(Self.map.otherRoots == ["Overlay"])
        #expect(Self.map.features.contains { $0.name == "Web" && $0.presentedBy == ["Root"] })
        let root = try #require(feature("Root"))
        #expect(root.embeds.map(\.feature) == ["Main", "Web"])
    }

    @Test
    func aListWhosePropertyIsNamedRowsIsEmbeddedOnce() throws {
        #expect(try #require(feature("Main")).embeds.map(\.feature) == ["Child", "Row"])
    }

    @Test
    func aControlReachesADestinationThroughAnArmThatReSendsIt() throws {
        let control = try #require(controls("Main", "destination", "detail", action: "openDetail").first)

        #expect(control.control == "Button \"Details\" in NavigationStack")
        #expect(control.chain == ["tapDetail"])
    }

    @Test
    func aChildsDelegateIsTracedToTheChildsControl() throws {
        let control = try #require(controls("Main", "destination", "picker", action: "child.delegate.showPicker").first)

        #expect(control.control == "Button \"Pick\"")
        #expect(control.reducer == "Child")
        #expect(control.chain == ["tapPicker"])
    }

    @Test
    func aChildsSendThatOpensAParentsDestinationIsNotAnOtherUIAction() throws {
        #expect(try #require(feature("Child")).otherUIActions.isEmpty)
        #expect(try #require(feature("Row")).otherUIActions.isEmpty)
    }

    @Test
    func aRowStoreSendIsTracedThroughTheList() throws {
        let control = try #require(controls("Main", "destination", "detail", action: "rows.element.delegate.open").first)

        #expect(control.control == "Button \"Row\" in ForEach")
        #expect(control.reducer == "Row")
    }

    @Test
    func anActionHandedToAViewHelperIsCreditedToTheHelpersCallSite() {
        #expect(controls("Main", "destination", "detail", action: "refresh").map(\.control) == ["menuItem \"Refresh\""])
    }

    @Test
    func anActionHandedToAViewAsAPropertyIsCreditedToTheViewsCallSite() {
        #expect(controls("Main", "destination", "picker", action: "finish").map(\.control) == ["ConfirmView \"Done\""])
    }

    @Test
    func aHelperSwitchExtendsThePathOnlyWhenTheArmHandsItTheSwitchedValue() throws {
        let destinations = try #require(feature("Main")).destinations
        let actions = destinations.flatMap(\.triggers).map(\.action)

        #expect(actions.contains("menu.showPicker"))
        #expect(actions.contains("onAppear"))
        #expect(!actions.contains("onAppear.showPicker"))
        #expect(actions.contains("refresh"))
        #expect(!actions.contains { $0.hasPrefix("refresh.") })
    }

    @Test
    func viewModifiersAndChildSlotKeyPathsArePresentations() throws {
        let main = try #require(feature("Main"))
        let detail = try #require(main.destinations.first { $0.caseName == "detail" })
        let picker = try #require(main.destinations.first { $0.caseName == "picker" })

        #expect(detail.presentedAs.contains(PresentedAs(style: "sheet", condition: nil)))
        #expect(picker.presentedAs.contains(PresentedAs(style: "popover in Root", condition: nil)))
    }

    @Test
    func aPlainArrayPathListsEachStepItsDestinationSwitchDraws() throws {
        let steps = try #require(feature("Main")).destinations.filter { $0.slot == "steps" }

        #expect(steps.map(\.caseName) == ["welcome", "signIn.initial", "signIn.code"])
        #expect(steps.map(\.type) == ["WelcomeView", "SignInView", "CodeView"])
        #expect(steps.first { $0.caseName == "signIn.initial" }?.triggers.map(\.action) == ["startSignIn"])
        #expect(steps.first { $0.caseName == "signIn.code" }?.triggers.map(\.action) == ["didSendCode"])
        #expect(steps.first { $0.caseName == "welcome" }?.triggers.isEmpty == true)
        #expect(steps.allSatisfy { $0.presentedAs == [PresentedAs(style: "NavigationStack push", condition: nil)] })
    }

    // MARK: - Private

    private static let map: NavigationMap = {
        let builder = GraphBuilder(sources: [
            (file: "/repo/App/Root.swift", text: rootSource),
            (file: "/repo/App/Main.swift", text: mainSource),
            (file: "/repo/App/Debug/Launcher.swift", text: launcherSource)
        ], configuration: Configuration(appRoot: "Root", ignoredReducers: ["Launcher"]))
        return builder.build(root: "Root", boundaries: [], regenerate: "test", relativeTo: "/repo")
    }()
}

private extension WholeAppMapTests {

    func feature(_ name: String) -> Feature? {
        Self.map.features.first { $0.name == name }
    }

    func controls(_ feature: String, _ slot: String, _ caseName: String, action: String) -> [UIControl] {
        self.feature(feature)?.destinations
            .first { $0.slot == slot && $0.caseName == caseName }?.triggers
            .first { $0.action == action }?.controls ?? []
    }
}

private let rootSource = #"""
@Reducer
struct Root {
    @ObservableState
    struct State {
        var main = Main.State()
        var launcher: Launcher.State?
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.main, action: \.main) { Main() }
        Reduce { state, action in .none }
            .ifLet(\.launcher, action: \.launcher) { Launcher() }
    }
}

@Reducer
struct Web {
    @ObservableState
    struct State {}
}

@Reducer
struct Overlay {
    @ObservableState
    struct State {}
}

struct RootView: View {
    @Bindable var store: StoreOf<Root>
    var body: some View {
        MainView(store: store.scope(state: \.main, action: \.main))
            .popover(item: $store.scope(state: \.main.$destination, action: \.main.destination).picker) { PickerView(store: $0) }
        WebView(store: Store(initialState: .init()) { Web() })
    }
}

extension AppDelegate {
    func presentOverlay() {
        window.rootView = OverlayView(store: .init(initialState: .init(), reducer: { Overlay().logging() }))
    }
}

#Preview {
    RootView(store: Store(initialState: .init()) { Hidden() })
}
"""#

private let mainSource = #"""
@Reducer
struct Main {
    @ObservableState
    struct State {
        @Presents var destination: Destination.State?
        var steps: [Step] = []
        var rows = IdentifiedArrayOf<Row.State>()
        var child = Child.State()
        var mode = Mode.a
    }
    enum Step: Hashable {
        enum SignIn: Hashable {
            case initial
            case code
        }
        case welcome
        case signIn(SignIn)
    }
    @Reducer
    enum Destination {
        case detail(Detail)
        case picker(Picker)
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.child, action: \.child) { Child() }
        Reduce { state, action in
            switch action {
            case .openDetail:
                state.destination = .detail(.init())
                return .none
            case .tapDetail:
                return .send(.openDetail)
            case .menu(let item):
                return handleMenu(item, state: &state)
            case .onAppear:
                return handleMenu(state.defaultItem, state: &state)
            case .refresh:
                return handleRefresh(state: &state)
            case .child(.delegate(.showPicker)):
                state.destination = .picker(.init())
                return .none
            case .startSignIn:
                state.steps = [.signIn(.initial)]
                return .none
            case .didSendCode:
                state.steps += [.signIn(.code)]
                return .none
            case .finish:
                state.destination = .picker(.init())
                return .none
            case .rows(.element(id: _, action: .delegate(.open))):
                state.destination = .detail(.init())
                return .none
            }
        }.forEach(\.rows, action: \.rows) { Row() }
    }
    func handleMenu(_ item: MenuItem, state: inout State) -> Effect<Action> {
        switch item {
        case .showPicker:
            state.destination = .picker(.init())
            return .none
        }
    }
    func handleRefresh(state: inout State) -> Effect<Action> {
        switch state.mode {
        case .a:
            state.destination = .detail(.init())
            return .none
        }
    }
}

@Reducer
struct Child {
    @ObservableState
    struct State {}
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .tapPicker:
                return .send(.delegate(.showPicker))
            }
        }
    }
}

@Reducer
struct Row {
    @ObservableState
    struct State {}
}

@Reducer
struct Detail {
    @ObservableState
    struct State {}
}

@Reducer
struct Picker {
    @ObservableState
    struct State {}
}

struct MainView: View {
    @Bindable var store: StoreOf<Main>
    var body: some View {
        NavigationStack(path: $store.steps) {
            Button {
                store.send(.tapDetail)
            } label: {
                Text("Details")
            }.navigationDestination(for: Main.Step.self) { step in
                switch step {
                case .welcome:
                    WelcomeView()
                case .signIn(.initial):
                    SignInView()
                case .signIn(.code):
                    CodeView()
                }
            }
        }.modifier(PresentationsModifier(store: store))
        menuItem(title: "Refresh", action: .refresh)
        ConfirmView(title: "Done", action: .finish, store: store)
        ForEach(store.scope(state: \.rows, action: \.rows)) { rowStore in
            Button {
                rowStore.send(.delegate(.open))
            } label: {
                Text("Row")
            }
        }
    }
    func menuItem(title: String, action: Main.Action) -> some View {
        Button {
            store.send(action)
        } label: {
            Text(title)
        }
    }
}

struct ConfirmView: View {
    let title: String
    let action: Main.Action
    let store: StoreOf<Main>
    var body: some View {
        Button {
            store.send(action)
        } label: {
            Text(title)
        }
    }
}

struct PresentationsModifier: ViewModifier {
    @Bindable var store: StoreOf<Main>
    func body(content: Content) -> some View {
        content.sheet(item: $store.scope(state: \.$destination, action: \.destination).detail) { DetailView(store: $0) }
    }
}

struct ChildView: View {
    let store: StoreOf<Child>
    var body: some View {
        Button {
            store.send(.tapPicker)
        } label: {
            Text("Pick")
        }
    }
}
"""#

private let launcherSource = #"""
@Reducer
struct Launcher {
    @ObservableState
    struct State {
        var hidden = Hidden.State()
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.hidden, action: \.hidden) { Hidden() }
    }
}

@Reducer
struct Hidden {
    @ObservableState
    struct State {}
}
"""#
