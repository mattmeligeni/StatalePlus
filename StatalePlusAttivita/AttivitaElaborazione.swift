import ActivityKit
import Foundation

/// Dati della Live Activity dei lavori lunghi. Lo stesso tipo, con lo stesso nome e gli stessi campi, è definito
/// anche nell'app (`Statale+/Core/Local`): ActivityKit li abbina per nome, quindi vanno cambiati insieme.
nonisolated struct AttivitaElaborazioneAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var lavori: [Lavoro]
    }

    struct Lavoro: Codable, Hashable, Sendable, Identifiable {
        var id: String
        /// "download", "trascrizione", "riassunto", "miglioramento".
        var tipo: String
        var titolo: String
        var sottotitolo: String
        var progresso: Double
        var fase: String?
        var rimanente: String?
        var inPausa: Bool
        var concluso: Bool
    }
}
