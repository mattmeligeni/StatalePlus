import Foundation

/// Sottoinsieme di selettori CSS usato dai parser:
/// `tag`, `*`, `#id`, `.classe`, `[attr]`, `[attr=v]`, `[attr^=v]`, `[attr*=v]`, `[attr$=v]`,
/// combinatori discendente (spazio) e figlio (`>`, anche iniziale: "> div"), gruppi con virgola.
nonisolated enum CSSSelector {
    private struct Compound {
        var tag: String?
        var id: String?
        var classes: [String] = []
        var attrs: [(name: String, op: String, value: String)] = []

        func matches(_ n: HTMLNode) -> Bool {
            guard n.kind == .element else { return false }
            if let tag, tag != "*", n.tag != tag { return false }
            if let id, n.attributes["id"] != id { return false }
            if !classes.isEmpty {
                let own = Set(n.classes.map(String.init))
                if !classes.allSatisfy(own.contains) { return false }
            }
            for a in attrs {
                guard let v = n.attributes[a.name] else { return false }
                switch a.op {
                case "=": if v != a.value { return false }
                case "^=": if !v.hasPrefix(a.value) { return false }
                case "*=": if !v.contains(a.value) { return false }
                case "$=": if !v.hasSuffix(a.value) { return false }
                default: break
                }
            }
            return true
        }
    }

    private enum Combinator { case descendant, child }
    private struct Step { let combinator: Combinator; let compound: Compound }

    static func select(_ selector: String, in context: HTMLNode) -> [HTMLNode] {
        let groups = split(selector)
        let all = context.descendants
        if groups.count == 1 { return all.filter { matches($0, steps: groups[0], context: context) } }
        return all.filter { el in groups.contains { matches(el, steps: $0, context: context) } }
    }

    // MARK: Matching (da destra a sinistra)

    private static func matches(_ el: HTMLNode, steps: [Step], context: HTMLNode) -> Bool {
        guard let last = steps.last, last.compound.matches(el) else { return false }
        return matchAncestors(el, steps: steps, index: steps.count - 1, context: context)
    }

    /// `steps[index]` è già soddisfatto da `el`; verifica i passi precedenti.
    private static func matchAncestors(_ el: HTMLNode, steps: [Step], index: Int, context: HTMLNode) -> Bool {
        let comb = steps[index].combinator
        if index == 0 {
            // selettore relativo "> x": il padre deve essere il contesto
            return comb == .child ? el.parent === context : true
        }
        let prev = steps[index - 1].compound
        switch comb {
        case .child:
            guard let p = el.parent, prev.matches(p) else { return false }
            return matchAncestors(p, steps: steps, index: index - 1, context: context)
        case .descendant:
            var p = el.parent
            while let a = p {
                if prev.matches(a), matchAncestors(a, steps: steps, index: index - 1, context: context) { return true }
                p = a.parent
            }
            return false
        }
    }

    // MARK: Parsing del selettore

    private static func split(_ selector: String) -> [[Step]] {
        var groups: [String] = []
        var depth = 0, cur = ""
        for ch in selector {
            if ch == "[" { depth += 1 } else if ch == "]" { depth -= 1 }
            if ch == ",", depth == 0 { groups.append(cur); cur = "" } else { cur.append(ch) }
        }
        groups.append(cur)
        return groups.map { parseGroup($0.trimmed) }
    }

    private static func parseGroup(_ s: String) -> [Step] {
        var steps: [Step] = []
        var pending: Combinator = .descendant
        var token = ""
        var depth = 0
        func flush() {
            guard !token.isEmpty else { return }
            steps.append(Step(combinator: pending, compound: parseCompound(token)))
            token = ""; pending = .descendant
        }
        for ch in s {
            if ch == "[" { depth += 1 }
            if ch == "]" { depth -= 1 }
            if depth == 0, ch == " " { flush(); continue }
            if depth == 0, ch == ">" { flush(); pending = .child; continue }
            token.append(ch)
        }
        flush()
        return steps
    }

    private static func parseCompound(_ s: String) -> Compound {
        var c = Compound()
        var i = s.startIndex
        func readName() -> String {
            var out = ""
            while i < s.endIndex, !"#.[".contains(s[i]) { out.append(s[i]); i = s.index(after: i) }
            return out
        }
        if i < s.endIndex, !"#.[".contains(s[i]) { c.tag = readName().lowercased() }
        while i < s.endIndex {
            let ch = s[i]
            i = s.index(after: i)
            switch ch {
            case "#": c.id = readName()
            case ".": c.classes.append(readName())
            case "[":
                guard let close = s[i...].firstIndex(of: "]") else { return c }
                let body = String(s[i..<close])
                i = s.index(after: close)
                if let r = body.range(of: #"[\^\*\$]?="#, options: .regularExpression) {
                    var v = String(body[r.upperBound...])
                    if v.count >= 2, let f = v.first, (f == "\"" || f == "'"), v.last == f { v = String(v.dropFirst().dropLast()) }
                    c.attrs.append((String(body[..<r.lowerBound]).lowercased(), String(body[r]), v))
                } else {
                    c.attrs.append((body.lowercased(), "", ""))
                }
            default: break
            }
        }
        return c
    }
}
