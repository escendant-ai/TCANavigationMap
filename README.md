# tca-navmap

A command-line tool that reads the source of an app built on [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) and writes a map of every screen: what opens it, how it is presented, which control the user touches to get there, and the shortest route to it from the app's root.

It reads syntax only, with [swift-syntax](https://github.com/swiftlang/swift-syntax). It does not build your app, import TCA or run anything, so it works on a checkout that does not compile.

Each map is `<Root>.md` to read and `<Root>.json` for tools, with the same facts in both. This is one line of the tree from the [example's map](Example/navigation-map/AppFeature.md):

```
- `destination.detail` → **ContactDetail** · `navigationDestination` · via `.rows.element.delegate.open` ← Button in ForEach
```

It says: `Contacts` opens `ContactDetail` as a navigation push when its `destination` becomes `.detail`; the reducer does that on a row's `delegate.open`; and the row sends that when the button in the list's `ForEach` is tapped.

## What it is for

- **A coding agent driving a simulator.** The map tells it which screen holds a feature, the taps that reach it, and what to expect there.
- **Someone new to the codebase.** The tree is the app's navigation, generated from the code in front of them.
- **Review.** Maps are byte-identical for unchanged source, so two checkouts diff cleanly, and the whole-app map ends with the reducers nothing reaches any more.

## Status

The tests run on source held in the test files; see [CONTRIBUTING.md](CONTRIBUTING.md). Requirements: macOS 13 or later and a Swift 6 toolchain. Linux has not been tried.

## Quick start

```bash
swift build -c release

# The example: a small app's source, read but never built
cd Example
../.build/release/tca-navmap AppFeature --sources Sources --ignore Launcher --screen-name-modifier trackScreen
```

That writes `Example/navigation-map/AppFeature.md` and `AppFeature.json`; the copies in this repository came from that command.

The first release build compiles swift-syntax and took about two and a half minutes on an Apple silicon Mac; a debug build took about fifteen seconds with swift-syntax already fetched.

## Using it on your app

Run it from the root of your checkout, so the file paths in the map are relative to it:

```bash
tca-navmap AppFeature --sources App,Packages            # the whole app
tca-navmap AppFeature --sources App,Packages --area Contacts   # one area
```

`AppFeature` is the `@Reducer` at the top of your app. Maps are cheap to make, so generate one when you need it and keep the output directory out of git; a committed map describes some other commit.

| Option | Meaning |
|---|---|
| `<AppRoot>` | The reducer at the top of the app. Required. |
| `--area <Reducer>` | Map one area. Only reducers under that reducer's directory are expanded; a reducer outside it is listed as an edge and marked "outside this map". |
| `--sources <dir>[,<dir>…]` | Directories to read. Default: the current directory. |
| `--exclude <text>[,<text>…]` | Skip files whose path contains any of these, for example `/Generated/`. |
| `--boundary <dir>[,<dir>…]` | Directories whose reducers are expanded, replacing the default. Include the area's own directory to widen an area map. |
| `--ignore <Reducer>[,…]` | Reducers that are not a place a user goes, such as a debug launcher that embeds many features as standalone roots. They are left out, along with whatever only they reach. |
| `--condition-modifier <name>[,…]` | Modifiers that apply their content conditionally. Default: `if`, for the common `.if(condition) { … } else: { … }` extension. |
| `--screen-name-modifier <name>[,…]` | Modifiers that name a screen with a string literal, such as an analytics `.trackScreen("Profile")`. The names are listed per feature. |
| `--out <dir>` | Where the two files are written. Default: `navigation-map`. |

Directories named `.build`, `.git`, `.swiftpm`, `Carthage`, `DerivedData` or `Pods`, and any directory whose name ends in `Tests`, are always skipped. A source directory that cannot be listed or a source file that cannot be read fails the run, because a file parsed as empty would silently drop its reducers from the map.

## What a map records

The whole-app map covers every reducer reachable from the root and from stores the app creates outside it (a store built for a separate window, say), and ends with any reducer nothing reaches. For each reducer it expands:

- **Destinations.** Each `@Presents` and `StackState` slot and each case of its enum, and each step of a plain-array `NavigationStack(path:)` with the view its `navigationDestination(for:)` switch draws. For each: the reducer it opens, how the view presents it (`sheet`, `fullScreenCover`, `navigationDestination`, `alert`, your own modifiers, with the condition of an enclosing condition modifier), the action arm that assigns it, and the controls that end up sending that action.
- **How a control reaches a destination.** Directly; through an arm that sends another action on; through a child's `delegate` action handled by the parent; through a list row's store; through a reducer helper the arm calls; or through a view helper or subview that is handed the action as a parameter. The control is listed with the reducer whose view holds it and the actions in between.
- **Other UI actions.** Every `store.send` that opens nothing. A send that opens a parent's destination, through a delegate action or a row's store, is listed with that destination and not here.
- **Embeds.** Always-on children (`Scope`, `forEach`), the row reducer of a generic list component, and stores a view creates for itself.
- **Service calls.** The `@Dependency` members the reducer calls.
- **Accessibility identifiers** set in the reducer's views, and screen names if you configure a modifier.
- **Entry path.** The shortest route from the app root to the root of an area map.

A presentation drawn by a parent from its own store is credited to the slot's owner and labelled with the parent: `inline in Main` on a child's `destination.profile` means `MainView` draws it from `\.child.destination?.profile`, as a detail column beside a list does.

Generic reducers (ones with type parameters) are treated as shared components: named in the tree, not described.

## What it expects of your code

It recognises current TCA style, and several of these are matched as text:

- reducers declared with the `@Reducer` macro, struct or enum
- a view (or `ViewModifier`, or `UIViewRepresentable`) that stores a `StoreOf<Feature>` and calls it `store`
- a reducer body that switches on a value called `action` and mutates a value called `state`
- child-to-parent messages as `.delegate(.something)`
- key-path scoping: `store.scope(state: \.child, action: \.child)`

Code in another style is not an error. Its reducers are still listed; the destinations simply come out with no trigger or no presentation.

## What it cannot see

It reads syntax, not types, so it misses whatever is decided at run time:

- Whether a control is visible. `if contact.canInvite { Button(…) }` is recorded as a control that exists.
- A presentation inside a plain Swift `if`. Only a configured condition modifier's condition is recorded.
- Navigation done by binding rather than by sending an action, such as a `TabView` bound to `$store.selectedTab`.
- Actions no control sends: deep links, notifications and the results of effects. The destination lists the action with no control.
- The cases of a reducer helper that switches over state rather than over a value the action carried. The calling arm is credited with everything the helper opens.
- Labels built at run time, such as `Text(title)`, and icon-only buttons. Both are shown as a bare `Button`.
- A control more than six actions away from the arm that opens the destination. The search stops there, and the destination lists the action with no control.
- Two reducers with the same name. Only one is mapped, and a child type that could be either of two nested reducers is not followed. Both print a warning.
- A presentation through a wrapper it does not know. A destination with nothing under "Presented as" is that case.

## Related tools

[tca-graph](https://github.com/tornikegomareli/tca-graph) also reads a TCA codebase with swift-syntax. Its README describes a graph of reducers, their state, actions, composition and dependencies, with a web viewer and a linter. tca-navmap answers a narrower question, from the view code as well as the reducers: how a user gets to each screen. The two are complementary.

## License

MIT. See [LICENSE](LICENSE).
