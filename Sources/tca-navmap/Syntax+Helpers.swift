import SwiftSyntax

extension AttributeListSyntax {

    func contains(attribute name: String) -> Bool {
        contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name }
    }

    /// The attribute's argument text (`\.contactsService` for `@Dependency(\.contactsService)`), or nil
    /// when the attribute is absent.
    func argument(ofAttribute name: String) -> String? {
        lazy.compactMap { $0.as(AttributeSyntax.self) }
            .first { $0.attributeName.trimmedDescription == name }
            .map { $0.arguments?.trimmedDescription ?? "" }
    }
}

extension InheritanceClauseSyntax {

    func inherits(_ name: String) -> Bool {
        inheritedTypes.contains { $0.type.trimmedDescription == name }
    }
}

extension LabeledExprListSyntax {

    var firstStringLiteral: String? {
        lazy.compactMap { $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue }.first
    }
}

extension FunctionCallExprSyntax {

    var calleeName: String {
        if let reference = calledExpression.as(DeclReferenceExprSyntax.self) {
            reference.baseName.text
        } else if let member = calledExpression.as(MemberAccessExprSyntax.self) {
            member.declName.baseName.text
        } else if let generic = calledExpression.as(GenericSpecializationExprSyntax.self) {
            generic.expression.trimmedDescription
        } else {
            calledExpression.trimmedDescription
        }
    }

    /// `store` in `store.send(…)`.
    var memberBase: String? {
        calledExpression.as(MemberAccessExprSyntax.self)?.base?.trimmedDescription
    }

    /// The first reducer built inside a `Scope { Child() }` trailing closure.
    var childReducer: String? {
        guard let statement = trailingClosure?.statements.first?.item,
              let child = statement.as(ExprSyntax.self)?.as(FunctionCallExprSyntax.self) else { return nil }

        return child.calledExpression.trimmedDescription
    }
}

extension ClosureExprSyntax {

    /// `{ rowStore in … }` and `{ (rowStore: StoreOf<Row>) in … }` → ["rowStore"].
    var parameterNames: [String] {
        switch signature?.parameterClause {
        case .simpleInput(let parameters): parameters.map(\.name.text)
        case .parameterClause(let clause): clause.parameters.map { ($0.secondName ?? $0.firstName).text }
        case nil: []
        }
    }

    /// The call this closure is passed to, whether trailing, additional-trailing, or labelled.
    var owningCall: FunctionCallExprSyntax? {
        if let call = parent?.as(FunctionCallExprSyntax.self) {
            call
        } else if let element = parent?.as(MultipleTrailingClosureElementSyntax.self) {
            element.parent?.parent?.as(FunctionCallExprSyntax.self)
        } else if let argument = parent?.as(LabeledExprSyntax.self) {
            argument.parent?.parent?.as(FunctionCallExprSyntax.self)
        } else {
            nil
        }
    }
}

extension ExprSyntax {

    /// `ContactCell(…).padding().onTapGesture` → `ContactCell`.
    var rootViewName: String {
        var current = self
        while true {
            if let call = current.as(FunctionCallExprSyntax.self),
               let base = call.calledExpression.as(MemberAccessExprSyntax.self)?.base {
                current = base
            } else if let call = current.as(FunctionCallExprSyntax.self) {
                return call.calleeName
            } else if let base = current.as(MemberAccessExprSyntax.self)?.base {
                current = base
            } else {
                return current.trimmedDescription
            }
        }
    }

    /// `.destination(.presented(.detail(.back)))` → `destination.presented.detail.back`;
    /// `.openContact(let contact)` → `openContact`; `rowAction(action, for: x)` → `call:rowAction`.
    /// An element action follows its `action:` argument: `.items(.element(id: id, action: .tap))` →
    /// `items.element.tap`.
    var actionPath: String? {
        if let member = self.as(MemberAccessExprSyntax.self), member.base == nil {
            return member.declName.baseName.text
        } else if let call = self.as(FunctionCallExprSyntax.self),
                  let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base == nil {
            let head = member.declName.baseName.text
            let next = call.arguments.first { $0.label == nil } ?? call.arguments.first { $0.label?.text == "action" }
            if let tail = next?.expression.actionPath {
                return "\(head).\(tail)"
            } else {
                return head
            }
        } else if let reference = self.as(FunctionCallExprSyntax.self)?.calledExpression.as(DeclReferenceExprSyntax.self) {
            return "call:\(reference.baseName.text)"
        } else {
            return nil
        }
    }
}

extension PatternSyntax {

    /// `.openContact(let x)` and `let .openContact(x)` both match the expression `.openContact(…)`.
    var matchedExpression: ExprSyntax? {
        if let expression = self.as(ExpressionPatternSyntax.self)?.expression {
            expression
        } else if let binding = self.as(ValueBindingPatternSyntax.self) {
            binding.pattern.matchedExpression
        } else {
            nil
        }
    }
}

extension SyntaxProtocol {

    func descendants<T: SyntaxProtocol>(ofType type: T.Type) -> [T] {
        var found: [T] = []
        for child in children(viewMode: .sourceAccurate) {
            if let match = child.as(T.self) { found.append(match) }
            found.append(contentsOf: child.descendants(ofType: type))
        }
        return found
    }

    func isDescendant(of ancestor: Syntax) -> Bool {
        var current = parent
        while let node = current {
            if node.id == ancestor.id { return true }
            current = node.parent
        }
        return false
    }
}
