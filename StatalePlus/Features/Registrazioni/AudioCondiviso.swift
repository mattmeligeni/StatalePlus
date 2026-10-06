import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Audio di una registrazione da condividere con un nome leggibile (`Registrazione.nomeCondivisione`) invece di
/// `<id>.m4a`: chi lo riceve capisce di che lezione si tratta. La copia si crea solo quando si sceglie dove
/// mandarla; su APFS è un clone, quindi non occupa spazio in più e si fa all'istante anche per ore di audio.
nonisolated struct AudioCondiviso: Transferable {
    let sorgente: URL
    let nome: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Audio) { audio in
            SentTransferredFile(try audio.copia())
        }
    }

    private static var cartella: URL { URL.temporaryDirectory.appending(path: "Condivisi", directoryHint: .isDirectory) }

    /// Ogni condivisione in una sottocartella propria (due registrazioni possono avere lo stesso titolo); quelle
    /// più vecchie di un'ora si eliminano.
    private func copia() throws -> URL {
        let fm = FileManager.default
        let limite = Date().addingTimeInterval(-3600)
        for vecchia in (try? fm.contentsOfDirectory(at: Self.cartella, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            if let d = try? vecchia.resourceValues(forKeys: [.creationDateKey]).creationDate, d < limite {
                try? fm.removeItem(at: vecchia)
            }
        }
        let destinazione = Self.cartella.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: destinazione, withIntermediateDirectories: true)
        let file = destinazione.appending(path: nome + "." + sorgente.pathExtension)
        try fm.copyItem(at: sorgente, to: file)
        return file
    }
}
