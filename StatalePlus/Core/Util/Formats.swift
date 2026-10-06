import Foundation

/// Parsing dei formati reali restituiti da UNIMIA, SIFA, Moodle e dalle API Agenda/EasyBadge.
nonisolated enum Formats {
    static let rome = TimeZone(identifier: "Europe/Rome")!

    /// Lingua di tutte le date e i numeri mostrati, indipendente dalla lingua del dispositivo.
    static let it = Locale(identifier: "it_IT")

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = rome
        c.locale = Locale(identifier: "it_IT")
        c.firstWeekday = 2
        return c
    }()

    // DateFormatter è Sendable (thread-safe per parse/format); nessuna mutazione dopo l'init.
    private static let dmy = make("dd-MM-yyyy")
    private static let dmySlash = make("dd/MM/yyyy")
    private static let isoDay = make("yyyy-MM-dd")
    private static let sqlDateTime = make("yyyy-MM-dd HH:mm:ss")
    private static let isoOffset = make("yyyy-MM-dd'T'HH:mm:ssXXXXX")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = rome
        f.dateFormat = format
        return f
    }

    /// "28-09-2026" — Agenda XML `Giorno@Data`, esami `Data`, UNIMIA tasse "Data pagamento" ("11-09-2026 " con spazio).
    static func dayDMY(_ s: String) -> Date? { dmy.date(from: s.trimmed) }
    /// Parametri `datefrom`/`dateto` di test_call.php: "29-09-2026".
    static func dmyString(_ d: Date) -> String { dmy.string(from: d) }
    /// "02/02/2027" — messaggi tasse UNIMIA (gw6_219.html, #lista-messaggi).
    static func daySlash(_ s: String) -> Date? { dmySlash.date(from: s.trimmed) }
    /// "2026-12-07" — Agenda XML `GiornoFestivita@Giorno` (formato diverso dalle lezioni!).
    static func dayISO(_ s: String) -> Date? { isoDay.date(from: s.trimmed) }
    /// "2026-09-28 08:30:00" — EasyBadge timbrature.json `inizio`/`fine`/`Timestamp`.
    static func sqlDate(_ s: String) -> Date? { s.trimmed.isEmpty ? nil : sqlDateTime.date(from: s.trimmed) }
    /// "2026-09-21T16:49:05+02:00" — Moodle `time[datetime]` (course_14057__forum206891_disc91954.html).
    static func isoDate(_ s: String) -> Date? { isoOffset.date(from: s.trimmed) }

    /// Combina un giorno con "08:30" oppure "08:30:00" (EasyRoom `class@from`).
    static func at(_ day: Date, _ hhmm: String) -> Date? {
        let parts = hhmm.trimmed.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// "130 euro" / "1.234,56 euro" -> Decimal (UNIMIA gw6_219.html, colonne importo).
    static func euro(_ s: String) -> Decimal? {
        guard let r = s.range(of: #"-?[\d.]+(?:,\d+)?(?=\s*euro)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let normalized = s[r].replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func euroString(_ d: Decimal) -> String {
        d.formatted(.currency(code: "EUR").locale(Locale(identifier: "it_IT")))
    }

    /// Anno accademico corrente nel formato delle linguette Ariel "2026/27".
    static func currentAcademicYear(now: Date = .now) -> String {
        let c = calendar.dateComponents([.year, .month], from: now)
        let start = (c.month ?? 1) >= 8 ? (c.year ?? 2000) : (c.year ?? 2000) - 1
        return "\(start)/\(String(start + 1).suffix(2))"
    }

    /// Lunedì della settimana che contiene `d` (es. 7 ottobre 2026 → 5 ottobre 2026).
    static func inizioSettimana(_ d: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: d)?.start ?? calendar.startOfDay(for: d)
    }

    /// "5 – 11 ottobre 2026" / "28 settembre – 4 ottobre 2026".
    static func settimana(_ start: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let it = Locale(identifier: "it_IT")
        let stessoMese = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let a = stessoMese ? start.formatted(.dateTime.day().locale(it)) : start.formatted(.dateTime.day().month(.wide).locale(it))
        return "\(a) – \(end.formatted(.dateTime.day().month(.wide).year().locale(it)))"
    }

    /// "mer 30 settembre · 11:00"
    static func giornoEOra(_ d: Date) -> String {
        "\(d.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).locale(it))) · \(time(d))"
    }

    static func time(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "it_IT"))) }
}

// MARK: - Testi mostrati

