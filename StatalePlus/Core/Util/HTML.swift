import Foundation

/// Utilità comuni sopra il parser HTML interno.
nonisolated enum HTML {
    static func parse(_ html: String) -> HTMLNode { HTMLParser.parse(html) }

    static func text(_ el: HTMLNode?) -> String { el?.text ?? "" }

    static func readableText(_ el: HTMLNode?) -> String { el?.readableText ?? "" }

    static func readableMarkdown(_ el: HTMLNode?) -> String { el?.readableMarkdown ?? "" }

    /// Coppie `<li><label>Chiave: </label>Valore</li>` (UNIMIA, blocchi #div_studente / #div_anagrafica).
    static func labelPairs(in container: HTMLNode?) -> [String: String] {
        guard let container else { return [:] }
        var out: [String: String] = [:]
        for li in container.select("li") {
            guard let label = li.first("label") else { continue }
            let labelText = label.text
            let key = labelText.trimmingCharacters(in: CharacterSet(charactersIn: ": ")).trimmed
            let full = li.text
            let value = full.hasPrefix(labelText) ? String(full.dropFirst(labelText.count)).trimmed : full
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    static func absoluteURL(_ href: String, base: URL) -> URL? {
        URL(string: href, relativeTo: base)?.absoluteURL
    }
}
