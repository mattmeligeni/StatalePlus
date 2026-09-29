import Foundation

/// XML da GET `/EasyRoom/do.php`:
/// `<activities><offices><office name address><rooms><room id name capacity room_code/></rooms></office>…</offices>
///  <classes><class id from="08:00:00" to="18:00:00" office room faculty name teacher type/></classes></activities>`.
/// `<office>` non ha un `id`: la sede di un'occupazione si ricava da `class@room` → `<room id>` → `<office>` contenitore.
/// `<class>` non ha una data: è l'occupazione del giorno della richiesta.
nonisolated struct Sede: Sendable, Hashable, Identifiable {
    var id: String { nome }
    let nome: String        // office@name "Noto"
    let indirizzo: String   // office@address "via Noto, 8/10, Milano, 20141"
    let aule: [Aula]
}

nonisolated struct Aula: Sendable, Hashable, Identifiable {
    let id: String          // room@id "174"
    let nome: String        // room@name "Cono 2"
    let codice: String      // room@room_code "33230#4001" (= AulaCodice degli appelli)
    let capienza: Int?      // room@capacity "23"
    let sede: String        // office@name contenitore
    let indirizzo: String   // office@address contenitore
}

nonisolated struct Occupazione: Sendable, Hashable, Identifiable {
    let id: String          // class@id
    let dalle: String       // class@from "08:00:00"
    let alle: String        // class@to "18:00:00"
    let aulaId: String      // class@room "300"
    let nome: String        // class@name
    let docente: String     // class@teacher
    let tipo: String        // class@type "Lezione" / "Esame" / "Indisponibilità" / …

    func intervallo(on day: Date) -> ClosedRange<Date>? {
        guard let a = Formats.at(day, dalle), let b = Formats.at(day, alle), a <= b else { return nil }
        return a...b
    }
}

nonisolated struct OccupazioneAule: Sendable {
    let sedi: [Sede]
    let occupazioni: [Occupazione]
    let giorno: Date

    var aulePerId: [String: Aula] {
        Dictionary(sedi.flatMap(\.aule).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Codici aula confrontati ignorando il separatore: appelli "33230#4001", lezioni "9999981-Conf", EasyRoom "9999981@Conf".
    static func normalizza(_ codice: String) -> String {
        codice.lowercased().replacingOccurrences(of: #"[#@\-]"#, with: "#", options: .regularExpression)
    }

    /// Trova l'aula per codice, poi per nome aula + nome sede.
    func aula(codici: [String], nome: String, sede: String) -> Aula? {
        let all = sedi.flatMap(\.aule)
        let wanted = Set(codici.map(Self.normalizza).filter { !$0.isEmpty })
        if !wanted.isEmpty, let a = all.first(where: { wanted.contains(Self.normalizza($0.codice)) }) { return a }
        let n = nome.matchKey, s = sede.matchKey
        return all.first { $0.nome.matchKey == n && $0.sede.matchKey == s }
            ?? all.first { $0.nome.matchKey == n && ($0.sede.matchKey.contains(s) || s.contains($0.sede.matchKey)) }
    }

    func sede(nome: String) -> Sede? {
        let s = nome.matchKey
        return sedi.first { $0.nome.matchKey == s } ?? sedi.first { $0.nome.matchKey.contains(s) && !s.isEmpty }
    }
}
