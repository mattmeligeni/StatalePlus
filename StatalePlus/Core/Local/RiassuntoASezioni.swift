import Foundation

/// Riassunto "a sezioni con memoria" per i modelli con un contesto ampio (Apple Intelligence su Private Cloud
/// Compute). La trascrizione si divide in blocchi; per ognuno il modello scrive le
/// sezioni `### Titolo` nuove, ricevendo i titoli già scritti per non ripetersi e collegare i concetti; una passata
/// finale scrive "In breve", punti chiave e domande dagli appunti. Le sezioni già scritte restano in memoria: un
/// riassunto interrotto (app in background) riprende da lì.
nonisolated enum RiassuntoASezioni {
    static let istruzioni = """
        Sei un assistente che prepara appunti di studio dettagliati per uno studente universitario. Scrivi sempre in \
        italiano, in modo chiaro e completo, come appunti da cui si possa studiare senza riascoltare la lezione. Usa \
        esclusivamente le informazioni presenti nel testo: non aggiungere argomenti, definizioni, esempi o domande che \
        non derivano dal testo. La trascrizione automatica contiene errori di riconoscimento (parole sbagliate, nomi di \
        autori storpiati, frasi spezzate): correggili quando il significato è evidente dal contesto, altrimenti ignora \
        i passaggi incomprensibili. Tralascia saluti, avvisi organizzativi e pause, salvo indicazioni utili per l'esame.
        """

    enum Errore: LocalizedError {
        case vuoto
        var errorDescription: String? { "Il modello non ha prodotto un riassunto. Riprova." }
    }

    /// `genera(richiesta, massimo token)` produce una risposta con `istruzioni` come istruzioni di sistema.
    static func riassumi(_ trascrizione: String, paroleBlocco: Int, glossario: [String] = [],
                         progresso: @escaping @Sendable (Double, String) -> Void,
                         genera: (String, Int) async throws -> String) async throws -> Riassunto {
        let blocchi = dividiInBlocchi(trascrizione, parole: paroleBlocco)
        let chiave = trascrizione.hashValue
        var sezioni = await cache.fatte(chiave)
        for i in sezioni.count..<blocchi.count {
            try Task.checkCancellation()
            progresso(0.03 + 0.85 * Double(i) / Double(blocchi.count), "Parte \(i + 1) di \(blocchi.count)")
            let titoli = sezioni.flatMap(titoliSezioni).map { "- \($0)" }.joined(separator: "\n")
            var richiesta = "Stai preparando gli appunti di una lezione divisa in \(blocchi.count) parti. Questa è la parte \(i + 1).\n"
            if !titoli.isEmpty {
                richiesta += "Argomenti già trattati nelle parti precedenti (non ripeterli, ma collega i nuovi concetti a questi quando il docente lo fa):\n\(titoli)\n"
            }
            richiesta += GlossarioCorso.rigaPrompt(GlossarioCorso.pertinenti(glossario, a: blocchi[i], massimo: 80))
            richiesta += """

                Scrivi gli appunti di questa parte in Markdown: una sezione `### Titolo` per ogni argomento nuovo, \
                nell'ordine, con 1-3 paragrafi dettagliati (concetti, definizioni, autori, esempi, test e passaggi \
                spiegati dal docente). Solo le sezioni, senza introduzione né conclusione.

                Trascrizione della parte \(i + 1):
                \(blocchi[i])
                """
            sezioni.append(try await genera(richiesta, 3_000))
            await cache.salva(chiave, sezioni)
        }
        let corpo = sezioni.joined(separator: "\n\n")
        guard !corpo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Errore.vuoto }
        progresso(0.9, "Sintesi finale")
        let finale = try await genera("""
            Questi sono gli appunti completi di una lezione. Scrivi, in Markdown:

            ## In breve
            Un paragrafo di 4-6 frasi su cosa tratta la lezione e come si collegano gli argomenti.

            ## Punti chiave
            Elenco puntato dei 10-15 concetti più importanti, ognuno in una frase completa.

            ## Da ripassare
            Elenco numerato di 10-15 domande di verifica a cui si risponde con gli appunti.

            ## Termini tecnici
            Elenco puntato dei termini tecnici della materia nominati negli appunti (strutture, sostanze, processi, \
            malattie, test), uno per riga, nella forma corretta, senza spiegazioni.

            Appunti:
            \(corpo)
            """, 3_000)
        await cache.svuota(chiave)
        progresso(1, "Completato")
        // I termini servono al glossario del corso, non al documento.
        let pezzi = finale.components(separatedBy: "## Termini tecnici")
        let termini = pezzi.count > 1
            ? pezzi[1].split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-*•"))) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            : []
        return Riassunto(testo: documento(corpo: corpo, finale: pezzi[0]), termini: termini)
    }

    static func svuotaCache() async { await cache.svuota() }

    /// "## In breve" + "## Riassunto" con le sezioni + "## Punti chiave" e "## Da ripassare" della passata finale.
    static func documento(corpo: String, finale: String) -> String {
        let parti = finale.components(separatedBy: "## Punti chiave")
        let inBreve = parti[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let resto = parti.count > 1 ? "## Punti chiave" + parti[1...].joined(separator: "## Punti chiave") : ""
        // Le sezioni usano solo `###`: eventuali titoli di livello più alto scritti dal modello si abbassano.
        let sezioni = corpo.split(separator: "\n", omittingEmptySubsequences: false).map { riga -> String in
            riga.hasPrefix("## ") || riga.hasPrefix("# ") ? "### " + riga.drop { $0 == "#" || $0 == " " } : String(riga)
        }.joined(separator: "\n")
        var md = inBreve.hasPrefix("## In breve") ? inBreve : "## In breve\n" + inBreve
        md += "\n\n## Riassunto\n\n" + sezioni.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resto.isEmpty { md += "\n\n" + resto.trimmingCharacters(in: .whitespacesAndNewlines) }
        return md
    }

    private static func titoliSezioni(_ testo: String) -> [String] {
        testo.split(separator: "\n").filter { $0.hasPrefix("### ") }.map { $0.dropFirst(4).trimmingCharacters(in: .whitespaces) }
    }

    /// Blocchi di circa `parole` parole, rispettando i paragrafi.
    static func dividiInBlocchi(_ testo: String, parole: Int) -> [String] {
        var blocchi: [String] = []
        var corrente: [Substring] = []
        var conteggio = 0
        for p in testo.split(separator: "\n", omittingEmptySubsequences: true) {
            let n = p.split(separator: " ").count
            if conteggio > 0, conteggio + n > parole {
                blocchi.append(corrente.joined(separator: "\n\n"))
                corrente = []
                conteggio = 0
            }
            corrente.append(p)
            conteggio += n
        }
        if !corrente.isEmpty { blocchi.append(corrente.joined(separator: "\n\n")) }
        return blocchi
    }

    private static let cache = Sezioni()

    private actor Sezioni {
        private var archivio: [Int: [String]] = [:]
        func fatte(_ chiave: Int) -> [String] { archivio[chiave] ?? [] }
        func salva(_ chiave: Int, _ sezioni: [String]) { archivio[chiave] = sezioni }
        func svuota(_ chiave: Int) { archivio[chiave] = nil }
        func svuota() { archivio = [:] }
    }
}
