import Foundation
import SwiftSyntax

// MARK: - Pass 1: declarations

/// Finds every `@Reducer` type and every View that holds a store, so pass 2 can attribute facts.
final class DeclCollector: SyntaxVisitor {

    var index: Index

    init(file: String, index: Index) {
        self.file = file
        self.index = index
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append(node.name.text)
        let name = stack.joined(separator: ".")
        if node.attributes.contains(attribute: "Reducer") {
            noteDuplicate(of: name)
            index.reducers[name] = ReducerDecl(
                name: name,
                isEnum: false,
                isGeneric: node.genericParameterClause != nil,
                file: file
            )
        }
        // A ViewModifier holding the store presents like a view (`PresentationsModifier`), and so does a
        // UIView(Controller)Representable that wraps a UIKit screen.
        let isView = node.inheritanceClause.map {
            $0.inherits("View")
                || $0.inherits("ViewModifier")
                || $0.inherits("UIViewRepresentable")
                || $0.inherits("UIViewControllerRepresentable")
        } ?? false
        if isView, let reducer = storeReducer(in: node.memberBlock) {
            index.views[node.name.text] = (reducer, file)
        }
        if isView {
            for member in node.memberBlock.members {
                for binding in member.decl.as(VariableDeclSyntax.self)?.bindings ?? [] {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }

                    index.viewMembers["\(node.name.text)|\(name)"] = (
                        binding.typeAnnotation?.type.trimmedDescription,
                        binding.accessorBlock?.trimmedDescription
                    )
                }
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) { stack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append(node.name.text)
        let name = stack.joined(separator: ".")
        if node.attributes.contains(attribute: "Reducer") {
            noteDuplicate(of: name)
            index.reducers[name] = ReducerDecl(
                name: name,
                isEnum: true,
                isGeneric: node.genericParameterClause != nil,
                file: file
            )
        }
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) { stack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) { stack.removeLast() }

    // MARK: - Private

    private let file: String
    private var stack: [String] = []
}

private extension DeclCollector {

    func storeReducer(in members: MemberBlockSyntax) -> String? {
        for member in members.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }

            for binding in variable.bindings {
                if let type = binding.typeAnnotation?.type.trimmedDescription, let reducer = type.storeReducer {
                    return reducer
                }
            }
        }
        return nil
    }
}

private extension DeclCollector {

    func noteDuplicate(of name: String) {
        guard let earlier = index.reducers[name] else { return }

        index.duplicateReducers[name, default: [earlier.file]].append(file)
    }
}

// MARK: - Pass 2: facts

final class FactCollector: SyntaxVisitor {

    var index: Index
    /// Owner reducer → `@Dependency` variable name → dependency key.
    var dependencyVars: [String: [String: String]] = [:]
    /// Raw `name.member` accesses, resolved against `dependencyVars` once every file is read.
    var memberAccesses: [(owner: String, base: String, member: String)] = []
    /// "UI owner|property" → the slot a computed store property scopes to (`var deleteAlertStore`).
    var storeAliases: [String: (slot: String, caseName: String?)] = [:]
    var storeAliasUses: [(reducer: String, name: String, style: String, condition: String?, file: String)] = []
    /// (UI owner, function) → the actions a mapping function like `rowAction(_:for:)` returns.
    var actionMappers: [String: [(item: String, action: String)]] = [:]

    init(file: String, index: Index, configuration: Configuration) {
        self.file = file
        self.index = index
        self.configuration = configuration
        super.init(viewMode: .sourceAccurate)
    }

