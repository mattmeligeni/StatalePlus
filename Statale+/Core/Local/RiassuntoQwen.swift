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
    /// Apple Intelligence su Private Cloud Compute (online, iOS 27): solo con l'entitlement concesso da Apple.
    case cloud

    var nome: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .qwen: "Qwen 3.5 4B"
        case .cloud: "Apple Intelligence online"
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
    static let byteTotali: Int64 = 3_061_129_077

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

    /// Riassume una trascrizione. `progresso` riceve (0…1, messaggio).
    @concurrent
    static func riassumi(_ trascrizione: String, progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard installato else { throw Errore.nonInstallato }
        guard PrimoPiano.attivo || EsecuzioneEstesa.gpuConcessa else { throw Errore.inPausa }
        #if os(iOS)
        guard UInt64(os_proc_available_memory()) >= memoriaNecessaria else { throw Errore.memoriaInsufficiente }
        #endif
        progresso(0, "Caricamento di Qwen…")
        Memory.cacheLimit = 256 * 1024 * 1024
        defer { Memory.clearCache() }
        let modello = try await LLMModelFactory.shared.loadContainer(from: cartella, using: CaricatoreTokenizer())

        return try await RiassuntoASezioni.riassumi(trascrizione, paroleBlocco: 2_200, progresso: progresso) { richiesta, massimo in
            try await genera(richiesta, massimo: massimo, con: modello)
        }
    }

    /// Più risposte brevi con lo stesso modello caricato una volta (es. gli elenchi del glossario del corso).
    @concurrent
    static func rispondi(_ richieste: [String], istruzioni: String, massimo: Int,
                         progresso: @escaping @Sendable (Double) -> Void) async throws -> [String] {
        guard installato else { throw Errore.nonInstallato }
        guard PrimoPiano.attivo || EsecuzioneEstesa.gpuConcessa else { throw Errore.inPausa }
        #if os(iOS)
        guard UInt64(os_proc_available_memory()) >= memoriaNecessaria else { throw Errore.memoriaInsufficiente }
        #endif
        Memory.cacheLimit = 256 * 1024 * 1024
        defer { Memory.clearCache() }
        let modello = try await LLMModelFactory.shared.loadContainer(from: cartella, using: CaricatoreTokenizer())
        var risposte: [String] = []
        for (i, r) in richieste.enumerated() {
            progresso(Double(i) / Double(max(richieste.count, 1)))
            risposte.append(try await genera(r, massimo: massimo, con: modello, istruzioni: istruzioni, temperatura: 0.3))
        }
        progresso(1)
        return risposte
    }

    /// Una risposta del modello (senza il "ragionamento" di Qwen 3.5). Si ferma se l'app esce dal primo piano.
    private static func genera(_ richiesta: String, massimo: Int, con modello: ModelContainer,
                               istruzioni: String = RiassuntoASezioni.istruzioni, temperatura: Float = 0.7) async throws -> String {
        let input = try await modello.prepare(input: UserInput(
            chat: [.system(istruzioni), .user(richiesta)],
            additionalContext: ["enable_thinking": false]))
        let parametri = GenerateParameters(maxTokens: massimo, temperature: temperatura, topP: 0.8, topK: 20,
                                           repetitionPenalty: 1.05, repetitionContextSize: 256)
        var testo = ""
        for await evento in try await modello.generate(input: input, parameters: parametri) {
            guard PrimoPiano.attivo || EsecuzioneEstesa.gpuConcessa else { throw Errore.inPausa }
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
