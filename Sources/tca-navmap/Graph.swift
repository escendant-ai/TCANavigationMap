import Foundation

// MARK: - Output model

struct NavigationMap: Codable {

    let root: String
    let regenerate: String
    /// Shortest route from the app's root reducer, so an agent knows which tab or screen hosts the root.
    let entryPath: [PathStep]
    /// Whole-app map only: reducers the app runs in a store of their own, outside the root's tree
    /// (a window the app fills itself).
    let otherRoots: [String]
    let features: [Feature]
    /// Whole-app map only: reducers no user path reaches.
    let unreachable: [UnreachableFeature]
}

struct UnreachableFeature: Codable {

    let name: String
    let file: String
}

struct PathStep: Codable {

    let feature: String
    let via: String?
}

struct Feature: Codable {

    let name: String
    let file: String
    let views: [String]
    let screenNames: [String]
    let accessibilityIdentifiers: [String]
    let dependencies: [String]
    let serviceCalls: [String]
    let delegatesSent: [String]
    let embeds: [Embed]
    let destinations: [Destination]
    let otherUIActions: [UIControl]
    let presentedBy: [String]
    /// Outside the map's boundary: listed so the edge is visible, not expanded.
    let isExternal: Bool

    enum CodingKeys: String, CodingKey {
        case name, file, views, screenNames, accessibilityIdentifiers, dependencies
        case serviceCalls, delegatesSent, embeds, destinations, otherUIActions, presentedBy
        case isExternal = "external"
    }
}

struct Embed: Codable {

    let property: String
    let feature: String
}

struct Destination: Codable {

    let slot: String
    let caseName: String?
    let feature: String?
    let type: String
    let presentedAs: [PresentedAs]
    let triggers: [TriggerRef]
}

struct PresentedAs: Codable, Hashable {

    let style: String
    let condition: String?
}

struct TriggerRef: Codable {

    let action: String
    let controls: [UIControl]
}

struct UIControl: Codable, Hashable, Comparable {

    let action: String
    let control: String
    let site: String?
    let file: String
    /// Set when the control sits in another reducer's view: a child whose delegate the trigger handles.
    var reducer: String?
    /// The actions between the control's own and the trigger, in order, when the control reaches the
    /// trigger through re-sends (`.openExport` → `.showExport`) or a child's delegate.
    var chain: [String]?

    /// Total order, so regenerating from unchanged source is byte-identical and maps from two checkouts diff cleanly.
    static func < (lhs: UIControl, rhs: UIControl) -> Bool {
        (lhs.action, lhs.control, lhs.site ?? "", lhs.file, lhs.reducer ?? "", (lhs.chain ?? []).joined(separator: " "))
            < (rhs.action, rhs.control, rhs.site ?? "", rhs.file, rhs.reducer ?? "", (rhs.chain ?? []).joined(separator: " "))
    }
}

// MARK: - Builder

struct GraphBuilder {

    let index: Index
    let configuration: Configuration
    var serviceCalls: [String: Set<String>] = [:]

    init(index: Index, actionMappers: [String: [(item: String, action: String)]], configuration: Configuration) {
        self.index = index
        self.configuration = configuration
        var sends: [UISend] = []
        for send in index.sends {
            guard send.action.hasPrefix("call:") else {
                sends.append(send)
                continue
            }

            let function = String(send.action.dropFirst("call:".count))
            guard let mapping = actionMappers["\(send.reducer)|\(function)"] else {
                sends.append(send)
                continue
            }

            for (item, action) in mapping {
                sends.append(UISend(
                    reducer: send.reducer,
                    action: action,
                    control: "item .\(item) of \(send.control)",
                    site: send.site,
                    file: send.file
                ))
            }
        }
        // `exportMenuItem(title: "PDF", …, action: .showExport)` → the helper's `store.send(action)`.
        for call in index.helperCallActions {
            guard let send = index.parameterSends[call.key] else { continue }

            sends.append(UISend(reducer: send.reducer, action: call.action, control: call.control, site: call.site, file: call.file))
        }
        self.expandedSends = sends
        for (origin, send) in index.foreignSends {
            guard let reducer = reducer(of: origin, from: send.reducer) else { continue }

            expandedSends.append(UISend(
                reducer: reducer,
                action: send.action,
                control: send.control,
                site: send.site,
                file: send.file,
                host: send.host
            ))
        }
    }