    // Scope tracking

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) { stack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) { stack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) { stack.removeLast() }

    // State slots, dependencies

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if let ui = uiOwner(for: node) {
            for binding in node.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let accessor = binding.accessorBlock?.trimmedDescription,
                      let match = accessor.firstMatch(#"scope\(state:\s*\\\.\$?(\w+)[^)]*\)(?:\.(\w+))?"#) else { continue }

                storeAliases["\(ui)|\(name)"] = (match[1], match[2].isEmpty ? nil : match[2])
            }
        }
        guard let owner = reducerOwner else { return .visitChildren }

        let isInState = stack.last == "State"
        for binding in node.bindings {
            guard let property = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }

            let typeText = binding.typeAnnotation?.type.trimmedDescription ?? ""
            let initText = binding.initializer?.value.trimmedDescription ?? ""
            if isInState, node.attributes.contains(attribute: "Presents") {
                index.reducers[owner]?.presents.append((property, typeText.stateBaseType))
            }
            if isInState, let match = (typeText + " " + initText).firstMatch(#"StackState<([\w.]+)\.State>"#) {
                index.reducers[owner]?.stacks.append((property, match[1]))
            }
            if isInState, let match = typeText.firstMatch(#"^\[([\w.]+)\]$"#) {
                index.reducers[owner]?.arrays.append((property, match[1]))
            }
            if let dependency = node.attributes.argument(ofAttribute: "Dependency"),
               let key = dependency.firstMatch(#"\\\.(\w+)"#) {
                dependencyVars[owner, default: [:]][property] = key[1]
                index.dependencies[owner, default: []].insert(key[1])
            }
        }
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let owner = reducerOwner else { return .visitChildren }

        let qualified = stack.joined(separator: ".")
        for element in node.elements {
            guard let type = element.parameterClause?.parameters.first?.type.trimmedDescription else { continue }

            if qualified == owner, index.reducers[owner]?.isEnum == true {
                index.reducers[owner]?.cases.append((element.name.text, type))
            }
        }
        return .visitChildren
    }

    // Calls

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calleeName

        if let owner = reducerOwner {
            if ["Scope", "ifCaseLet", "ifLet", "forEach"].contains(callee), let child = node.childReducer {
                let keyPath = node.arguments.first?.expression.trimmedDescription ?? ""
                let property = keyPath.firstMatch(#"\\\.\$?(\w+)"#)?[1] ?? keyPath
                index.reducers[owner]?.scopes.append((property, child))
            }
            let firstArgument = node.arguments.first?.expression.trimmedDescription ?? ""
            if callee == "send", let delegate = firstArgument.firstMatch(#"^\.delegate\(\.(\w+)"#) {
                index.delegates[owner, default: []].insert(delegate[1])
            }
        }

        // `WebView(store: Store(initialState: …) { Web() })`, or a window the app delegate fills:
        // a store made outside any reducer tree, so what it runs is reachable only through here.
        if ["Store", "init"].contains(callee), node.arguments.first?.label?.text == "initialState",
           !isInPreview(Syntax(node)), let created = createdReducer(of: node),
           created != configuration.appRoot, !configuration.ignoredReducers.contains(created) {
            index.createdStores[uiOwner(for: node), default: []].insert(created)
        }

        if let ui = uiOwner(for: node) {
            if callee == "send", let base = node.memberBase, let argument = node.arguments.first?.expression {
                collectSend(node, base: base, argument: argument, ui: ui)
            } else if node.calledExpression.is(DeclReferenceExprSyntax.self) {
                collectHelperCallActions(node, ui: ui)
            }
            if callee == "navigationDestination" { collectPathDestinations(node, ui: ui) }
            if configuration.screenNameModifiers.contains(callee), let name = node.arguments.firstStringLiteral {
                index.screenNames[ui, default: []].insert(name)
            }
            if callee == "accessibilityIdentifier", let name = node.arguments.firstStringLiteral {
                index.accessibilityIDs[ui, default: []].insert(name)
            }
            for argument in node.arguments {
                let text = argument.expression.trimmedDescription
                // `.sheet(item: $store.scope(state: \.$destination, action: \.destination).profile)`
                // (`\.categoryPicker` without the `$` is the same slot.) A longer path reaches a child's
                // slot: `\.document.$destination` is `document`'s `destination`, drawn here. Only slots are
                // ever looked up, so non-presentation scopes such as `\.contacts.list` match harmlessly;
                // `\.destination?.picker` is the `scope` form handled below.
                if let match = text.firstMatch(#"scope\(state:\s*\\\.([\w.$]+)(?![\w.$?])[^)]*\)(?:\.(\w+))?"#) {
                    let components = match[1].split(separator: ".").map { $0.replacingOccurrences(of: "$", with: "") }
                    let hostPath = Array(components.dropLast())
                    addPresentation(
                        ui,
                        slot: components.last ?? match[1],
                        caseName: match[2].isEmpty ? nil : match[2],
                        style: hostPath.isEmpty ? callee : "\(callee) in \(ui)",
                        node: node,
                        hostPath: hostPath
                    )
                } else if let reference = argument.expression.as(DeclReferenceExprSyntax.self) {

                    // `.prompt(deleteAlertStore)` — resolved against the computed property later.
                    storeAliasUses.append((
                        reducer: ui,
                        name: reference.baseName.text,
                        style: callee,
                        condition: enclosingCondition(of: Syntax(node)),
                        file: file
                    ))
                }
                // `NavigationStack(path: $store.scope(state: \.path, action: \.path)) { … } destination: { … }`,
                // or a plain array bound directly: `NavigationStack(path: $store.steps)`.
                if callee == "NavigationStack",
                   let match = text.firstMatch(#"scope\(state:\s*\\\.(\w+),"#) ?? text.firstMatch(#"^\$(?:self\.)?store\.(\w+)$"#) {
                    addPresentation(ui, slot: match[1], caseName: "*", style: "NavigationStack push", node: node)
                }
            }
            // `if let child = store.scope(state: \.destination?.detail, …)` — rendered in place
            // (split-view detail column, embedded panel) rather than presented.
            // Passed straight to a modifier (`.sheet(item: $store.scope(state: \.destination?.picker, …))`,
            // or one of the app's own), the modifier is the presentation. A parent can also draw a child's
            // destination from its own store — `Main` puts `\.contacts.destination?.profile` in the
            // detail column beside its list — so the leading `contacts.` is kept as the path to the owner.
            if callee == "scope", let keyPath = node.arguments.first?.expression.trimmedDescription,
               let match = keyPath.firstMatch(#"^\\\.((?:\w+\.)*)(\w+)\?\.(\w+)$"#) {
                let argument = node.parent?.as(LabeledExprSyntax.self) ?? node.parent?.parent?.as(LabeledExprSyntax.self)
                let modifier = argument?.parent?.parent?.as(FunctionCallExprSyntax.self)
                let hostPath = match[1].split(separator: ".").map(String.init)
                let style = modifier.map(\.calleeName) ?? "inline"
                addPresentation(
                    ui,
                    slot: match[2],
                    caseName: match[3],
                    style: hostPath.isEmpty ? style : "\(style) in \(ui)",
                    node: modifier ?? node,
                    hostPath: hostPath
                )
            }
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let owner = reducerOwner, let base = node.base?.as(DeclReferenceExprSyntax.self) {
            memberAccesses.append((owner, base.baseName.text, node.declName.baseName.text))
        }
        return .visitChildren
    }

    // Switch arms: action → destination

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        guard !handledSwitches.contains(node.id), let owner = reducerOwner else { return .visitChildren }

        if let function = enclosingFunction(of: Syntax(node)), !takesWholeAction(function, owner: owner) {
            // A helper such as `handleRowMenu(_:_:state:)`: its arms are credited to whichever
            // action arm calls it, as `rowMenu.delete` — when that arm passes the
            // switched parameter a value from its own pattern (checked once the calls are known).
            // `switch notification.action` switches over no parameter, so its arms are not actions.
            if let parameter = switchedParameter(node, in: function) {
                index.helperSwitchParameters["\(owner)|\(function.name.text)"] = parameter
                collectArms(node, prefix: nil, owner: owner, helper: function.name.text)
            }
        } else if node.subject.trimmedDescription == "action" {
            collectArms(node, prefix: nil, owner: owner, helper: nil)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body?.trimmedDescription else { return .visitChildren }

        if let owner = reducerOwner {
            for assignment in body.slotAssignments {
                index.helperAssignments[owner, default: []].append((node.name.text, assignment.slot, assignment.caseName))
            }
        }
        if let returnType = node.signature.returnClause?.type.trimmedDescription, returnType.hasSuffix("Action"),
           let ui = uiOwner(for: node) {
            collectActionMapper(node, key: "\(ui)|\(node.name.text)")
        }
        return .visitChildren
    }

    // MARK: - Private

    private let file: String
    private let configuration: Configuration
    private var handledSwitches: Set<SyntaxIdentifier> = []
    private var stack: [String] = []
}

