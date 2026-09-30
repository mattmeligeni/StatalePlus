import Foundation
import PDFKit

/// Obbligo di frequenza letto dal manifesto degli studi del corso.
nonisolated struct ObbligoFrequenza: Codable, Sendable, Hashable {
    let percentuale: Int      // "È richiesta una frequenza di almeno il 50% del monte ore…" → 50
    let url: URL              // PDF del manifesto
    let coorte: String        // "Immatricolati nell'Anno Accademico 2026/2027" → "2026/2027"

    var soglia: Double { Double(percentuale) / 100 }
}

/// Manifesti degli studi su apps.unimi.it (PDF pubblici, nessun cookie):
/// `ita_manifesto_{CODICE}of{N}_{anno di fine a.a.}.pdf`, es. `ita_manifesto_DBDof2_2027.pdf`.
/// Nello stesso anno accademico ogni `ofN` è una coorte diversa (DBD 2026/27: of1 = immatricolati 2025/26,
/// of2 = immatricolati 2026/27): si provano gli indici e si sceglie il manifesto della coorte dello studente.
actor ManifestoService {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    /// - Parameters:
    ///   - codiceCorso: "DBD"
    ///   - annoCorso: anno di corso dello studente (1, 2, …)
    ///   - inizioAnnoAccademico: 2026 per l'a.a. 2026/27
    func obbligoFrequenza(codiceCorso: String, annoCorso: Int, inizioAnnoAccademico: Int) async throws -> ObbligoFrequenza? {
        let codice = codiceCorso.trimmed.uppercased()
        guard !codice.isEmpty, codice.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        let inizioCoorte = inizioAnnoAccademico - max(annoCorso - 1, 0)
        var primo: ObbligoFrequenza?
        var trovati = 0
        for n in 1...6 {
            guard let url = URL(string: "https://apps.unimi.it/files/manifesti/ita_manifesto_\(codice)of\(n)_\(inizioAnnoAccademico + 1).pdf") else { continue }
            let r = try await http.get(url, headers: ["Accept": "application/pdf"])
            guard r.status == 200, r.isPDF else {
                if trovati > 0 { break }   // indici consecutivi: dopo il primo buco non ce ne sono altri
                continue
            }
            trovati += 1
            guard let letto = Self.leggi(r.data, url: url) else { continue }
            if letto.coorte.hasPrefix(String(inizioCoorte)) { return letto }
            primo = primo ?? letto
        }
        return primo
    }

    /// Estrae percentuale e coorte dal testo del PDF.
    static func leggi(_ pdf: Data, url: URL) -> ObbligoFrequenza? {
        guard let testo = PDFDocument(data: pdf)?.string else { return nil }
        let piatto = testo.collapsed
        guard let p = piatto.firstMatch(#"frequenza di almeno il\s*(\d{1,3})\s*%"#, options: .caseInsensitive).flatMap(Int.init),
              (1...100).contains(p) else { return nil }
        let coorte = piatto.firstMatch(#"Immatricolati nell['’]Anno Accademico\s*(\d{4}/\d{2,4})"#, options: .caseInsensitive) ?? ""
        return ObbligoFrequenza(percentuale: p, url: url, coorte: coorte)
    }
}