    // MARK: - Private

    private var expandedSends: [UISend]
}

extension GraphBuilder {

    /// What the map gets wrong without saying so in its output: a reducer name declared twice, where
    /// only one declaration is mapped, and a child type that names more than one reducer, whose edge
    /// is dropped.
    func warnings(relativeTo base: String) -> [String] {
        let duplicates = index.duplicateReducers.map { name, files in
            "\(name) is declared as a reducer in \(files.map { $0.relative(to: base) }.joined(separator: " and ")); only the last one is mapped"
        }
        let ambiguous = index.reducers.values.flatMap { reducer -> [String] in
            let types = (reducer.presents + reducer.stacks + reducer.scopes).map(\.type) + reducer.cases.map(\.type)
            return types.compactMap { type in
                let base = type.genericBase
                guard resolve(type, in: reducer.name) == nil else { return nil }

                let candidates = index.reducers.keys.filter { $0.hasSuffix("." + base) }.sorted()
                guard candidates.count > 1 else { return nil }

                return "\(base) in \(reducer.name) could be \(candidates.joined(separator: " or ")); what it opens is not mapped"
            }
        }
        return Array(Set(duplicates + ambiguous)).sorted()
    }

    /// Features under one of `boundaries` are expanded; one outside them is described but not
    /// descended into, so the Contacts map stops at the edge of Contacts instead of walking the whole app.
    /// No boundaries expands everything reachable: the whole-app map.
    func build(root: String, boundaries: [String], regenerate: String, relativeTo base: String) -> NavigationMap {
        let notUserPaths = configuration.ignoredReducers
        let isInside = { (file: String) in boundaries.isEmpty || boundaries.contains { file.hasPrefix($0 + "/") } }
        var order: [String] = []
        var seen: Set<String> = []
        var presentedBy: [String: Set<String>] = [:]
        let otherRoots = boundaries.isEmpty ? (index.createdStores[nil] ?? []).compactMap { resolve($0, in: root) }.sorted() : []
        func visit(_ name: String) {
            guard seen.insert(name).inserted else { return }

            order.append(name)
            // Generic reducers (a `PagedList<Row>`, say) are shared components: list, don't expand.
            guard let reducer = index.reducers[name], !reducer.isGeneric else { return }
            guard name == root || isInside(reducer.file) else { return }

            for (child, _, _) in children(of: name) where !notUserPaths.contains(child) {
                presentedBy[child, default: []].insert(name)
                visit(child)
            }
        }
        visit(root)
        for other in otherRoots { visit(other) }

        // Searched over every reducer, not only the ones in this map, so an area map and the whole-app
        // map agree about a control whose destination belongs to a parent outside the area.
        let openedElsewhere = index.reducers.values
            .filter { !$0.isEnum && !$0.isGeneric }
            .reduce(into: Set<ForeignSend>()) { $0.formUnion(destinations(of: $1, base: base).used.foreign) }
        let features = order.compactMap { name -> Feature? in
            // Enum slots are folded into their owner; generic components (a `PagedList<Row>`)
            // are named in the tree, not described.
            guard let reducer = index.reducers[name], !reducer.isEnum, !reducer.isGeneric else { return nil }

            return feature(
                reducer,
                presentedBy: presentedBy[name] ?? [],
                base: base,
                isExternal: name != root && !otherRoots.contains(name) && !isInside(reducer.file),
                openedElsewhere: openedElsewhere
            )
        }
        let unreachable = boundaries.isEmpty ? index.reducers.values
            .filter { !$0.isEnum && !$0.isGeneric && !seen.contains($0.name) && !notUserPaths.contains($0.name) }
            .sorted { $0.name < $1.name }
            .map { reducer in
                UnreachableFeature(name: reducer.name, file: reducer.file.relative(to: base))
            } : []
        return NavigationMap(
            root: root,
            regenerate: regenerate,
            entryPath: entryPath(to: root, from: configuration.appRoot),
            otherRoots: otherRoots,
            features: features,
            unreachable: unreachable
        )
    }
}

