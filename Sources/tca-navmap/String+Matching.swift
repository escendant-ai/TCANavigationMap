import Foundation

extension String {

    /// `StoreOf<Contacts>`, `Bindable<StoreOf<Contacts>>`, `Store<Contacts.State, Contacts.Action>` → `Contacts`.
    var storeReducer: String? {
        firstMatch(#"StoreOf<([\w.]+)>"#)?[1] ?? firstMatch(#"Store<([\w.]+)\.State,"#)?[1]
    }

    /// `Destination.State?` → `Destination`; `AlertState<Action.Alert>?` stays as written.
    var stateBaseType: String {
        var type = self
        if type.hasSuffix("?") { type.removeLast() }
        if type.hasSuffix(".State") { type.removeLast(".State".count) }
        return type
    }

    /// `Prompt<Contact>` → `Prompt`.
    var genericBase: String {
        String(prefix { $0 != "<" })
    }

    /// `PagedList<Row<Contact>, ContactFilter>` → ["Row<Contact>", "ContactFilter"].
    var typeArguments: [String] {
        guard let open = firstIndex(of: "<"), let close = lastIndex(of: ">"), open < close else { return [] }

        return String(self[index(after: open)..<close]).topLevelElements(brackets: "<([{", ">)]}")
    }

    /// Slot assignments in a reducer body: `state.destination = .profile(…)` → (destination, profile),
    /// `state.path.append(.detail(…))` → (path, detail), and `state.editor = Editor.State(…)`
    /// → (editor, init) for a struct-typed slot. A plain-array path can be replaced outright,
    /// `state.steps = [.welcome, .signIn(.initial)]`, or extended, `state.steps += [.signIn(.code(…))]`,
    /// which yields each element; `subCase` is the payload's own case where it is one (`initial`).
    var slotAssignments: [(slot: String, caseName: String, subCase: String?)] {
        let assigned = matches(#"state\.(\w+)\s*=\s*\.(\w+)\b(?:\(\.(\w+))?"#).map { ($0[1], $0[2], $0[3].nilIfEmpty) }
            .filter { $0.1 != "none" }
        let replaced = matches(#"state\.(\w+)\s*\+?=\s*\[([^\]\n]*)\]"#).flatMap { match in
            match[2].topLevelElements().compactMap { element in
                element.firstMatch(#"^\.(\w+)\b(?:\(\.(\w+))?"#).map { (match[1], $0[1], $0[2].nilIfEmpty) }
            }
        }
        return assigned
            + matches(#"state\.(\w+)\s*=\s*[A-Z][\w.]*\("#).map { ($0[1], "init", nil) }
            + matches(#"state\.(\w+)\.append\(\.(\w+)\b(?:\(\.(\w+))?"#).map { ($0[1], $0[2], $0[3].nilIfEmpty) }
            + replaced
    }

    /// `.welcome, .signIn(.initial)` → [".welcome", ".signIn(.initial)"]: split on commas
    /// outside brackets.
    func topLevelElements(brackets opening: String = "([{", _ closing: String = ")]}") -> [String] {
        var elements: [String] = []
        var current = ""
        var depth = 0
        for character in self {
            if opening.contains(character) { depth += 1 }
            if closing.contains(character) { depth -= 1 }
            if character == ",", depth == 0 {
                elements.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        elements.append(current.trimmingCharacters(in: .whitespaces))
        return elements.filter { !$0.isEmpty }
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// Every match of `pattern`, each as [whole match, group 1, group 2, …] ("" for an unmatched group).
    func matches(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return regex.matches(in: self, range: NSRange(startIndex..., in: self)).map { result in
            (0..<result.numberOfRanges).map { group in
                Range(result.range(at: group), in: self).map { String(self[$0]) } ?? ""
            }
        }
    }

    func firstMatch(_ pattern: String) -> [String]? {
        matches(pattern).first
    }

    /// This path relative to `base`, or unchanged when it lies outside it.
    func relative(to base: String) -> String {
        hasPrefix(base + "/") ? String(dropFirst(base.count + 1)) : self
    }
}
