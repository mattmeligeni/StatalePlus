import UIKit

/// PDF A4 del riassunto (da condividere, salvare in File o stampare): Markdown → HTML semplice → pagine con
/// `UIMarkupTextPrintFormatter`, margini da documento e intestazione con titolo, insegnamento e data.
enum PDFRiassunto {
    static func crea(markdown: String, titolo: String, sottotitolo: String) -> URL? {
        let html = """
            <html><head><meta charset="utf-8"><style>
            body { font-family: -apple-system, 'Helvetica Neue', sans-serif; font-size: 11pt; line-height: 1.45; color: #111; }
            h1 { font-size: 18pt; margin: 0 0 2pt 0; }
            .sotto { color: #666; font-size: 10pt; margin: 0 0 14pt 0; }
            h2 { font-size: 14pt; margin: 16pt 0 6pt 0; border-bottom: 1px solid #ddd; padding-bottom: 2pt; }
            h3 { font-size: 12pt; margin: 12pt 0 4pt 0; }
            p { margin: 0 0 8pt 0; text-align: justify; }
            li { margin-bottom: 4pt; }
            </style></head><body>
            <h1>\(escape(titolo))</h1><p class="sotto">\(escape(sottotitolo))</p>
            \(corpo(markdown))
            </body></html>
            """
        let renderer = PaginaA4()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        let dati = NSMutableData()
        UIGraphicsBeginPDFContextToData(dati, renderer.paperRect, [kCGPDFContextTitle as String: titolo])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let nome = "Riassunto – " + titolo.replacingOccurrences(of: #"[/:\\?%*|"<>]"#, with: "-", options: .regularExpression).prefix(80) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appending(path: String(nome))
        do { try (dati as Data).write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    private static func corpo(_ md: String) -> String {
        var html: [String] = []
        var lista: String?        // "ul" / "ol" aperta
        func chiudi() { if let l = lista { html.append("</\(l)>"); lista = nil } }
        for riga in md.components(separatedBy: "\n") {
            let r = riga.trimmingCharacters(in: .whitespaces)
            if r.hasPrefix("### ") { chiudi(); html.append("<h3>\(inline(String(r.dropFirst(4))))</h3>") }
            else if r.hasPrefix("## ") || r.hasPrefix("# ") { chiudi(); html.append("<h2>\(inline(r.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))</h2>") }
            else if r.hasPrefix("- ") || r.hasPrefix("* ") || r.hasPrefix("• ") {
                if lista != "ul" { chiudi(); html.append("<ul>"); lista = "ul" }
                html.append("<li>\(inline(String(r.dropFirst(2))))</li>")
            } else if let testo = r.firstMatch(#"^\d+[.)]\s+(.*)$"#) {
                if lista != "ol" { chiudi(); html.append("<ol>"); lista = "ol" }
                html.append("<li>\(inline(testo))</li>")
            } else if r.isEmpty { chiudi() }
            else { chiudi(); html.append("<p>\(inline(r))</p>") }
        }
        chiudi()
        return html.joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// **grassetto** e *corsivo*.
    private static func inline(_ s: String) -> String {
        escape(s)
            .replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\*)\*(?!\*)(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
    }
}

/// Pagina A4 (595 × 842 punti) con margini di 2 cm circa.
private nonisolated final class PaginaA4: UIPrintPageRenderer {
    private static let pagina = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    override var paperRect: CGRect { Self.pagina }
    override var printableRect: CGRect { Self.pagina.insetBy(dx: 56, dy: 56) }
}