private extension GraphBuilder {

    /// The reducer of a store that isn't the view's own: its declared type, or the child its scope
    /// path reaches from the view's reducer. A generic list stops at its row reducer, the first
    /// reducer among its type arguments (`PagedList<NoteItem, …>` → `NoteItem`).
    func reducer(of origin: StoreOrigin, from owner: String) -> String? {
        switch origin {
        case .type(let type):
            return resolve(type, in: owner)
        case .scoped(let path, let caseName, let actionPath):
            return reducer(at: path, caseName: caseName, from: owner)
                ?? (actionPath.isEmpty ? nil : reducer(at: actionPath, caseName: caseName, from: owner))
        }
    }

    func reducer(at path: [String], caseName: String?, from owner: String) -> String? {
        var current = owner
        for (position, property) in path.enumerated() {
            guard let reducer = index.reducers[current] else { return nil }

            if let embed = embeddedScopes(of: reducer).first(where: { $0.property == property }) {
                guard let child = resolve(embed.type, in: current) else { return nil }

                if index.reducers[child]?.isGeneric == true {
                    return embed.type.typeArguments.lazy.compactMap { resolve($0, in: current) }.first ?? child
                }
                current = child
            } else if let slot = (reducer.presents + reducer.stacks).first(where: { $0.property == property }),
                      let slotType = resolve(slot.type, in: current) {
                guard let slotReducer = index.reducers[slotType], slotReducer.isEnum else {
                    current = slotType
                    continue
                }

                guard position == path.count - 1, let caseName, let enumCase = slotReducer.cases.first(where: { $0.name == caseName }),
                      let child = resolve(enumCase.type, in: slotType) else { return nil }

                current = child
            } else {
                return nil
            }
        }
        return current
    }

    /// Resolves a type written inside `context` the way Swift would: innermost scope first.
    func resolve(_ type: String, in context: String) -> String? {
        let base = type.genericBase
        var components = context.split(separator: ".").map(String.init)
        while true {
            let candidate = (components + [base]).joined(separator: ".")
            if index.reducers[candidate] != nil { return candidate }
            if components.isEmpty { break }
            components.removeLast()
        }
        let suffixMatches = index.reducers.keys.filter { $0.hasSuffix("." + base) }
        return suffixMatches.count == 1 ? suffixMatches[0] : nil
    }

    /// Children of a struct reducer: (feature, label, kind) for embeds and every slot case.
    func children(of name: String) -> [(feature: String, via: String, kind: ChildKind)] {
        guard let reducer = index.reducers[name] else { return [] }

        var result: [(String, String, ChildKind)] = []
        for scope in embeddedScopes(of: reducer) {
            guard let child = resolve(scope.type, in: name) else { continue }

            result.append((child, "embeds \(scope.property)", .embed))
            // A generic list's rows: `PagedList<NoteItem, …>` shows a NoteItem per row.
            if index.reducers[child]?.isGeneric == true {
                for row in scope.type.typeArguments.compactMap({ resolve($0, in: name) }) where index.reducers[row]?.isGeneric == false {
                    result.append((row, "embeds \(scope.property) rows", .row(of: scope.property)))
                }
            }
        }
        for created in (index.createdStores[name] ?? []).sorted() {
            if let child = resolve(created, in: name) { result.append((child, "creates a store in its view", .createdStore)) }
        }
        for slot in reducer.presents + reducer.stacks {
            guard let slotType = resolve(slot.type, in: name), let slotReducer = index.reducers[slotType] else { continue }
            guard slotReducer.isEnum else {
                result.append((slotType, slot.property, .slot))
                continue
            }

            for enumCase in slotReducer.cases {
                if let child = resolve(enumCase.type, in: slotType) {
                    result.append((child, "\(slot.property).\(enumCase.name)", .slot))
                }
            }
        }
        return result
    }

