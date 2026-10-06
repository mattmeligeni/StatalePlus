import Foundation

/// Nodo di un albero HTML costruito dal parser interno (nessuna dipendenza esterna).
nonisolated final class HTMLNode {
    enum Kind { case document, element, text }

    let kind: Kind
    let tag: String                       // minuscolo; "" per testo/documento
    let attributes: [String: String]      // nomi minuscoli
    private(set) var children: [HTMLNode] = []
    private(set) weak var parent: HTMLNode?
    let textValue: String                 // solo per i nodi di testo (entità già decodificate)

    init(kind: Kind, tag: String = "", attributes: [String: String] = [:], text: String = "") {
        self.kind = kind
        self.tag = tag
        self.attributes = attributes
        self.textValue = text
    }

    func append(_ child: HTMLNode) {
        child.parent = self
        children.append(child)
    }

    // MARK: Navigazione

    var elementChildren: [HTMLNode] { children.filter { $0.kind == .element } }
    var parentElement: HTMLNode? { parent?.kind == .element ? parent : nil }

    func attr(_ name: String) -> String { attributes[name] ?? "" }
    func hasAttr(_ name: String) -> Bool { attributes[name] != nil }
    var classes: [Substring] { attr("class").split(whereSeparator: \.isWhitespace) }

    /// Tutti gli elementi discendenti in ordine di documento (escluso self).
    var descendants: [HTMLNode] {
        var out: [HTMLNode] = []
        func walk(_ n: HTMLNode) {
            for c in n.children where c.kind == .element {
                out.append(c)
                walk(c)
            }
        }
        walk(self)
        return out
    }

    func element(id: String) -> HTMLNode? { descendants.first { $0.attributes["id"] == id } }

    func select(_ selector: String) -> [HTMLNode] { CSSSelector.select(selector, in: self) }
    func first(_ selector: String) -> HTMLNode? { select(selector).first }

    // MARK: Testo

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav",
        "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul", "option",
    ]

    /// Testo di tutti i discendenti con spazi collassati; spazio ai confini dei blocchi.
    var text: String {
        var out = ""
        func walk(_ n: HTMLNode) {
            for c in n.children {
                switch c.kind {
                case .text: out += c.textValue
                case .element:
                    let block = Self.blockTags.contains(c.tag)
                    if block { out += " " }
                    walk(c)
                    if block { out += " " }
                case .document: break
                }
            }
        }
        walk(self)
        return out.collapsed
    }

    /// Solo il testo figlio diretto.
    var ownText: String { children.filter { $0.kind == .text }.map(\.textValue).joined().collapsed }

    /// Testo leggibile con paragrafi ed elenchi puntati (descrizioni Moodle, post dei forum).
    var readableText: String {
        var out = ""
        func walk(_ n: HTMLNode) {
            for c in n.children {
                switch c.kind {
                case .text: out += c.textValue.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                case .element:
                    switch c.tag {
                    case "br": out += "\n"
                    case "li": out += "\n• "; walk(c); out += "\n"
                    default:
                        let block = Self.blockTags.contains(c.tag)
                        if block { out += "\n" }
                        walk(c)
                        if block { out += "\n" }
                    }
                case .document: break
                }
            }
        }
        walk(self)
        return out.components(separatedBy: "\n")
            .map { $0.collapsed }
            .reduce(into: [String]()) { acc, line in
                if line.isEmpty, acc.last?.isEmpty ?? true { return }
                acc.append(line)
            }
            .joined(separator: "\n")
            .trimmed
    }

    /// Come `readableText`, ma in Markdown inline: `**grassetto**` e `*corsivo*` da strong/b ed em/i, elenchi puntati
    /// senza righe vuote fra un punto e l'altro. Da mostrare con `Testo.markdown(_:)`.
    var readableMarkdown: String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: #"([\\*_\[\]`])"#, with: #"\\$1"#, options: .regularExpression)
        }
        func render(_ n: HTMLNode) -> String {
            var out = ""
            for c in n.children {
                switch c.kind {
                case .text:
                    out += esc(c.textValue.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
                case .element:
                    switch c.tag {
                    case "br": out += "\n"
                    case "script", "style": break
                    case "li": out += "\n• " + render(c).trimmed + "\n"
                    case "strong", "b", "em", "i":
                        let inner = render(c)
                        let t = inner.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty || t.contains("\n") {
                            out += inner
                        } else {
                            let m = (c.tag == "strong" || c.tag == "b") ? "**" : "*"
                            let lead = inner.hasPrefix(" ") ? " " : ""
                            let trail = inner.hasSuffix(" ") ? " " : ""
                            out += lead + m + t + m + trail
                        }
                    default:
                        let block = Self.blockTags.contains(c.tag)
                        if block { out += "\n" }
                        out += render(c)
                        if block { out += "\n" }
                    }
                case .document: break
                }
            }
            return out
        }
        let righe = render(self).components(separatedBy: "\n").map { $0.collapsed }
        var risultato: [String] = []
        for (i, riga) in righe.enumerated() {
            if riga.isEmpty {
                guard let ultima = risultato.last, !ultima.isEmpty else { continue }
                let prossima = righe[(i + 1)...].first { !$0.isEmpty }
                if ultima.hasPrefix("• "), prossima?.hasPrefix("• ") == true { continue }
            }
            risultato.append(riga)
        }
        return risultato.joined(separator: "\n").trimmed
    }
}
