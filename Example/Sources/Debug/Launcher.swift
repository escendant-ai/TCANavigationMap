import ComposableArchitecture

/// A debug-only screen that opens features on their own. Not a place a user goes, so the map is
/// generated with `--ignore Launcher`.
@Reducer
struct Launcher {

    @ObservableState
    struct State {
        var playground = Playground.State()
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.playground, action: \.playground) { Playground() }
    }
}

/// Reached only through the launcher, so the map lists it as not reachable from the app.
@Reducer
struct Playground {

    @ObservableState
    struct State {}
}