    /// `.ifLet(\.$picker) { Picker() }` wires a presentation slot, not an always-on child.
    func embeddedScopes(of reducer: ReducerDecl) -> [(property: String, type: String)] {
        let slots = Set((reducer.presents + reducer.stacks).map(\.property))
        var seen: Set<String> = []
        return reducer.scopes.filter { !slots.contains($0.property) && seen.insert("\($0.property)|\($0.type)").inserted }
    }

    /// Where an action arriving at `owner` came from, when it is a child's: `manageMember.delegate.didRemove`
    /// on Contacts is MemberDetail's `delegate.didRemove`. A generic list's row action can sit under any
    /// number of the list's own cases, so each suffix of the rest is offered against the row reducer.
    func routes(of action: String, from owner: String) -> [(child: String, rest: String)] {
        guard let reducer = index.reducers[owner] else { return [] }

        let components = action.split(separator: ".").map(String.init)
        guard let head = components.first else { return [] }

        var rest = Array(components.dropFirst())
        var result: [(String, String)] = []
        if let embed = embeddedScopes(of: reducer).first(where: { $0.property == head }), let child = resolve(embed.type, in: owner) {
            if rest.first == "element" { rest.removeFirst() }
            let rows = embed.type.typeArguments.compactMap { resolve($0, in: owner) }
            if index.reducers[child]?.isGeneric == true, !rows.isEmpty {
                for row in rows {
                    for drop in 0..<rest.count { result.append((row, rest.dropFirst(drop).joined(separator: "."))) }
                }
            } else if !rest.isEmpty {
                result.append((child, rest.joined(separator: ".")))
            }
        }
        if let slot = (reducer.presents + reducer.stacks).first(where: { $0.property == head }), let slotType = resolve(slot.type, in: owner) {
            if ["presented", "element"].contains(rest.first) { rest.removeFirst() }
            if let slotReducer = index.reducers[slotType], slotReducer.isEnum {
                if let caseName = rest.first, let enumCase = slotReducer.cases.first(where: { $0.name == caseName }),
                   let child = resolve(enumCase.type, in: slotType), rest.count > 1 {
                    result.append((child, rest.dropFirst().joined(separator: ".")))
                }
            } else if !rest.isEmpty {
                result.append((slotType, rest.joined(separator: ".")))
            }
        }
        return result.filter { index.reducers[$0.0]?.isEnum == false }
    }

    func entryPath(to root: String, from appRoot: String) -> [PathStep] {
        var previous: [String: (String, String)] = [:]
        var queue = [appRoot]
        var seen: Set<String> = [appRoot]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == root { break }
            for (child, via, _) in children(of: current) where !seen.contains(child) && index.reducers[child]?.isGeneric == false
                && !configuration.ignoredReducers.contains(child) {
                seen.insert(child)
                previous[child] = (current, via)
                queue.append(child)
            }
        }
        guard root == appRoot || previous[root] != nil else { return [] }