private extension FactCollector {

    /// Innermost enclosing type that is a reducer.
    var reducerOwner: String? {
        for count in stride(from: stack.count, through: 1, by: -1) {
            let name = stack.prefix(count).joined(separator: ".")
            if index.reducers[name] != nil { return name }
        }
        return nil
    }

    /// The reducer a view-side fact belongs to: the enclosing View's store, or a `StoreOf<R>` parameter.
    func uiOwner(for node: some SyntaxProtocol) -> String? {
        for name in stack.reversed() {
            if let view = index.views[name] { return view.reducer }
        }
        var current: Syntax? = Syntax(node)
        while let node = current {
            if let function = node.as(FunctionDeclSyntax.self) {
                for parameter in function.signature.parameterClause.parameters {
                    if let reducer = parameter.type.trimmedDescription.storeReducer { return reducer }
                }
            }
            current = node.parent
        }
        return nil
    }

    func enclosingFunction(of node: Syntax) -> FunctionDeclSyntax? {
        var current = node.parent
        while let node = current {
            if let function = node.as(FunctionDeclSyntax.self) { return function }
            current = node.parent
        }
        return nil
    }

    /// `func core(into state: inout State, action: Action)` is the reducer itself, not a helper.
    func takesWholeAction(_ function: FunctionDeclSyntax, owner: String) -> Bool {
        function.signature.parameterClause.parameters.contains {
            ["Action", "\(owner).Action"].contains($0.type.trimmedDescription)
        }
    }

