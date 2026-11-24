import SwiftParser
import SwiftSyntax

extension GraphBuilder {

    /// Parses `sources` and collects every fact the graph needs: declarations first, so the second
    /// pass can attribute each fact to its reducer, then resolves what only the whole set can.
    init(sources: [(file: String, text: String)], configuration: Configuration) {
        let trees = sources.map { ($0.file, Parser.parse(source: $0.text)) }

        var index = Index()
        for (file, tree) in trees {
            let collector = DeclCollector(file: file, index: index)
            collector.walk(tree)
            index = collector.index
        }

        var dependencyVars: [String: [String: String]] = [:]
        var memberAccesses: [(owner: String, base: String, member: String)] = []
        var actionMappers: [String: [(item: String, action: String)]] = [:]
        var storeAliases: [String: (slot: String, caseName: String?)] = [:]
        var storeAliasUses: [(reducer: String, name: String, style: String, condition: String?, file: String)] = []
        for (file, tree) in trees {
            let collector = FactCollector(file: file, index: index, configuration: configuration)
            collector.walk(tree)
            index = collector.index
            dependencyVars.merge(collector.dependencyVars) { $0.merging($1) { first, _ in first } }
            memberAccesses += collector.memberAccesses
            actionMappers.merge(collector.actionMappers) { $0 + $1 }
            storeAliases.merge(collector.storeAliases) { first, _ in first }
            storeAliasUses += collector.storeAliasUses
        }

        for use in storeAliasUses {
            guard let alias = storeAliases["\(use.reducer)|\(use.name)"] else { continue }

            index.presentations.append(Presentation(reducer: use.reducer, hostPath: [], slot: alias.slot, caseName: alias.caseName, style: use.style, condition: use.condition, file: use.file))
        }

        self.init(index: index, actionMappers: actionMappers, configuration: configuration)

        for access in memberAccesses {
            guard let key = dependencyVars[access.owner]?[access.base] else { continue }

            serviceCalls[access.owner, default: []].insert("\(key).\(access.member)")
        }
    }
}
