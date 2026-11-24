import ComposableArchitecture
import SwiftUI

@Reducer
struct Settings {

    @ObservableState
    struct State {
        @Presents var about: About.State?
    }

    enum Action {
        case about(PresentationAction<About.Action>)
        case aboutButtonTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .about:
                return .none
            case .aboutButtonTapped:
                state.about = About.State()
                return .none
            }
        }
        .ifLet(\.$about, action: \.about) { About() }
    }
}

@Reducer
struct About {

    @ObservableState
    struct State {}
}

struct SettingsView: View {

    @Bindable var store: StoreOf<Settings>
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Button("About") {
            store.send(.aboutButtonTapped)
        }
        .trackScreen("Settings")
        .if(sizeClass == .compact) { view in
            view.sheet(item: $store.scope(state: \.about, action: \.about)) { AboutView(store: $0) }
        } else: { view in
            view.popover(item: $store.scope(state: \.about, action: \.about)) { AboutView(store: $0) }
        }
    }
}
