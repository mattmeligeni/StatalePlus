import AppleArchive
import Foundation
import System

/// Esportazione e importazione di tutte le registrazioni (audio, originali, metadati, trascrizioni, riassunti) in un
/// unico file `.aar` (AppleArchive, senza compressione: l'audio è già compresso). Serve per spostarle su un altro
/// iPhone o per conservarle quando l'app va disinstallata, ad esempio passando da una versione installata con Xcode
/// a una di TestFlight firmata da un altro team: iOS non aggiorna un'app con un identificativo diverso.
nonisolated enum ArchivioRegistrazioni {
    enum Errore: LocalizedError {
        case scrittura, lettura, vuoto
        var errorDescription: String? {
            switch self {
            case .scrittura: "Non è stato possibile creare l'archivio delle registrazioni."
            case .lettura: "Il file scelto non è un archivio di registrazioni di Statale Plus."
            case .vuoto: "Nell'archivio non ci sono registrazioni."
            }
        }
    }

    /// Crea l'archivio nella cartella temporanea e ne restituisce il percorso.
    @concurrent
    static func esporta(da cartella: URL) async throws -> URL {
        let data = Date.now.italiano(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        let destinazione = URL.temporaryDirectory.appending(path: "Registrazioni Statale Plus \(data).aar")
        try? FileManager.default.removeItem(at: destinazione)
        guard let file = ArchiveByteStream.fileStream(path: FilePath(destinazione.path(percentEncoded: false)), mode: .writeOnly,
                                                      options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644)),
              let codifica = ArchiveStream.encodeStream(writingTo: file),
              let campi = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM,CTM") else { throw Errore.scrittura }
        defer { try? codifica.close(); try? file.close() }
        do {
            try codifica.writeDirectoryContents(archiveFrom: FilePath(cartella.path(percentEncoded: false)), keySet: campi)
        } catch {
            throw Errore.scrittura
        }
        return destinazione
    }

    /// Estrae l'archivio in una cartella temporanea e sposta nella cartella delle registrazioni i file delle
    /// registrazioni che non ci sono già (quelle presenti restano come sono). Restituisce quante ne ha aggiunte.
    @concurrent
    static func importa(_ archivio: URL, in cartella: URL) async throws -> Int {
        let accesso = archivio.startAccessingSecurityScopedResource()
        defer { if accesso { archivio.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let estratti = URL.temporaryDirectory.appending(path: "Importazione-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: estratti, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: estratti) }
        guard let file = ArchiveByteStream.fileStream(path: FilePath(archivio.path(percentEncoded: false)), mode: .readOnly,
                                                      options: [], permissions: FilePermissions(rawValue: 0o644)),
              let decodifica = ArchiveStream.decodeStream(readingFrom: file),
              let estrazione = ArchiveStream.extractStream(extractingTo: FilePath(estratti.path(percentEncoded: false)),
                                                           flags: [.ignoreOperationNotPermitted]) else { throw Errore.lettura }
        defer { try? estrazione.close(); try? decodifica.close(); try? file.close() }
        do {
            _ = try ArchiveStream.process(readingFrom: decodifica, writingTo: estrazione)
        } catch {
            throw Errore.lettura
        }
        let files = try fm.contentsOfDirectory(at: estratti, includingPropertiesForKeys: nil)
        let audio = files.filter { $0.pathExtension == "m4a" && !$0.lastPathComponent.contains(".originale.") && UUID(uuidString: String($0.lastPathComponent.prefix(36))) != nil }
        guard !audio.isEmpty else { throw Errore.vuoto }
        var aggiunte = 0
        for a in audio {
            let id = String(a.lastPathComponent.prefix(36))
            guard !fm.fileExists(atPath: cartella.appending(path: a.lastPathComponent).path(percentEncoded: false)) else { continue }
            for f in files where f.lastPathComponent.hasPrefix(id) && !f.lastPathComponent.hasSuffix(".tmp.m4a") {
                try? fm.moveItem(at: f, to: cartella.appending(path: f.lastPathComponent))
            }
            aggiunte += 1
        }
        return aggiunte
    }
}
