import Foundation

nonisolated enum EasyRoomParser {
    static func parse(_ data: Data, day: Date = .now) throws -> OccupazioneAule {
        let delegate = EasyRoomDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return OccupazioneAule(sedi: delegate.sedi, occupazioni: delegate.occupazioni, giorno: day)
    }
}

nonisolated private final class EasyRoomDelegate: NSObject, XMLParserDelegate {
    var sedi: [Sede] = []
    var occupazioni: [Occupazione] = []
    private var office: (name: String, address: String)?
    private var rooms: [Aula] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "office":
            office = (a["name"] ?? "", a["address"] ?? ""); rooms = []
        case "room":
            guard let office, let id = a["id"] else { return }
            rooms.append(Aula(id: id, nome: a["name"] ?? "", codice: a["room_code"] ?? "",
                              capienza: Int(a["capacity"] ?? ""), sede: office.name, indirizzo: office.address))
        case "class":
            guard let id = a["id"], let room = a["room"] else { return }
            occupazioni.append(Occupazione(id: id, dalle: a["from"] ?? "", alle: a["to"] ?? "", aulaId: room,
                                           nome: a["name"] ?? "", docente: a["teacher"] ?? "", tipo: a["type"] ?? ""))
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "office", let office else { return }
        sedi.append(Sede(nome: office.name, indirizzo: office.address, aule: rooms.sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }))
        self.office = nil
    }
}
