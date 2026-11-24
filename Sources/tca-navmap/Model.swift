// Facts pulled out of the source, before any cross-file resolution.

/// What syntax alone cannot tell the extractor.
struct Configuration {

    /// The reducer at the top of the app.
    var appRoot: String
    /// Reducers that are not a place a user goes, such as a debug launcher that embeds dozens of
    /// features as standalone roots. A map leaves them out, along with whatever only they reach.
    var ignoredReducers: Set<String> = []
    /// View modifiers that apply their content conditionally: `.if(condition) { … } else: { … }`.
    var conditionModifiers: Set<String> = ["if"]
    /// View modifiers that name a screen with a string literal, such as an analytics
    /// `.trackScreen("Profile")`.
    var screenNameModifiers: Set<String> = []
}

/// A `@Reducer` struct or enum, keyed by its qualified name (`Contacts.Destination`).
struct ReducerDecl {

    let name: String
    let isEnum: Bool
    let isGeneric: Bool
    let file: String
    /// `@Presents var destination: Destination.State?` → ("destination", "Destination").
    var presents: [(property: String, type: String)] = []
    /// `var path = StackState<Path.State>()` → ("path", "Path").
    var stacks: [(property: String, type: String)] = []
    /// `Scope(state: \.toolbar, …) { Toolbar() }`.
    var scopes: [(property: String, type: String)] = []
    /// Enum reducers: `case profile(Profile)`.
    var cases: [(name: String, type: String)] = []
    /// Plain arrays in State, `var steps: [Step]` → ("steps", "Step"): a navigation path when a view
    /// binds `NavigationStack(path: $store.steps)`.
    var arrays: [(property: String, element: String)] = []
}

/// A switch arm in a reducer that assigns a presentation slot.
struct Trigger {

    let owner: String
    let action: String
    let slot: String
    let caseName: String
    /// The payload's own case, for a path element: `.signIn(.code(…))` → `code`.
    let subCase: String?
}

/// A `.navigationDestination(for: Main.Step.self) { step in switch step { … } }` arm: what a
/// plain-array path element shows.
struct PathDestination {

    let reducer: String
    let elementType: String
    /// `signIn.code` for `case .signIn(.code(let destination))`.
    let caseName: String
    let view: String?
    /// `store.scope(state: \.about, …)` → `about`, the embedded child it shows.
    let scopedProperty: String?
}

/// Where a store other than the view's own `store` comes from.
enum StoreOrigin {

    /// `let detailStore: StoreOf<ContactDetail>`.
    case type(String)
    /// `{ childStore in … }` on `store.scope(state: \.$destination, …).picker`. The action
    /// path names the child when the state path is a computed filter (`\.filteredGroups`).
    case scoped(path: [String], caseName: String?, actionPath: [String])
}

/// A `store.send(…)` in a view, with what the user touches to fire it.
struct UISend {

    let reducer: String
    let action: String
    let control: String
    let site: String?
    let file: String
    /// For a send on another store: the reducer whose view makes it, the parent drawing a list's rows.
    var host: String?
}

/// A presentation modifier bound to a slot case: `.sheet(item: …\.$destination….profile)`.
struct Presentation {

    /// The reducer whose view draws the presentation.
    let reducer: String
    /// Embedded-property path from `reducer` to the slot's owner: `["contacts"]` when `Main` draws
    /// `\.contacts.destination?.profile`; empty when the view draws its own store's slot.
    let hostPath: [String]
    let slot: String
    let caseName: String?
    let style: String
    let condition: String?
    let file: String
}

struct Index {

    var reducers: [String: ReducerDecl] = [:]
    /// Reducer name → every file declaring a reducer of that name, when there is more than one. Only
    /// the last one read is in `reducers`.
    var duplicateReducers: [String: [String]] = [:]
    /// View struct name → reducer it holds a store of.
    var views: [String: (reducer: String, file: String)] = [:]
    /// "View|member" → a stored or computed member's declared type or accessor, so a send in an
    /// extension can find which store `detailsStore` is.
    var viewMembers: [String: (type: String?, accessor: String?)] = [:]
    var triggers: [Trigger] = []
    var helperAssignments: [String: [(func: String, slot: String, caseName: String)]] = [:]
    /// An arm's calls to helper functions, with the arguments it passes from its own pattern
    /// (`handleRowMenu(action, contact, state:)` from `.rowMenu(let action, let contact)` → #0, #1).
    var helperCalls: [(owner: String, action: String, func: String, boundArguments: Set<String>)] = []
    /// "Owner|helper" → the parameter a helper switches over, as its label or `#position`.
    var helperSwitchParameters: [String: String] = [:]
    /// View-created stores outside previews (`WebView(store: Store(initialState: …) { Web() })`):
    /// UI owner → the reducers it creates. `nil` is the app itself (a window it fills itself).
    var createdStores: [String?: Set<String>] = [:]
    /// "Owner|helper" → arms of a switch inside that helper, credited to the calling arm.
    var helperArms: [String: [(arm: String, slot: String, caseName: String)]] = [:]
    /// Owner → each arm's own sends (`.send(.x)`), so a control that fires the arm also reaches
    /// what the sent action opens. `helper` is set when the arm belongs to a helper's switch.
    var armSends: [String: [(arm: String, sent: String, helper: String?)]] = [:]
    var sends: [UISend] = []
    /// Sends on a store other than the view's own, resolved to the store's reducer once the graph exists.
    var foreignSends: [(origin: StoreOrigin, send: UISend)] = []
    /// "UI owner|function|label" → the send a view helper makes with an action it was handed
    /// (`exportMenuItem(…, action: Home.Action)` → `store.send(action)`).
    var parameterSends: [String: UISend] = [:]
    /// Calls to view helpers with an action argument, joined with `parameterSends`.
    var helperCallActions: [(key: String, action: String, control: String, site: String?, file: String)] = []
    var pathDestinations: [PathDestination] = []
    var presentations: [Presentation] = []
    var dependencies: [String: Set<String>] = [:]
    var serviceCalls: [String: Set<String>] = [:]
    var delegates: [String: Set<String>] = [:]
    var screenNames: [String: Set<String>] = [:]
    var accessibilityIDs: [String: Set<String>] = [:]
}
