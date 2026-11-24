import ComposableArchitecture
import SwiftUI

@Reducer
struct AppFeature {

    @ObservableState
    struct State {
        var contacts = Contacts.State()
        var settings = Settings.State()
        var launcher: Launcher.State?
        var selectedTab = Tab.contacts
    }

    enum Tab {
        case contacts
        case settings
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case contacts(Contacts.Action)
        case launcher(Launcher.Action)
        case settings(Settings.Action)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Scope(state: \.contacts, action: \.contacts) { Contacts() }
        Scope(state: \.settings, action: \.settings) { Settings() }
        Reduce { _, _ in .none }
            .ifLet(\.launcher, action: \.launcher) { Launcher() }
    }
}

struct AppView: View {

    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        TabView(selection: $store.selectedTab) {
            ContactsView(store: store.scope(state: \.contacts, action: \.contacts))
                .tabItem { Label("Contacts", systemImage: "person.2") }
                .tag(AppFeature.Tab.contacts)
            SettingsView(store: store.scope(state: \.settings, action: \.settings))
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppFeature.Tab.settings)
        }
    }
}

@main
struct ExampleApp: App {

    let store = Store(initialState: AppFeature.State()) { AppFeature() }

    var body: some Scene {
        WindowGroup { AppView(store: store) }
    }
}