nonisolated enum Testo {
    /// Markdown inline (grassetto, corsivo) conservando gli a capo.
    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    /// "mercoledì 30 settembre" → "Mercoledì 30 settembre" (solo la prima lettera).
    static func maiuscolaIniziale(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }

    /// "secondo trimestre" → "2° trimestre" (etichette dei periodi quando lo spazio è poco).
    static func periodoBreve(_ s: String) -> String {
        let ordinali = ["primo": "1°", "secondo": "2°", "terzo": "3°", "quarto": "4°"]
        let parti = s.lowercased().split(separator: " ", maxSplits: 1).map(String.init)
        guard parti.count == 2, let n = ordinali[parti[0]] else { return maiuscolaIniziale(s.lowercased()) }
        return "\(n) \(parti[1])"
    }

    /// "NEUROPSICOLOGIA CLINICA" → "Neuropsicologia clinica" (solo se il testo è tutto maiuscolo).
    static func frase(_ s: String) -> String {
        guard s == s.uppercased(), s != s.lowercased() else { return s }
        let l = s.lowercased()
        return l.prefix(1).uppercased() + l.dropFirst()
    }

    /// "DBD - NEUROPSICOLOGIA CLINICA E SPERIMENTALE (Classe LM-51 R) (CDS MAGISTRALE)"
    /// e "Neuropsicologia clinica e sperimentale (classe lm-51 r)" → "Neuropsicologia clinica e sperimentale · LM-51 R".
    static func nomeCorso(_ label: String) -> String {
        var s = label.collapsed
        s = s.replacingOccurrences(of: #"^[A-Z0-9]{2,6}\s+-\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\((CDS|CORSO|MASTER|SEMESTRE)[^)]*\)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let classe = s.firstMatch(#"\(\s*classe\s+([^)]+)\)"#, options: .caseInsensitive)?.trimmed.uppercased()
        s = s.replacingOccurrences(of: #"\s*\(\s*classe\s+[^)]+\)"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmed
        s = frase(s)
        return classe.map { "\(s) · \($0)" } ?? s
    }

    /// "ROSSI MARIO" → "Rossi Mario"; anche liste "A B, C D". L'ordine dei nomi resta quello della fonte.
    static func persona(_ s: String) -> String {
        s.split(separator: ",").map { parte in
            parte.split(separator: " ").map { String($0).lowercased().capitalized }.joined(separator: " ")
        }
        .joined(separator: ", ")
    }

    private static let particelle: Set<String> = ["di", "del", "della", "dei", "degli", "delle", "da", "dal", "dalla", "e", "in", "sul", "al", "alla", "ai"]

    private static func titolo(_ s: String) -> String {
        s.lowercased().split(separator: " ").enumerated().map { i, w in
            let w = String(w)
            return i > 0 && particelle.contains(w) ? w : w.capitalized
        }
        .joined(separator: " ")
    }

    /// "CONTRIB. REGIONE LOMBARDIA" → "Contributo Regione Lombardia",
    /// "IMP. DI BOLLO - RIMBORSO SPESE" → "Imposta di Bollo – Rimborso Spese".
    static func voceTassa(_ s: String) -> String {
        guard s == s.uppercased() else { return s }
        let estese = s.collapsed
            .replacingOccurrences(of: #"\bCONTRIB\."#, with: "CONTRIBUTO", options: .regularExpression)
            .replacingOccurrences(of: #"\bIMP\."#, with: "IMPOSTA", options: .regularExpression)
            .replacingOccurrences(of: " - ", with: " – ")
        return titolo(estese)
    }

    /// Grafia dei testi dei siti d'Ateneo: "E' possibile", "si puo' pagare", "Pago PA" → "È possibile", "si può pagare", "PagoPA".
    static func tipografia(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\bE'(?=\s)"#, with: "È", options: .regularExpression)
        let accenti: [(String, String)] = [("che", "ché"), ("a", "à"), ("e", "è"), ("i", "ì"), ("o", "ò"), ("u", "ù")]
        for (da, a) in accenti {
            t = t.replacingOccurrences(of: "(?<!')\\b(\\p{L}*)\(da)'(?![\\p{L}])", with: "$1\(a)", options: .regularExpression)
        }
        return t.replacingOccurrences(of: #"\bPago\s?PA\b"#, with: "PagoPA", options: .regularExpression)
    }

    /// EasyRoom: "Via Celoria, 2, Milano, 20133" → "Via Celoria 2, 20133 Milano".
    static func indirizzoSede(_ s: String) -> String {
        let p = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard p.count == 4, p[3].count == 5, p[3].allSatisfy(\.isNumber) else { return s }
        return "\(p[0]) \(p[1]), \(p[3]) \(p[2])"
    }

    /// "via mario rossi 10 20100 milano  MI italia" → "Via Mario Rossi 10, 20100 Milano (MI), Italia".
    static func indirizzo(_ s: String) -> String {
        let t = s.collapsed
        guard let re = try? NSRegularExpression(pattern: #"^(.*?)\s+(\d{5})\s+(.+?)\s+([A-Za-z]{2})\s+([A-Za-z ]+)$"#),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), m.numberOfRanges == 6 else {
            return titolo(t)
        }
        func g(_ i: Int) -> String { Range(m.range(at: i), in: t).map { String(t[$0]) } ?? "" }
        return "\(titolo(g(1))), \(g(2)) \(titolo(g(3))) (\(g(4).uppercased())), \(titolo(g(5)))"
    }
}

nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Collassa spazi/a capo multipli.
    var collapsed: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
    }
    func firstMatch(_ pattern: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              m.numberOfRanges > group, let r = Range(m.range(at: group), in: self) else { return nil }
        return String(self[r])
    }
    /// Normalizzazione per confrontare nomi di insegnamento fra sistemi con codici diversi
    /// (SIFA "DBD0A0", Agenda "DBD-28_1", appelli coorte precedente "DBD-9_1").
    var matchKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmed
    }
}

nonisolated extension Date {
    /// Come `formatted(date:time:)` ma sempre in italiano e nel fuso di Milano.
    func italiano(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: Formats.it, calendar: Formats.calendar, timeZone: Formats.rome))
    }

    /// "ieri", "la settimana scorsa", "tra 2 giorni"…
    var relativoItaliano: String {
        formatted(.relative(presentation: .named).locale(Formats.it))
    }
}
