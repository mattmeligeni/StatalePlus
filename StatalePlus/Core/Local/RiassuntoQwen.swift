import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Qwen 3.5 0.8B (Alibaba, Apache 2.0) quantizzato a 4 bit (`mlx-community/Qwen3.5-0.8B-4bit`), eseguito con MLX
/// sulla GPU: il modello scaricabile per i riassunti, anche sugli iPhone senza Apple Intelligence.
///
/// Scelto con una prova alla cieca su una lezione vera di un'ora (2026-10-07), fra Apple Intelligence e sette modelli
/// da 0,6 a 1,7 GB: è stato giudicato il migliore (appunti specifici, comprensibili, ordinati, con punti chiave e
/// domande utili), davanti a Qwen 3.5 2B (troppo lungo e ripetitivo) e ad Apple Intelligence (troppo corto). Sul Mac
/// (M1 Pro) un'ora di lezione in 35 secondi con 1,9 GB di memoria al massimo; su un iPhone qualche minuto.
/// Il vecchio Qwen 3.5 4B (3 GB, tolto il 2026-10-06) era troppo lento e consumava troppo.
///
/// Stesso metodo dei riassunti online (`RiassuntoASezioni`): blocchi di ~1500 parole (quelli della prova), sezioni
/// `### Titolo` con la memoria dei titoli già scritti, passata finale con "In breve", punti chiave e domande.
/// Il glossario del corso resta ad Apple Intelligence: con Qwen inventava parole.
///
/// La GPU in background su iPhone non è concessa: se l'app esce dal primo piano il lavoro si ferma con
/// `Errore.inPausa` e riprende al ritorno dalle sezioni già scritte.
nonisolated enum QwenLocale {
    static let repo = "mlx-community/Qwen3.5-0.8B-4bit"
    static let dimensioneMB = 652
    static let byteTotali: Int64 = 652_027_143
    static let paroleBlocco = 1_500
    /// Memoria libera che serve per partire (picco misurato 1,9 GB sul Mac con la cache di MLX libera; limitata a
    /// 256 MB ne basta meno).
    static let memoriaNecessaria: UInt64 = 1_800_000_000

    static var cartella: URL { ScaricatoreModelli.cartellaBase.appending(path: "qwen3.5-0.8b-4bit", directoryHint: .isDirectory) }
    private static var conferma: URL { ScaricatoreModelli.cartellaBase.appending(path: "installato-qwen3.5-0.8b-4bit") }

    /// iPhone con almeno 6 GB di memoria (da iPhone 13 Pro e 14). MLX non funziona nel simulatore.
    static var supportato: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ProcessInfo.processInfo.physicalMemory >= 5_500_000_000
        #endif
    }

    static var installato: Bool {
        FileManager.default.fileExists(atPath: conferma.path(percentEncoded: false))
            && FileManager.default.fileExists(atPath: cartella.appending(path: "model.safetensors").path(percentEncoded: false))
    }

    static var spazioOccupato: Int64 { ScaricatoreModelli.dimensione(cartella) }

    /// Controllo rapido (all'avvio): i file ci sono e occupano quanto devono.
    static var integro: Bool { installato && Double(spazioOccupato) >= Double(byteTotali) * 0.98 }

    /// Riprende un download interrotto (i file già completi non si riscaricano) e verifica la dimensione finale.
    @concurrent
    static func scarica(progresso: @escaping @Sendable (Double, String) -> Void) async throws {
        try? FileManager.default.removeItem(at: conferma)
        try await ScaricatoreModelli.scaricaRepository(repo, in: cartella) { p in
            progresso(p, "\(Int(p * Double(dimensioneMB))) di \(dimensioneMB) MB")
        }
        guard Double(spazioOccupato) >= Double(byteTotali) * 0.98 else { throw ScaricatoreModelli.Errore.downloadNonRiuscito }
        try Data().write(to: conferma)
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: cartella)
        try? FileManager.default.removeItem(at: conferma)
        Task { await RiassuntoASezioni.svuotaCache() }
    }

    enum Errore: LocalizedError {
        case nonInstallato, memoriaInsufficiente, inPausa
        var errorDescription: String? {
            switch self {
            case .nonInstallato: "Il modello per i riassunti non è scaricato: scaricalo da Altro › IA › Riassunti."
            case .memoriaInsufficiente: "Memoria insufficiente in questo momento: chiudi qualche app e riprova."
            case .inPausa: "Riassunto in pausa: riprende quando torni nell'app."
            }
        }
    }

    /// Riassume una trascrizione. `progresso` riceve (0…1, messaggio).
    @concurrent
    static func riassumi(_ trascrizione: String, glossario: [String] = [],
                         progresso: @escaping @Sendable (Double, String) -> Void) async throws -> Riassunto {
        guard LimitiElaborazione.contenutoSufficiente(trascrizione) else { throw AppleIntelligence.Errore.testoInsufficiente }
        guard installato else { throw Errore.nonInstallato }
        guard PrimoPiano.attivo else { throw Errore.inPausa }
        #if os(iOS)
        guard UInt64(os_proc_available_memory()) >= memoriaNecessaria else { throw Errore.memoriaInsufficiente }
        #endif
        progresso(0, "Caricamento del modello…")
        Memory.cacheLimit = 256 * 1024 * 1024
        defer { Memory.clearCache() }
        let modello = try await LLMModelFactory.shared.loadContainer(from: cartella, using: CaricatoreTokenizer())
        return try await RiassuntoASezioni.riassumi(trascrizione, paroleBlocco: paroleBlocco, glossario: glossario,
                                                    progresso: progresso) { richiesta, massimo in
            try await genera(richiesta, massimo: massimo, con: modello)
        }
    }

    /// Una risposta del modello (senza il "ragionamento" di Qwen 3.5), con i parametri della prova alla cieca.
    /// Si ferma appena l'app esce dal primo piano: la GPU in background chiuderebbe l'app.
    private static func genera(_ richiesta: String, massimo: Int, con modello: ModelContainer) async throws -> String {
        guard PrimoPiano.attivo else { throw Errore.inPausa }
        let input = try await modello.prepare(input: UserInput(
            chat: [.system(RiassuntoASezioni.istruzioni), .user(richiesta)],
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