    /// The parameter a helper's switch inspects, as its argument label or `#position`: `#0` for
    /// `switch action` in `handleRowMenu(_ action: …, …)`, `option` for `choose(option:state:)`.
    func switchedParameter(_ node: SwitchExprSyntax, in function: FunctionDeclSyntax) -> String? {
        guard let subject = node.subject.as(DeclReferenceExprSyntax.self)?.baseName.text else { return nil }

        for (position, parameter) in function.signature.parameterClause.parameters.enumerated()
        where (parameter.secondName ?? parameter.firstName).text == subject {
            return parameter.firstName.text == "_" ? "#\(position)" : parameter.firstName.text
        }
        return nil
    }

    /// Attributes each slot assignment to the innermost arm that makes it: an arm holding a nested
    /// `switch action { case .send: … }` gets its own assignments, and the nested arms get theirs as
    /// `outer.inner`, rather than the outer arm claiming every destination below it. A nested switch
    /// over anything but a value the arm's pattern binds (`switch result`, `switch state.tab`) is
    /// part of the arm's own body: its cases are not actions.
    func collectArms(_ node: SwitchExprSyntax, prefix: String?, owner: String, helper: String?) {
        handledSwitches.insert(node.id)
        for element in node.cases {
            guard let arm = element.as(SwitchCaseSyntax.self), case .case(let label) = arm.label else { continue }

            let bound = Set(label.caseItems.flatMap { $0.pattern.descendants(ofType: IdentifierPatternSyntax.self) }.map(\.identifier.text))
            let found = arm.statements.descendants(ofType: SwitchExprSyntax.self)
            let nested = found
                .filter { candidate in !found.contains { Syntax(candidate).isDescendant(of: Syntax($0)) } }
                .filter { bound.contains($0.subject.as(DeclReferenceExprSyntax.self)?.baseName.text ?? "") }
            for inner in found where !nested.contains(where: { $0.id == inner.id || Syntax(inner).isDescendant(of: Syntax($0)) }) {
                handledSwitches.insert(inner.id)
            }
            var body = arm.statements.trimmedDescription
            for inner in nested { body = body.replacingOccurrences(of: inner.trimmedDescription, with: "") }
            for item in label.caseItems {
                guard let expression = item.pattern.matchedExpression, let action = expression.actionPath else { continue }

                let path = prefix.map { "\($0).\(action)" } ?? action
                for sent in sentActions(in: arm, excluding: nested) {
                    index.armSends[owner, default: []].append((arm: path, sent: sent, helper: helper))
                }
                for assignment in body.slotAssignments {
                    if let helper {
                        index.helperArms["\(owner)|\(helper)", default: []].append((path, assignment.slot, assignment.caseName))
                    } else {
                        index.triggers.append(Trigger(
                            owner: owner,
                            action: path,
                            slot: assignment.slot,
                            caseName: assignment.caseName,
                            subCase: assignment.subCase
                        ))
                    }
                }
                if helper == nil {
                    for call in helperCalls(in: arm, excluding: nested) {
                        let passed = call.arguments.enumerated().compactMap { position, argument -> String? in
                            guard let name = argument.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                                  bound.contains(name) else { return nil }

                            return argument.label?.text ?? "#\(position)"
                        }
                        index.helperCalls.append((owner, path, call.calleeName, Set(passed)))
                    }
                }
                for inner in nested { collectArms(inner, prefix: path, owner: owner, helper: helper) }
            }
        }
    }

