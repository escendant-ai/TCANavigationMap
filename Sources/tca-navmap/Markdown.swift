// Human/agent-readable rendering of a NavigationMap. The JSON beside it carries the same facts.

extension NavigationMap {

    /// The map as Markdown: entry path, a navigable tree, then one section per feature.
    var markdown: String {
        var out: [String] = []
        let byName = Dictionary(uniqueKeysWithValues: features.map { ($0.name, $0) })

        out.append("# Navigation map: \(root)")
        out.append("")
        out.append("> Generated from source by `tca-navmap` — do not edit by hand. Regenerate: `\(regenerate)`")
        out.append("")
        if !entryPath.isEmpty {
            let path = entryPath.map { step in step.via.map { "→ `\($0)` → **\(step.feature)**" } ?? "**\(step.feature)**" }
            out.append("**Reached from the app root:** " + path.joined(separator: " "))
            out.append("")
        }

        out.append("## Tree")
        out.append("")
        var expanded: Set<String> = []
        func tree(_ name: String, depth: Int) {
            guard let feature = byName[name] else { return }

            let indent = String(repeating: "  ", count: depth)
            for embed in feature.embeds {
                out.append("\(indent)- `\(embed.property)` embeds **\(embed.feature)**" + (byName[embed.feature]?.isExternal == true ? " (outside this map)" : ""))
                descend(embed.feature, depth: depth + 1)
            }
            for destination in feature.destinations {
                let label = destination.caseName.map { "\(destination.slot).\($0)" } ?? destination.slot
                let target = destination.feature.map { byName[$0]?.isExternal == true ? "**\($0)** (outside this map)" : "**\($0)**" }
                    ?? "`\(destination.type)`"
                let styles = destination.presentedAs.map(\.markdown).joined(separator: " / ")
                let via = destination.triggers.map { trigger in
                    let controls = trigger.controls.map(\.control).uniqued()
                    return controls.isEmpty ? "`.\(trigger.action)`" : "`.\(trigger.action)` ← " + controls.joined(separator: "; ")
                }
                var line = "\(indent)- `\(label)` → \(target)"
                if !styles.isEmpty { line += " · \(styles)" }
                if !via.isEmpty { line += " · via " + via.joined(separator: " | ") }
                out.append(line)
                if let child = destination.feature { descend(child, depth: depth + 1) }
            }
        }
        func descend(_ name: String, depth: Int) {
            guard let feature = byName[name], !feature.isExternal else { return }

            if expanded.contains(name) {
                out.append(String(repeating: "  ", count: depth) + "- ↺ see **\(name)** above")
                return
            }
            expanded.insert(name)
            tree(name, depth: depth)
        }
        out.append("- **\(root)**")
        expanded.insert(root)
        tree(root, depth: 1)
        for other in otherRoots where !expanded.contains(other) {
            out.append("- **\(other)** (a store of its own, outside \(root))")
            expanded.insert(other)
            tree(other, depth: 1)
        }
        out.append("")

        out.append("## Features")
        for feature in features {
            out.append("")
            out.append("### \(feature.name)")
            out.append("")
            if feature.isExternal { out.append("_Outside this map's boundary — its own destinations are listed, not expanded._") }
            out.append("- Reducer: `\(feature.file)`")
            if !feature.views.isEmpty { out.append("- Views: " + feature.views.map { "`\($0)`" }.joined(separator: ", ")) }
            if !feature.presentedBy.isEmpty { out.append("- Parents: " + feature.presentedBy.joined(separator: ", ")) }
            if !feature.screenNames.isEmpty { out.append("- Screen names: " + feature.screenNames.joined(separator: ", ")) }
            if !feature.accessibilityIdentifiers.isEmpty {
                out.append("- Accessibility identifiers: " + feature.accessibilityIdentifiers.map { "`\($0)`" }.joined(separator: ", "))
            }
            if !feature.serviceCalls.isEmpty { out.append("- Service calls: " + feature.serviceCalls.map { "`\($0)`" }.joined(separator: ", ")) }
            if !feature.delegatesSent.isEmpty { out.append("- Delegates sent to parent: " + feature.delegatesSent.map { "`\($0)`" }.joined(separator: ", ")) }

            if !feature.destinations.isEmpty {
                out.append("")
                out.append("| Destination | Opens | Presented as | Action | UI control |")
                out.append("|---|---|---|---|---|")
                for destination in feature.destinations {
                    let label = destination.caseName.map { "\(destination.slot).\($0)" } ?? destination.slot
                    let opens = destination.feature ?? "`\(destination.type)`"
                    let styles = destination.presentedAs.map(\.markdown).joined(separator: "<br>")
                    if destination.triggers.isEmpty {
                        out.append("| `\(label)` | \(opens) | \(styles) | — | — |")
                    }
                    for trigger in destination.triggers {
                        let controls = trigger.controls.map(\.markdownCell).joined(separator: "<br>")
                        out.append("| `\(label)` | \(opens) | \(styles) | `.\(trigger.action)` | \(controls.isEmpty ? "—" : controls) |")
                    }
                }
            }
            if !feature.otherUIActions.isEmpty {
                out.append("")
                out.append("| Other UI action | UI control |")
                out.append("|---|---|")
                for control in feature.otherUIActions {
                    out.append("| `.\(control.action)` | \(control.markdownCell) |")
                }
            }
        }
        if !unreachable.isEmpty {
            out.append("")
            out.append("## Not reachable from the app")
            out.append("")
            out.append("No user path presents or embeds these reducers.")
            out.append("")
            for feature in unreachable {
                out.append("- **\(feature.name)** (`\(feature.file)`)")
            }
        }
        out.append("")
        return out.joined(separator: "\n")
    }
}

private extension PresentedAs {

    var markdown: String {
        condition.map { "`\(style)` when `\($0)`" } ?? "`\(style)`"
    }
}

private extension UIControl {

    /// The control and the property it sits in, escaped for a Markdown table cell, then the child it
    /// sits in and the actions it passes through on the way: `Button "Remove" (`body`) in MemberDetail
    /// → `.removeMember``.
    var markdownCell: String {
        var text = control.replacingOccurrences(of: "|", with: "\\|") + (site.map { " (`\($0)`)" } ?? "")
        if let reducer { text += " in \(reducer)" }
        if let chain { text += " → " + chain.map { "`.\($0)`" }.joined(separator: " → ") }
        return text
    }
}

extension Array where Element: Hashable {

    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
