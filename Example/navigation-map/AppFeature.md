# Navigation map: AppFeature

> Generated from source by `tca-navmap` — do not edit by hand. Regenerate: `tca-navmap AppFeature --sources Sources --ignore Launcher --screen-name-modifier trackScreen`

**Reached from the app root:** **AppFeature**

## Tree

- **AppFeature**
  - `contacts` embeds **Contacts**
    - `rows` embeds **ContactRow**
    - `destination.add` → **AddContact** · `sheet` · via `.addButtonTapped` ← Button "Add contact" in .toolbar on List
    - `destination.detail` → **ContactDetail** · `navigationDestination` · via `.rows.element.delegate.open` ← Button in ForEach
      - `alert.deleteConfirmation` → `AlertState<Action.Alert>` · `alert` · via `.deleteButtonTapped` ← Button "Delete contact" in Form
      - `edit` → **EditContact** · `sheet` · via `.editButtonTapped` ← Button "Edit" in Form
  - `settings` embeds **Settings**
    - `about` → **About** · `popover` when `!(sizeClass == .compact)` / `sheet` when `sizeClass == .compact` · via `.aboutButtonTapped` ← Button "About"

## Features

### AppFeature

- Reducer: `Sources/AppFeature.swift`
- Views: `AppView (Sources/AppFeature.swift)`

### Contacts

- Reducer: `Sources/Contacts/Contacts.swift`
- Views: `ContactsView (Sources/Contacts/Contacts.swift)`
- Parents: AppFeature
- Service calls: `contactsClient.fetchAll`

| Destination | Opens | Presented as | Action | UI control |
|---|---|---|---|---|
| `destination.add` | AddContact | `sheet` | `.addButtonTapped` | Button "Add contact" in .toolbar on List (`body`) |
| `destination.detail` | ContactDetail | `navigationDestination` | `.rows.element.delegate.open` | Button in ForEach (`body`) in ContactRow → `.tapped` |

| Other UI action | UI control |
|---|---|
| `.onAppear` | .onAppear on List in NavigationStack (`body`) |

### ContactRow

- Reducer: `Sources/Contacts/Contacts.swift`
- Parents: Contacts
- Delegates sent to parent: `open`

### AddContact

- Reducer: `Sources/Contacts/Contacts.swift`
- Parents: Contacts

### ContactDetail

- Reducer: `Sources/Contacts/ContactDetail.swift`
- Views: `ContactDetailView (Sources/Contacts/ContactDetail.swift)`
- Parents: Contacts
- Delegates sent to parent: `didDelete`

| Destination | Opens | Presented as | Action | UI control |
|---|---|---|---|---|
| `alert.deleteConfirmation` | `AlertState<Action.Alert>` | `alert` | `.deleteButtonTapped` | Button "Delete contact" in Form (`body`) |
| `edit` | EditContact | `sheet` | `.editButtonTapped` | Button "Edit" in Form (`body`) |

### EditContact

- Reducer: `Sources/Contacts/ContactDetail.swift`
- Parents: ContactDetail

### Settings

- Reducer: `Sources/Settings/Settings.swift`
- Views: `SettingsView (Sources/Settings/Settings.swift)`
- Parents: AppFeature
- Screen names: Settings

| Destination | Opens | Presented as | Action | UI control |
|---|---|---|---|---|
| `about` | About | `popover` when `!(sizeClass == .compact)`<br>`sheet` when `sizeClass == .compact` | `.aboutButtonTapped` | Button "About" (`body`) |

### About

- Reducer: `Sources/Settings/Settings.swift`
- Parents: Settings

## Not reachable from the app

No user path presents or embeds these reducers.

- **Playground** (`Sources/Debug/Launcher.swift`)