    /// A view's `store.send(…)`. The action can arrive as a helper's parameter or a view's property,
    /// `store.send(action)`, to be joined with the call sites that hand it over; the store can be one
    /// other than the view's own, `childStore.send(.back)`, to be resolved to its reducer once
    /// the graph exists.
    func collectSend(_ node: FunctionCallExprSyntax, base: String, argument: ExprSyntax, ui: String) {
        let (control, site) = describeTrigger(of: Syntax(node))
        let action = argument.actionPath ?? argument.trimmedDescription
        let send = UISend(reducer: ui, action: action, control: control, site: site, file: file)
        guard ["store", "self.store", "store.wrappedValue"].contains(base) else {
            if base.firstMatch(#"^\w+$"#) != nil, let origin = storeOrigin(named: base, from: Syntax(node)) {
                var hosted = send
                hosted.host = ui
                index.foreignSends.append((origin, hosted))
            }
            return
        }

        if let name = argument.as(DeclReferenceExprSyntax.self)?.baseName.text {
            if let function = enclosingFunction(of: Syntax(node)),
               let parameter = function.signature.parameterClause.parameters.first(where: { ($0.secondName ?? $0.firstName).text == name }) {
                index.parameterSends["\(ui)|\(function.name.text)|\(parameter.firstName.text)"] = send
                return
            }
            // `PromptView(…, action: .openSettings, …)` sending its `action` property.
            if let type = enclosingTypeName(of: Syntax(node)), index.viewMembers["\(type)|\(name)"] != nil {
                index.parameterSends["\(ui)|\(type)|\(name)"] = send
                return
            }
        }
        index.sends.append(send)
    }

    /// `exportMenuItem(title: "PDF", …, action: .showExport)`: an action handed to a
    /// view helper, named by the call site's own label.
    func collectHelperCallActions(_ node: FunctionCallExprSyntax, ui: String) {
        let callee = node.calleeName
        for argument in node.arguments {
            guard let label = argument.label?.text, let action = argument.expression.actionPath, !action.hasPrefix("call:") else { continue }

            let shown = controlLabel(node, excluding: Syntax(node.calledExpression)).map { "\(callee) \"\($0)\"" } ?? callee
            let (_, site) = describeTrigger(of: Syntax(node))
            index.helperCallActions.append((key: "\(ui)|\(callee)|\(label)", action: action, control: shown, site: site, file: file))
        }
    }

