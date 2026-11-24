import ComposableArchitecture
import SwiftUI

@Reducer
struct ContactDetail {

    @ObservableState
    struct State {
        let id: UUID
        @Presents var alert: AlertState<Action.Alert>?
        @Presents var edit: EditContact.State?
    }

    enum Action {
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)
        case deleteButtonTapped
        case edit(PresentationAction<EditContact.Action>)
        case editButtonTapped

        enum Alert {
            case confirmDelete
        }

        enum Delegate {
            case didDelete(UUID)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .alert(.presented(.confirmDelete)):
                return .send(.delegate(.didDelete(state.id)))
            case .alert, .delegate, .edit:
                return .none
            case .deleteButtonTapped:
                state.alert = .deleteConfirmation
                return .none
            case .editButtonTapped:
                state.edit = EditContact.State(id: state.id)
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$edit, action: \.edit) { EditContact() }
    }
}

@Reducer
struct EditContact {

    @ObservableState
    struct State {
        let id: UUID
    }
}

struct ContactDetailView: View {

    @Bindable var store: StoreOf<ContactDetail>

    var body: some View {
        Form {
            Button("Edit") {
                store.send(.editButtonTapped)
            }
            Button("Delete contact", role: .destructive) {
                store.send(.deleteButtonTapped)
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .sheet(item: $store.scope(state: \.edit, action: \.edit)) { editStore in
            EditContactView(store: editStore)
        }
    }
}
