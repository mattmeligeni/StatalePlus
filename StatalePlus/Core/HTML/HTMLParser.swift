import Foundation

/// Parser HTML tollerante, sufficiente per le pagine di UNIMIA (Plumtree), SIFA (Wicket) e Moodle:
/// tag void, testo grezzo di script/style, chiusure implicite di p/li/tr/td/option, entità HTML.
nonisolated enum HTMLParser {
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
    ]
    private static let rawTextTags: Set<String> = ["script", "style", "textarea", "title"]
    private static let closesP: Set<String> = [
        "address", "article", "aside", "blockquote", "div", "dl", "fieldset", "footer", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hr", "main", "nav", "ol", "p", "pre", "section", "table", "ul",
    ]

    static func parse(_ html: String) -> HTMLNode {
        let b = Array(html.utf8)
        let n = b.count
        let root = HTMLNode(kind: .document)
        var stack: [HTMLNode] = [root]
        var i = 0

        func string(_ from: Int, _ to: Int) -> String { String(decoding: b[from..<to], as: UTF8.self) }
        func starts(_ s: String, at p: Int) -> Bool {
            let u = Array(s.utf8)
            guard p + u.count <= n else { return false }
            for k in 0..<u.count where lower(b[p + k]) != u[k] { return false }
            return true
        }
        func find(_ s: String, from p: Int) -> Int? {
            var q = p
            while q < n { if starts(s, at: q) { return q }; q += 1 }
            return nil
        }
        /// Chiude (pop) fino all'elemento `tag` compreso, senza superare i confini indicati.
        func close(_ tags: Set<String>, stopAt boundaries: Set<String>) {
            guard let idx = stack.lastIndex(where: { tags.contains($0.tag) || boundaries.contains($0.tag) }),
                  tags.contains(stack[idx].tag) else { return }
            stack.removeSubrange(idx...)
        }

        while i < n {
            if b[i] == UInt8(ascii: "<"), i + 1 < n {
                let next = b[i + 1]
                if starts("<!--", at: i) {
                    i = (find("-->", from: i + 4).map { $0 + 3 }) ?? n
                    continue
                }
                if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
                    i = (find(">", from: i).map { $0 + 1 }) ?? n
                    continue
                }
                if next == UInt8(ascii: "/") {
                    var j = i + 2
                    while j < n, isNameChar(b[j]) { j += 1 }
                    let name = string(i + 2, j).lowercased()
                    i = (find(">", from: j).map { $0 + 1 }) ?? n
                    if let idx = stack.lastIndex(where: { $0.tag == name }), idx > 0 { stack.removeSubrange(idx...) }
                    continue
                }
                if isLetter(next) {
                    var j = i + 1
                    while j < n, isNameChar(b[j]) { j += 1 }
                    let name = string(i + 1, j).lowercased()
                    var attrs: [String: String] = [:]
                    var selfClosing = false
                    // attributi
                    while j < n {
                        while j < n, isSpace(b[j]) { j += 1 }
                        guard j < n else { break }
                        if b[j] == UInt8(ascii: ">") { j += 1; break }
                        if b[j] == UInt8(ascii: "/") { selfClosing = true; j += 1; continue }
                        let ns = j
                        while j < n, !isSpace(b[j]), b[j] != UInt8(ascii: "="), b[j] != UInt8(ascii: ">"),
                              !(b[j] == UInt8(ascii: "/") && j + 1 < n && b[j + 1] == UInt8(ascii: ">")) { j += 1 }
                        let attrName = string(ns, j).lowercased()
                        while j < n, isSpace(b[j]) { j += 1 }
                        var value = ""
                        if j < n, b[j] == UInt8(ascii: "=") {
                            j += 1
                            while j < n, isSpace(b[j]) { j += 1 }
                            if j < n, b[j] == UInt8(ascii: "\"") || b[j] == UInt8(ascii: "'") {
                                let q = b[j]; let vs = j + 1
                                j = vs
                                while j < n, b[j] != q { j += 1 }
                                value = string(vs, j); j += 1
                            } else {
                                let vs = j
                                while j < n, !isSpace(b[j]), b[j] != UInt8(ascii: ">") { j += 1 }
                                value = string(vs, j)
                            }
                        }
                        if !attrName.isEmpty, attrs[attrName] == nil { attrs[attrName] = HTMLEntities.decode(value) }
                        if attrName.isEmpty { j += 1 }
                    }
                    i = j

                    // chiusure implicite
                    switch name {
                    case "li": close(["li"], stopAt: ["ul", "ol", "table", "div"])
                    case "tr": close(["tr", "td", "th"], stopAt: ["table", "thead", "tbody", "tfoot"])
                    case "td", "th": close(["td", "th"], stopAt: ["tr", "table"])
                    case "thead", "tbody", "tfoot": close(["thead", "tbody", "tfoot", "tr", "td", "th"], stopAt: ["table"])
                    case "option": close(["option"], stopAt: ["select", "datalist"])
                    case "dt", "dd": close(["dt", "dd"], stopAt: ["dl"])
                    default: if closesP.contains(name), stack.last?.tag == "p" { stack.removeLast() }
                    }

                    let el = HTMLNode(kind: .element, tag: name, attributes: attrs)
                    stack.last!.append(el)
                    if rawTextTags.contains(name) {
                        let end = find("</\(name)", from: i) ?? n
                        if name != "script" && name != "style" {
                            el.append(HTMLNode(kind: .text, text: HTMLEntities.decode(string(i, end))))
                        }
                        i = (find(">", from: end).map { $0 + 1 }) ?? n
                    } else if !selfClosing && !voidTags.contains(name) {
                        stack.append(el)
                    }
                    continue
                }
            }
            // testo
            var j = i + 1
            while j < n, b[j] != UInt8(ascii: "<") { j += 1 }
            stack.last!.append(HTMLNode(kind: .text, text: HTMLEntities.decode(string(i, j))))
            i = j
        }
        return root
    }

    private static func lower(_ c: UInt8) -> UInt8 { (c >= 65 && c <= 90) ? c + 32 : c }
    private static func isLetter(_ c: UInt8) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
    private static func isSpace(_ c: UInt8) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 || c == 12 }
    private static func isNameChar(_ c: UInt8) -> Bool {
        isLetter(c) || (c >= 48 && c <= 57) || c == UInt8(ascii: "-") || c == UInt8(ascii: ":") || c == UInt8(ascii: "_")
    }
}

nonisolated enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "agrave": "à", "aacute": "á", "egrave": "è", "eacute": "é", "igrave": "ì", "iacute": "í",
        "ograve": "ò", "oacute": "ó", "ugrave": "ù", "uacute": "ú",
        "Agrave": "À", "Aacute": "Á", "Egrave": "È", "Eacute": "É", "Igrave": "Ì", "Ograve": "Ò", "Ugrave": "Ù",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "ccedil": "ç", "ntilde": "ñ",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "laquo": "«", "raquo": "»",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·", "deg": "°", "ordm": "º", "ordf": "ª",
        "euro": "€", "copy": "©", "reg": "®", "trade": "™", "times": "×", "sect": "§", "shy": "",
    ]

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let body = s[s.index(after: i)..<semi]
                var rep: String?
                if body.hasPrefix("#x") || body.hasPrefix("#X") {
                    rep = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if body.hasPrefix("#") {
                    rep = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    rep = named[String(body)]
                }
                if let rep {
                    out += rep
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
