import Foundation

/// Parsing dei formati reali restituiti da UNIMIA, SIFA, Moodle e dalle API Agenda/EasyBadge.
nonisolated enum Formats {
    static let rome = TimeZone(identifier: "Europe/Rome")!

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

    static func time(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "it_IT"))) }
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
