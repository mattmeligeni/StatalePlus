import Foundation

/// Cartella dei modelli locali (Parakeet) in `Application Support/Modelli`, esclusa dal backup iCloud.
nonisolated enum ScaricatoreModelli {
    static var cartellaBase: URL {
        URL.applicationSupportDirectory.appending(path: "Modelli", directoryHint: .isDirectory)
    }

    static func preparaCartellaBase() throws {
        try FileManager.default.createDirectory(at: cartellaBase, withIntermediateDirectories: true)
        var base = cartellaBase
        var valori = URLResourceValues()
        valori.isExcludedFromBackup = true
        try? base.setResourceValues(valori)
    }

    /// Byte occupati da una cartella (ricorsivo).
    static func dimensione(_ cartella: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: cartella, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return e.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
            .reduce(0) { $0 + Int64($1) }
    }
}
