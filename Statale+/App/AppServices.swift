import Foundation

/// Grafo dei servizi. Due sessioni autenticate distinte (CAS per UNIMIA+SIFA, Ariel) sullo stesso
/// `HTTPCookieStorage.shared` e un client anonimo senza cookie per le API pubbliche.
/// Richieste distanziate per host: 0,7–0,8 s sui portali autenticati, 0,3 s sulle API pubbliche.
nonisolated final class AppServices: Sendable {
    let cas: CASSession
    let arielSession: ArielSession
    let unimia: UnimiaService
    let sifa: SifaService
    let ariel: ArielService
    let agenda: AgendaService
    let easyRoom: EasyRoomService
    let easyBadge: EasyBadgeService

    init() {
        let casHTTP = HTTPClient(profile: .authenticated, minInterval: .milliseconds(800))
        let arielHTTP = HTTPClient(profile: .authenticated, minInterval: .milliseconds(700))
        let publicHTTP = HTTPClient(profile: .anonymous, minInterval: .milliseconds(300))
        cas = CASSession(http: casHTTP)
        arielSession = ArielSession(http: arielHTTP)
        unimia = UnimiaService(cas: cas)
        sifa = SifaService(cas: cas)
        ariel = ArielService(session: arielSession)
        agenda = AgendaService(http: publicHTTP)
        easyRoom = EasyRoomService(http: publicHTTP)
        easyBadge = EasyBadgeService(http: publicHTTP)
    }
}