    /// `.navigationDestination(for: Main.Step.self) { step in switch step { case .signIn(.initial): SignInView(…) } }`.
    func collectPathDestinations(_ node: FunctionCallExprSyntax, ui: String) {
        guard let forArgument = node.arguments.first(where: { $0.label?.text == "for" }),
              let elementType = forArgument.expression.trimmedDescription.firstMatch(#"^([\w.]+)\.self$"#)?[1],
              let switchExpr = node.trailingClosure?.statements.descendants(ofType: SwitchExprSyntax.self).first else { return }

        for element in switchExpr.cases {
            guard let arm = element.as(SwitchCaseSyntax.self), case .case(let label) = arm.label else { continue }

            let view = arm.statements.descendants(ofType: FunctionCallExprSyntax.self)
                .first { $0.calleeName.first?.isUppercase == true }?
                .calleeName
            let scoped = arm.statements.trimmedDescription.firstMatch(#"scope\(state:\s*\\\.(\w+)"#)?[1]
            for item in label.caseItems {
                guard let caseName = item.pattern.matchedExpression?.actionPath else { continue }

                index.pathDestinations.append(PathDestination(
                    reducer: ui,
                    elementType: elementType,
                    caseName: caseName,
                    view: view,
                    scopedProperty: scoped
                ))
            }
        }
    }

    /// The view a node sits in, through an extension of it too.
    func enclosingTypeName(of node: Syntax) -> String? {
        var current = node.parent
        while let ancestor = current {
            if let type = ancestor.as(StructDeclSyntax.self) { return type.name.text }
            if let type = ancestor.as(ExtensionDeclSyntax.self) { return type.extendedType.trimmedDescription }
            current = ancestor.parent
        }
        return nil
    }

    /// Where a store named `name` comes from: a closure parameter of a scoping call, an `if let`
    /// binding, a local, a function parameter, or a property of the enclosing view.
    func storeOrigin(named name: String, from node: Syntax) -> StoreOrigin? {
        var current = node.parent
        while let ancestor = current {
            if let closure = ancestor.as(ClosureExprSyntax.self), closure.parameterNames.contains(name), let call = closure.owningCall {
                let text = call.trimmedDescription.replacingOccurrences(of: closure.trimmedDescription, with: "")
                return scopedOrigin(in: text)
            }
            if let ifExpr = ancestor.as(IfExprSyntax.self) {
                for condition in ifExpr.conditions {
                    if let binding = condition.condition.as(OptionalBindingConditionSyntax.self),
                       binding.pattern.trimmedDescription == name, let value = binding.initializer?.value.trimmedDescription {
                        return scopedOrigin(in: value)
                    }
                }
            }
            if let items = ancestor.as(CodeBlockItemListSyntax.self) {
                for item in items {
                    for binding in item.item.as(VariableDeclSyntax.self)?.bindings ?? [] where binding.pattern.trimmedDescription == name {
                        if let reducer = binding.typeAnnotation?.type.trimmedDescription.storeReducer { return .type(reducer) }
                        if let value = binding.initializer?.value.trimmedDescription { return scopedOrigin(in: value) }
                    }
                }
            }
            if let function = ancestor.as(FunctionDeclSyntax.self),
               let parameter = function.signature.parameterClause.parameters.first(where: { ($0.secondName ?? $0.firstName).text == name }),
               let reducer = parameter.type.trimmedDescription.storeReducer {
                return .type(reducer)
            }
            let typeName = ancestor.as(StructDeclSyntax.self)?.name.text ?? ancestor.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription
            if let typeName {
                guard let member = index.viewMembers["\(typeName)|\(name)"] else { return nil }

                if let reducer = member.type?.storeReducer { return .type(reducer) }
                return member.accessor.flatMap(scopedOrigin(in:))
            }
            current = ancestor.parent
        }
        return nil
    }

    /// `store.scope(state: \.$destination, action: \.destination).picker` or
    /// `store.scope(state: \.destination?.picker, …)` → the path and case; `\.items` → the path.
    func scopedOrigin(in text: String) -> StoreOrigin? {
        let actionPath = text.firstMatch(#"scope\(state:[^)]*action:\s*\\\.([\w.]+)"#)?[1].split(separator: ".").map(String.init) ?? []
        if let match = text.firstMatch(#"scope\(state:\s*\\\.((?:\w+\.)*)(\w+)\?\.(\w+)"#) {
            let path = match[1].split(separator: ".").map(String.init) + [match[2]]
            return .scoped(path: path, caseName: match[3], actionPath: actionPath)
        }
        if let match = text.firstMatch(#"scope\(state:\s*\\\.([\w.$]+)(?![\w.$?])[^)]*\)(?:\.(\w+))?"#) {
            let path = match[1].split(separator: ".").map { $0.replacingOccurrences(of: "$", with: "") }
            return .scoped(path: path, caseName: match[2].nilIfEmpty, actionPath: actionPath)
        }
        return nil
    }

    /// `Store(initialState: …) { Web() }` or `.init(initialState: …, reducer: { Overlay(…).logging() })`
    /// → the reducer at the root of the closure's expression.
    func createdReducer(of call: FunctionCallExprSyntax) -> String? {
        let closure = call.trailingClosure ?? call.arguments.first { $0.label?.text == "reducer" }?.expression.as(ClosureExprSyntax.self)
        guard let expression = closure?.statements.first?.item.as(ExprSyntax.self) else { return nil }

        let name = expression.rootViewName
        return name.first?.isUppercase == true ? name : nil
    }

    /// Inside `#Preview { … }` or a `PreviewProvider`: a fixture, not a place in the app.
    func isInPreview(_ node: Syntax) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if ancestor.as(MacroExpansionExprSyntax.self)?.macroName.text == "Preview"
                || ancestor.as(MacroExpansionDeclSyntax.self)?.macroName.text == "Preview"
                || ancestor.as(StructDeclSyntax.self)?.inheritanceClause?.inherits("PreviewProvider") == true {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    /// Calls to the reducer's own helpers in an arm: `handleRowMenu(action, contact, state: &state)`.
    func helperCalls(in arm: SwitchCaseSyntax, excluding nested: [SwitchExprSyntax]) -> [FunctionCallExprSyntax] {
        arm.statements.descendants(ofType: FunctionCallExprSyntax.self).filter { call in
            let isOwn = call.calledExpression.is(DeclReferenceExprSyntax.self)
                || ["self", "Self"].contains(call.calledExpression.as(MemberAccessExprSyntax.self)?.base?.trimmedDescription ?? "")
            return isOwn && !nested.contains { call.isDescendant(of: Syntax($0)) }
        }
    }

    /// Actions an arm sends on: `return .send(.showExport)`, `await send(.delegate(.didSave))`.
    func sentActions(in arm: SwitchCaseSyntax, excluding nested: [SwitchExprSyntax]) -> [String] {
        arm.statements.descendants(ofType: FunctionCallExprSyntax.self)
            .filter { call in call.calleeName == "send" && !nested.contains { call.isDescendant(of: Syntax($0)) } }
            .compactMap { $0.arguments.first?.expression.actionPath }
            .filter { !$0.hasPrefix("call:") }
    }

    func collectActionMapper(_ function: FunctionDeclSyntax, key: String) {
        guard let body = function.body else { return }

        for switchExpr in body.descendants(ofType: SwitchExprSyntax.self) {
            for element in switchExpr.cases {
                guard let arm = element.as(SwitchCaseSyntax.self), case .case(let label) = arm.label,
                      let statement = arm.statements.first?.item else { continue }

                var result = Syntax(statement)
                if let returned = statement.as(ReturnStmtSyntax.self)?.expression { result = Syntax(returned) }
                guard let resultExpr = result.as(ExprSyntax.self), let action = resultExpr.actionPath else { continue }

                for item in label.caseItems {
                    let itemName = item.pattern.trimmedDescription.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    actionMappers[key, default: []].append((itemName, action))
                }
            }
        }
    }

    // Helpers

    /// Walks up from a `store.send` to what the user touches: the closure's owning call, and the
    /// computed property or function it sits in.
    func describeTrigger(of node: Syntax) -> (String, String?) {
        // Two levels reads as "RowMenu in .contextMenu on ContactCell"; more is noise.
        var controls: [String] = []
        var site: String?
        var current = node.parent
        while let node = current {
            if controls.count < 2, let closure = node.as(ClosureExprSyntax.self), let call = closure.owningCall {
                let label = closure.parent?.as(LabeledExprSyntax.self)?.label?.text
                var control: String
                if let label, let title = pairedTitle(of: label, in: call) {
                    // `Panel(actionTitle: "Save", …, secondaryTitle: "Discard",
                    // secondaryAction: { … })` — the closure's own title, not the first literal.
                    control = "\(call.calleeName) \"\(title)\""
                } else {
                    control = describeControl(call, excluding: Syntax(closure))
                }
                // `ContactCell(…, onTapAvatar: { … })` — the argument names the tap target.
                if let label, label != "action" { control += " \(label):" }
                controls.append(control)
            }
            if let binding = node.as(PatternBindingSyntax.self) {
                site = binding.pattern.trimmedDescription
                break
            }
            if let function = node.as(FunctionDeclSyntax.self) {
                site = function.name.text
                break
            }
            current = node.parent
        }
        return (controls.isEmpty ? "direct" : controls.joined(separator: " in "), site)
    }

    func addPresentation(
        _ reducer: String,
        slot: String,
        caseName: String?,
        style: String,
        node: FunctionCallExprSyntax,
        hostPath: [String] = []
    ) {
        index.presentations.append(Presentation(
            reducer: reducer,
            hostPath: hostPath,
            slot: slot,
            caseName: caseName,
            style: style,
            condition: enclosingCondition(of: Syntax(node)),
            file: file
        ))
    }

    func describeControl(_ call: FunctionCallExprSyntax, excluding closure: Syntax) -> String {
        let name = call.calleeName
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base {
            // A modifier such as `.onTapGesture` — name the view it is attached to.
            return ".\(name) on \(base.rootViewName)"
        }
        // `primaryAction: .init("Save") { … }` — the argument label says more than `init`.
        let shown = name == "init" ? (argumentLabel(above: Syntax(call)) ?? name) : name
        return controlLabel(call, excluding: closure).map { "\(shown) \"\($0)\"" } ?? shown
    }

    /// `secondaryAction:` pairs with `secondaryTitle:`, `action:` with `actionTitle:` or `title:`.
    func pairedTitle(of label: String, in call: FunctionCallExprSyntax) -> String? {
        guard label.lowercased().hasSuffix("action") else { return nil }

        let prefix = String(label.dropLast("action".count))
        let candidates = prefix.isEmpty ? ["actionTitle", "title"] : ["\(prefix)Title"]
        for candidate in candidates {
            if let argument = call.arguments.first(where: { $0.label?.text == candidate }),
               let literal = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
                return literal
            }
        }
        return nil
    }

    /// The label of the argument an expression is passed as, looking through `cond ? x : nil`.
    func argumentLabel(above node: Syntax) -> String? {
        var current = node.parent
        for _ in 0..<4 {
            guard let node = current else { return nil }

            if let argument = node.as(LabeledExprSyntax.self) { return argument.label?.text }
            current = node.parent
        }
        return nil
    }

    /// The words the user reads on a control: a title-like argument, else its `Text`, else the first
    /// literal that is not an icon name (`Image("search")` is not the button's label).
    func controlLabel(_ call: FunctionCallExprSyntax, excluding closure: Syntax) -> String? {
        for argument in call.arguments where ["title", "buttonTitle", "label"].contains(argument.label?.text ?? "") {
            if let literal = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue { return literal }
        }
        let calls = call.descendants(ofType: FunctionCallExprSyntax.self).filter { !$0.isDescendant(of: closure) }
        if let text = calls.first(where: { $0.calleeName == "Text" }), let literal = text.arguments.firstStringLiteral {
            return literal
        }
        let iconCalls: Set<String> = ["ImageView", "Image", "Icon", "systemImage"]
        return call.descendants(ofType: StringLiteralExprSyntax.self)
            .filter { !$0.isDescendant(of: closure) }
            .first { literal in
                let owner = literal.parent?.parent?.parent?.as(FunctionCallExprSyntax.self)
                let label = literal.parent?.as(LabeledExprSyntax.self)?.label?.text
                return !(owner.map { iconCalls.contains($0.calleeName) } ?? false) && label != "systemImage"
            }?
            .representedLiteralValue
    }

    /// A conditional modifier wrapped around a presentation modifier: `.if(cond) { … } else: { … }`.
    func enclosingCondition(of node: Syntax) -> String? {
        var current = node.parent
        while let node = current {
            if let closure = node.as(ClosureExprSyntax.self), let call = closure.owningCall, configuration.conditionModifiers.contains(call.calleeName),
               let condition = call.arguments.first?.expression.trimmedDescription {
                let isElse = closure.parent?.as(MultipleTrailingClosureElementSyntax.self)?.label.text == "else"
                return isElse ? "!(\(condition))" : condition
            }
            current = node.parent
        }
        return nil
    }
}