        var steps: [PathStep] = [PathStep(feature: root, via: previous[root]?.1)]
        var current = root
        while let (parent, _) = previous[current] {
            steps.insert(PathStep(feature: parent, via: previous[parent]?.1), at: 0)
            current = parent
        }
        return steps
    }

    /// A reducer's destinations, and the sends that open them: its own, and the ones in a child's
    /// views that reach it through a delegate action or a row's store.
    func destinations(of reducer: ReducerDecl, base: String) -> (destinations: [Destination], used: SendUse) {
        let name = reducer.name
        let sends = expandedSends.filter { $0.reducer == name }
        let triggers = allTriggers(for: name)
        var usedSends = SendUse()

        var destinations: [Destination] = []
        for slot in reducer.presents + reducer.stacks {
            let slotType = resolve(slot.type, in: name)
            let slotTriggers = triggers.filter { $0.slot == slot.property }
            if let slotType, let slotEnum = index.reducers[slotType], slotEnum.isEnum {
                for enumCase in slotEnum.cases {
                    let caseTriggers = slotTriggers.filter { $0.caseName == enumCase.name }
                    destinations.append(Destination(
                        slot: slot.property,
                        caseName: enumCase.name,
                        feature: resolve(enumCase.type, in: slotType),
                        type: enumCase.type,
                        presentedAs: presentations(name, slot.property, enumCase.name),
                        triggers: triggerRefs(caseTriggers, owner: name, sends: sends, used: &usedSends, base: base)
                    ))
                }
            } else if let slotType, index.reducers[slotType] != nil {
                destinations.append(Destination(
                    slot: slot.property,
                    caseName: nil,
                    feature: slotType,
                    type: slot.type,
                    presentedAs: presentations(name, slot.property, nil),
                    triggers: triggerRefs(slotTriggers, owner: name, sends: sends, used: &usedSends, base: base)
                ))
            } else {
                // A plain AlertState / ConfirmationDialogState slot: each assigned factory is a "case".
                let caseNames = Array(Set(slotTriggers.map(\.caseName))).sorted()
                for caseName in caseNames.isEmpty ? [nil] : caseNames.map(Optional.some) {
                    destinations.append(Destination(
                        slot: slot.property,
                        caseName: caseName,
                        feature: nil,
                        type: slot.type,
                        presentedAs: presentations(name, slot.property, nil),
                        triggers: triggerRefs(
                            slotTriggers.filter { $0.caseName == caseName },
                            owner: name,
                            sends: sends,
                            used: &usedSends,
                            base: base
                        )
                    ))
                }
            }
        }

        // A plain array bound as a NavigationStack path (`var steps: [Step]`): one destination per
        // case its `navigationDestination(for:)` switch draws.
        for array in reducer.arrays where !presentations(name, array.property, "*").isEmpty {
            let arms = index.pathDestinations.filter {
                $0.reducer == name && ($0.elementType == array.element || $0.elementType.hasSuffix("." + array.element))
            }
            for arm in arms {
                let armTriggers = triggers.filter { trigger in
                    guard trigger.slot == array.property else { return false }

                    let assigned = trigger.subCase.map { "\(trigger.caseName).\($0)" } ?? trigger.caseName
                    return arm.caseName == assigned || (trigger.subCase == nil && arm.caseName.hasPrefix(trigger.caseName + "."))
                }
                let child = arm.scopedProperty
                    .flatMap { scoped in embeddedScopes(of: reducer).first { $0.property == scoped } }
                    .flatMap { resolve($0.type, in: name) }
                destinations.append(Destination(
                    slot: array.property,
                    caseName: arm.caseName,
                    feature: child,
                    type: arm.view ?? array.element,
                    presentedAs: presentations(name, array.property, "*"),
                    triggers: triggerRefs(armTriggers, owner: name, sends: sends, used: &usedSends, base: base)
                ))
            }
        }

        return (destinations, usedSends)
    }

    /// `openedElsewhere` holds the sends some other reducer's destination is credited with: they open
    /// something, so they are not this reducer's "other" UI actions either.
    func feature(
        _ reducer: ReducerDecl,
        presentedBy: Set<String>,
        base: String,
        isExternal: Bool,
        openedElsewhere: Set<ForeignSend>
    ) -> Feature {
        let name = reducer.name
        let sends = expandedSends.filter { $0.reducer == name }
        let (destinations, usedSends) = destinations(of: reducer, base: base)

        // Always-on children, then a generic list's rows and the stores its view makes for itself.
        let embeds = embeddedScopes(of: reducer).compactMap { scope in
            resolve(scope.type, in: name).map { Embed(property: scope.property, feature: $0) }
        }.filter { !configuration.ignoredReducers.contains($0.feature) } + children(of: name).compactMap { child in
            switch child.kind {
            case .row(let property): Embed(property: "\(property) rows", feature: child.feature)
            case .createdStore: Embed(property: "store made by its view", feature: child.feature)
            case .embed, .slot: nil
            }
        }

        // Facts written inside the slot enums' bodies (their Scope closures call services) belong here too.
        let slotEnums = (reducer.presents + reducer.stacks).compactMap { resolve($0.type, in: name) }.filter { index.reducers[$0]?.isEnum == true }
        let owners = [name] + slotEnums

        let otherUI = sends.enumerated()
            .filter { !usedSends.own.contains($0.offset) }
            .map { control($0.element, base: base) }
            .filter { !openedElsewhere.contains(ForeignSend(reducer: name, control: $0)) }

        let viewNames = index.views
            .filter { $0.value.reducer == name }
            .map { "\($0.key) (\($0.value.file.relative(to: base)))" }
            .sorted()

        return Feature(
            name: name,
            file: reducer.file.relative(to: base),
            views: viewNames,
            screenNames: (index.screenNames[name] ?? []).sorted(),
            accessibilityIdentifiers: (index.accessibilityIDs[name] ?? []).sorted(),
            dependencies: owners.flatMap { index.dependencies[$0] ?? [] }.uniqueSorted(),
            serviceCalls: owners.flatMap { serviceCalls[$0] ?? [] }.uniqueSorted(),
            delegatesSent: (index.delegates[name] ?? []).sorted(),
            embeds: embeds,
            destinations: destinations,
            otherUIActions: Array(Set(otherUI)).sorted(),
            presentedBy: presentedBy.sorted(),
            isExternal: isExternal
        )
    }

    func allTriggers(for name: String) -> [Trigger] {
        var result = index.triggers.filter { $0.owner == name }
        let helpers = index.helperAssignments[name] ?? []
        for call in index.helperCalls where call.owner == name {
            if passesSwitchedValue(call), let arms = index.helperArms["\(name)|\(call.func)"], !arms.isEmpty {
                for arm in arms {
                    result.append(Trigger(
                        owner: name,
                        action: "\(call.action).\(arm.arm)",
                        slot: arm.slot,
                        caseName: arm.caseName,
                        subCase: nil
                    ))
                }
                continue
            }
            for helper in helpers where helper.func == call.func {
                result.append(Trigger(owner: name, action: call.action, slot: helper.slot, caseName: helper.caseName, subCase: nil))
            }
        }
        return result
    }

    func presentations(_ reducer: String, _ slot: String, _ caseName: String?) -> [PresentedAs] {
        let found = index.presentations
            .filter { owner(of: $0) == reducer && $0.slot == slot && ($0.caseName == caseName || $0.caseName == "*") }
            .map { PresentedAs(style: $0.style, condition: $0.condition) }
        return Array(Set(found)).sorted { ($0.style, $0.condition ?? "") < ($1.style, $1.condition ?? "") }
    }

    /// The reducer that owns a presentation's slot: the drawing view's own reducer, or the one its
    /// host path reaches through embedded scopes.
    func owner(of presentation: Presentation) -> String? {
        var current = presentation.reducer
        for property in presentation.hostPath {
            guard let reducer = index.reducers[current],
                  let scope = embeddedScopes(of: reducer).first(where: { $0.property == property }),
                  let child = resolve(scope.type, in: current) else { return nil }

            current = child
        }
        return current
    }

    func triggerRefs(_ triggers: [Trigger], owner: String, sends: [UISend], used: inout SendUse, base: String) -> [TriggerRef] {
        let actions = Array(Set(triggers.map(\.action))).sorted()
        let search = ControlSearch(owner: owner, sends: sends, base: base)
        return actions.map { action in
            var visited: Set<String> = []
            let controls = controls(reaching: [action], in: owner, search: search, visited: &visited, used: &used)
            return TriggerRef(action: action, controls: Array(Set(controls)).sorted())
        }
    }

    /// Every control that ends up sending `trail[0]` to `owner`, where `trail` runs from the action
    /// being searched to the trigger: one the owner's views send directly; one that fires an arm which
    /// re-sends it (`.openExport` → `.send(.showExport)`); and, for an action a child
    /// delivers (`manageMember.delegate.didRemove`), the child's own controls for the rest of the path.
    func controls(
        reaching trail: [String],
        in owner: String,
        search: ControlSearch,
        visited: inout Set<String>,
        used: inout SendUse,
        parent: String? = nil
    ) -> [UIControl] {
        guard let action = trail.first, trail.count <= 6, visited.insert("\(owner)|\(action)").inserted else { return [] }

        var result: [UIControl] = []
        // A generic row reducer (`Item`) is sent to from every list in the app; only the rows this
        // parent draws count.
        let isGeneric = index.reducers[owner]?.isGeneric == true
        let sends = owner == search.owner
            ? search.sends
            : expandedSends.filter { $0.reducer == owner && (!isGeneric || $0.host == parent) }
        for (offset, send) in sends.enumerated() where send.action == action || send.action.hasPrefix(action + ".")
            // `store.send(.rowMenu(action, contact))` forwards a runtime value, so the send
            // only names the outer case — it still reaches every nested arm.
            || action.hasPrefix(send.action + ".") {
            var found = control(send, base: search.base)
            if owner == search.owner {
                used.own.insert(offset)
            } else {
                used.foreign.insert(ForeignSend(reducer: owner, control: found))
            }
            found.reducer = owner == search.owner ? nil : owner
            found.chain = trail.count > 1 ? Array(trail.dropLast()) : nil
            result.append(found)
        }
        for entry in armSends(of: owner) where entry.sent == action || entry.sent.hasPrefix(action + ".") {
            result += controls(reaching: [entry.arm] + trail, in: owner, search: search, visited: &visited, used: &used, parent: parent)
        }
        for (child, rest) in routes(of: action, from: owner) {
            result += controls(reaching: [rest] + trail.dropFirst(), in: child, search: search, visited: &visited, used: &used, parent: owner)
        }
        return result
    }

    /// Each arm's sends, with a helper's arms prefixed by the arm that calls the helper — or, when the
    /// call passes the switched parameter nothing from its own pattern, credited to that arm whole.
    func armSends(of owner: String) -> [(arm: String, sent: String)] {
        (index.armSends[owner] ?? []).flatMap { entry -> [(arm: String, sent: String)] in
            guard let helper = entry.helper else { return [(entry.arm, entry.sent)] }

            return index.helperCalls
                .filter { $0.owner == owner && $0.func == helper }
                .map { (passesSwitchedValue($0) ? "\($0.action).\(entry.arm)" : $0.action, entry.sent) }
        }
    }

    /// `handleRowMenu(action, contact, state:)` from `.rowMenu(let action, let contact)` hands the
    /// helper the very value it switches over, so each helper arm is a longer action path. A call passing
    /// state (`choose(option: state.option)`) is not: the arm reaches whatever the helper assigns.
    func passesSwitchedValue(_ call: (owner: String, action: String, func: String, boundArguments: Set<String>)) -> Bool {
        index.helperSwitchParameters["\(call.owner)|\(call.func)"].map(call.boundArguments.contains) ?? false
    }

    func control(_ send: UISend, base: String) -> UIControl {
        UIControl(action: send.action, control: send.control, site: send.site, file: send.file.relative(to: base))
    }
}

/// How a reducer comes to hold a child.
enum ChildKind {

    /// An always-on child: `Scope`, or the element reducer of a `forEach`.
    case embed
    /// The row reducer of a generic list embedded as `property`.
    case row(of: String)
    /// A store the reducer's view makes for itself.
    case createdStore
    /// A presentation or stack slot, or one case of its enum.
    case slot
}

/// The sends a reducer's destinations are credited with.
struct SendUse {

    /// Offsets into the reducer's own sends.
    var own: Set<Int> = []
    /// Sends in another reducer's views.
    var foreign: Set<ForeignSend> = []
}

/// A send in `reducer`'s views that opens a destination of another reducer.
struct ForeignSend: Hashable {

    let reducer: String
    let control: UIControl
}

/// The feature a trigger search is for: its own sends are the ones `used` indexes.
private struct ControlSearch {

    let owner: String
    let sends: [UISend]
    let base: String
}

private extension Sequence where Element: Hashable & Comparable {

    func uniqueSorted() -> [Element] { Array(Set(self)).sorted() }
}
