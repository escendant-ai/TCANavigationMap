import ComposableArchitecture
import SwiftUI

@Reducer
struct Contacts {

    @ObservableState
    struct State {
        var rows: IdentifiedArrayOf<ContactRow.State> = []
        @Presents var destination: Destination.State?
    }

    enum Action {
        case addButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case didLoad([ContactRow.State])
        case onAppear
        case rows(IdentifiedActionOf<ContactRow>)
    }

    @Reducer
    enum Destination {
        case add(AddContact)
        case detail(ContactDetail)
    }

    @Dependency(\.contactsClient) var contactsClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.destination = .add(AddContact.State())
                return .none
            case .destination(.presented(.detail(.delegate(.didDelete(let id))))):
                state.rows.remove(id: id)
                state.destination = nil
                return .none
            case .destination:
                return .none
            case .didLoad(let rows):
                state.rows = IdentifiedArray(uniqueElements: rows)
                return .none
            case .onAppear:
                return .run { send in
                    await send(.didLoad(try await contactsClient.fetchAll()))
                }
            case .rows(.element(id: let id, action: .delegate(.open))):
                state.destination = .detail(ContactDetail.State(id: id))
                return .none
            case .rows:
                return .none
            }
        }
        .forEach(\.rows, action: \.rows) { ContactRow() }
        .ifLet(\.$destination, action: \.destination)
    }
}

@Reducer
struct ContactRow {

    @ObservableState
    struct State: Identifiable {
        let id: UUID
        var name: String
    }

    enum Action {
        case delegate(Delegate)
        case tapped

        enum Delegate {
            case open
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .delegate:
                return .none
            case .tapped:
                return .send(.delegate(.open))
            }
        }
    }
}

@Reducer
struct AddContact {

    @ObservableState
    struct State {
        var name = ""
    }
}

struct ContactsView: View {

    @Bindable var store: StoreOf<Contacts>

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.scope(state: \.rows, action: \.rows)) { rowStore in
                    Button {
                        rowStore.send(.tapped)
                    } label: {
                        Text(rowStore.name)
                    }
                }
            }
            .toolbar {
                Button("Add contact") {
                    store.send(.addButtonTapped)
                }
            }
            .navigationDestination(item: $store.scope(state: \.destination?.detail, action: \.destination.detail)) { detailStore in
                ContactDetailView(store: detailStore)
            }
            .sheet(item: $store.scope(state: \.destination?.add, action: \.destination.add)) { addStore in
                AddContactView(store: addStore)
            }
            .onAppear {
                store.send(.onAppear)
            }
        }
    }
}
