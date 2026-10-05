import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
#if canImport(UIKit)
import UIKit
#endif

/// Motori dei riassunti selezionabili in Altro › IA.
nonisolated enum MotoreRiassunto: String, CaseIterable, Sendable {
    /// Modello di Apple Intelligence sul dispositivo (FoundationModels): nessun download, contesto di ~4K token.
    case apple
    /// Qwen 3.5 4B (Alibaba, Apache 2.0) con MLX, sul dispositivo: più accurato, download di ~3 GB.
    case qwen

    var nome: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .qwen: "Qwen 3.5 4B"
        }
    }
}

/// Qwen 3.5 4B quantizzato a 4 bit (`mlx-community/Qwen3.5-4B-4bit`) eseguito con MLX sulla GPU.
///
/// Prove su una lezione reale di 2 h 25 min e su una sintetica con errori di trascrizione voluti (Mac M1 Pro):
/// - a sezioni con memoria: copre quasi tutti gli argomenti (40 termini su 75 contro 34 di Apple), corregge nomi e
///   termini storpiati dalla trascrizione ("modo di gambier" → "nodi di Ranvier"), circa 5 minuti;
/// - in una passata sola è più rapido ma riassume troppo (un migliaio di parole per due ore).
/// Quindi: la trascrizione si divide in blocchi di ~2200 parole; per ogni blocco il modello scrive le sezioni
/// `### Titolo` nuove, ricevendo l'elenco dei titoli già scritti per non ripetersi e collegare i concetti; alla fine
/// una passata scrive "In breve", punti chiave e domande dagli appunti.
///
/// La GPU non si può usare con l'app in background (serve un entitlement che gli account personali non hanno): se
/// l'app esce dal primo piano il lavoro si ferma con `Errore.inPausa` e riprende al ritorno dalle sezioni già fatte.
nonisolated enum QwenLocale {
    static let repo = "mlx-community/Qwen3.5-4B-4bit"
    static let dimensioneMB = 3061
    /// Memoria che serve davvero (picco misurato 4,8 GB sul Mac, con la cache di MLX limitata ne bastano meno).
    static let memoriaNecessaria: UInt64 = 3_800_000_000

    static var cartella: URL { ScaricatoreModelli.cartellaBase.appending(path: "qwen3.5-4b-4bit", directoryHint: .isDirectory) }
    private static var conferma: URL { ScaricatoreModelli.cartellaBase.appending(path: "installato-qwen3.5-4b-4bit") }

    /// iPhone con almeno 8 GB di RAM (15 Pro e successivi). MLX non funziona nel simulatore.
    static var supportato: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ProcessInfo.processInfo.physicalMemory >= 7_500_000_000
        #endif
    }

    static var installato: Bool {
        FileManager.default.fileExists(atPath: conferma.path(percentEncoded: false))
            && FileManager.default.fileExists(atPath: cartella.appending(path: "model.safetensors").path(percentEncoded: false))
    }

    static var spazioOccupato: Int64 { ScaricatoreModelli.dimensione(cartella) }

    @concurrent
    static func scarica(progresso: @escaping @Sendable (Double) -> Void) async throws {
        try await ScaricatoreModelli.scaricaRepository(repo, in: cartella, progresso: progresso)
        try Data().write(to: conferma)
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: cartella)
        try? FileManager.default.removeItem(at: conferma)
        Task { await Sezioni.shared.svuota() }
    }

    enum Errore: LocalizedError {
        case nonInstallato, memoriaInsufficiente, inPausa, vuoto
        var errorDescription: String? {
            switch self {
            case .nonInstallato: "Il modello Qwen non è scaricato: scaricalo da Altro › IA › Riassunti."
            case .memoriaInsufficiente: "Memoria insufficiente per Qwen in questo momento: chiudi qualche app e riprova, oppure usa Apple Intelligence."
            case .inPausa: "Riassunto in pausa: riprende quando torni nell'app."
            case .vuoto: "Il modello non ha prodotto un riassunto. Riprova."
            }
        }
    }

    private static let istruzioni = """
        Sei un assistente che prepara appunti di studio dettagliati per uno studente universitario. Scrivi sempre in \
        italiano, in modo chiaro e completo, come appunti da cui si possa studiare senza riascoltare la lezione. Usa \
        esclusivamente le informazioni presenti nel testo: non aggiungere argomenti, definizioni, esempi o domande che \
        non derivano dal testo. La trascrizione automatica contiene errori di riconoscimento (parole sbagliate, nomi di \
        autori storpiati, frasi spezzate): correggili quando il significato è evidente dal contesto, altrimenti ignora \
        i passaggi incomprensibili. Tralascia saluti, avvisi organizzativi e pause, salvo indicazioni utili per l'esame.
        """

    /// Riassume una trascrizione. `progresso` riceve (0…1, messaggio).
    @concurrent
    static func riassumi(_ trascrizione: String, progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard installato else { throw Errore.nonInstallato }
        guard PrimoPiano.attivo else { throw Errore.inPausa }
        #if os(iOS)
        guard UInt64(os_proc_available_memory()) >= memoriaNecessaria else { throw Errore.memoriaInsufficiente }
        #endif
        progresso(0, "Caricamento di Qwen…")
        Memory.cacheLimit = 256 * 1024 * 1024
        defer { Memory.clearCache() }
        let modello = try await LLMModelFactory.shared.loadContainer(from: cartella, using: CaricatoreTokenizer())

        let blocchi = dividiInBlocchi(trascrizione, parole: 2_200)
        let chiave = trascrizione.hashValue
        var sezioni = await Sezioni.shared.fatte(chiave)
        for i in sezioni.count..<blocchi.count {
            try Task.checkCancellation()
            progresso(0.03 + 0.85 * Double(i) / Double(blocchi.count), "Parte \(i + 1) di \(blocchi.count)…")
            let titoli = sezioni.flatMap(titoliSezioni).map { "- \($0)" }.joined(separator: "\n")
            var richiesta = "Stai preparando gli appunti di una lezione divisa in \(blocchi.count) parti. Questa è la parte \(i + 1).\n"
            if !titoli.isEmpty {
                richiesta += "Argomenti già trattati nelle parti precedenti (non ripeterli, ma collega i nuovi concetti a questi quando il docente lo fa):\n\(titoli)\n"
            }
            richiesta += """

                Scrivi gli appunti di questa parte in Markdown: una sezione `### Titolo` per ogni argomento nuovo, \
                nell'ordine, con 1-3 paragrafi dettagliati (concetti, definizioni, autori, esempi, test e passaggi \
                spiegati dal docente). Solo le sezioni, senza introduzione né conclusione.

                Trascrizione della parte \(i + 1):
                \(blocchi[i])
                """
            let testo = try await genera(richiesta, massimo: 3_000, con: modello)
            sezioni.append(testo)
            await Sezioni.shared.salva(chiave, sezioni)
        }
        let corpo = sezioni.joined(separator: "\n\n")
        guard !corpo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Errore.vuoto }
        progresso(0.9, "Sintesi finale…")
        let finale = try await genera("""
            Questi sono gli appunti completi di una lezione. Scrivi, in Markdown:

            ## In breve
            Un paragrafo di 4-6 frasi su cosa tratta la lezione e come si collegano gli argomenti.

            ## Punti chiave
            Elenco puntato dei 10-15 concetti più importanti, ognuno in una frase completa.

            ## Da ripassare
            Elenco numerato di 10-15 domande di verifica a cui si risponde con gli appunti.

            Appunti:
            \(corpo)
            """, massimo: 2_500, con: modello)
        await Sezioni.shared.svuota(chiave)
        progresso(1, "Completato")
        return documento(corpo: corpo, finale: finale)
    }

    /// "## In breve" + "## Riassunto" con le sezioni + "## Punti chiave" e "## Da ripassare" della passata finale.
    private static func documento(corpo: String, finale: String) -> String {
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

    /// Una risposta del modello (senza il "ragionamento" di Qwen 3.5). Si ferma se l'app esce dal primo piano.
    private static func genera(_ richiesta: String, massimo: Int, con modello: ModelContainer) async throws -> String {
        let input = try await modello.prepare(input: UserInput(
            chat: [.system(istruzioni), .user(richiesta)],
            additionalContext: ["enable_thinking": false]))
        let parametri = GenerateParameters(maxTokens: massimo, temperature: 0.7, topP: 0.8, topK: 20,
                                           repetitionPenalty: 1.05, repetitionContextSize: 256)
        var testo = ""
        for await evento in try await modello.generate(input: input, parameters: parametri) {
            guard PrimoPiano.attivo else { throw Errore.inPausa }
            try Task.checkCancellation()
            if case .chunk(let pezzo) = evento { testo += pezzo }
        }
        return testo.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Sezioni già scritte per una trascrizione: se il riassunto si interrompe (app in background) riprende da lì.
private actor Sezioni {
    static let shared = Sezioni()
    private var archivio: [Int: [String]] = [:]
    func fatte(_ chiave: Int) -> [String] { archivio[chiave] ?? [] }
    func salva(_ chiave: Int, _ sezioni: [String]) { archivio[chiave] = sezioni }
    func svuota(_ chiave: Int) { archivio[chiave] = nil }
    func svuota() { archivio = [:] }
}

/// Il tokenizer di swift-transformers adattato al protocollo di mlx-swift-lm (come la macro di MLXHuggingFace, scritto
/// a mano per non dover abilitare le macro dei pacchetti in Xcode).
private nonisolated struct CaricatoreTokenizer: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        Ponte(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }

    struct Ponte: MLXLMCommon.Tokenizer {
        let upstream: any Tokenizers.Tokenizer
        init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
        }
        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
        }
        func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
        func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }
        func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                               additionalContext: [String: any Sendable]?) throws -> [Int] {
            do {
                return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
            } catch Tokenizers.TokenizerError.missingChatTemplate {
                throw MLXLMCommon.TokenizerError.missingChatTemplate
            }
        }
    }
}

/// L'app è in primo piano? Letto dai lavori sulla GPU, che con l'app in background non sono permessi.
nonisolated enum PrimoPiano {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var valore = true

    static var attivo: Bool {
        lock.lock(); defer { lock.unlock() }
        return valore
    }

    static func imposta(_ v: Bool) {
        lock.lock(); valore = v; lock.unlock()
    }
}
