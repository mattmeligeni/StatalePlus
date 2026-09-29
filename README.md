# Statale+

App iOS nativa (SwiftUI, Swift 6) che riunisce sotto un unico login i servizi per gli studenti dell'Università degli Studi di Milano, oggi sparsi in quattro sistemi diversi:

| Sistema                                                    | Cosa fornisce                                                                       |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| **UNIMIA** (`unimia.unimi.it`)                             | profilo, carriera e libretto, tasse, esiti in attesa                                |
| **SIFA online** (`studente.unimi.it`)                      | esami iscrivibili, prenotazioni agli appelli, esiti da accettare, pagamenti         |
| **Ariel / myAriel** (`ariel.unimi.it`, `myariel.unimi.it`) | corsi Moodle, schede insegnamento, materiali, bacheche, partecipanti, valutazioni   |
| **API mobili** (`orari-be.divsi.unimi.it`)                 | orario lezioni (Agenda), appelli, aule (EasyRoom), rilevazione presenze (EasyBadge) |

> Progetto indipendente, non affiliato all'Ateneo.

---

## Indice

- [Funzionalità](#funzionalità)
- [Requisiti e build](#requisiti-e-build)
- [Architettura](#architettura)
- [Autenticazione](#autenticazione)
- [Fonti dati ed endpoint](#fonti-dati-ed-endpoint)
- [Formati e particolarità dei dati](#formati-e-particolarità-dei-dati)
- [Persistenza](#persistenza)
- [Aggiornamento dei dati](#aggiornamento-dei-dati)
- [Permessi](#permessi)
- [Stato dei lavori](#stato-dei-lavori)
- [Contribuire](#contribuire)
- [Changelog](#changelog)

---

## Funzionalità

### Accesso

- Riservato agli **studenti immatricolati** con indirizzo `@studenti.unimi.it`.
- Si può scrivere solo `nome.cognome`: il dominio viene aggiunto in automatico. Qualsiasi altro dominio
  (es. `@unimi.it`, `@gmail.com`) o formato non valido viene rifiutato prima di contattare i server.
- Credenziali salvate in Keychain solo dopo un login CAS riuscito; all'avvio, credenziali con dominio non ammesso
  vengono scartate e si torna all'onboarding.

### Oggi

- Saluto con foto profilo locale.
- **Lezioni di oggi** del proprio corso (insegnamenti attivati), con etichette aggiornate ogni minuto:
  `ANNULLATA` (rossa), `IN CORSO` (viola), `INIZIA TRA X MIN` (arancione, da 60 minuti prima).
- La **prossima lezione** (la prima non annullata non ancora finita, quindi anche quella in corso) è in grassetto.
  Tutto è **live** (ogni riga si ricalcola ogni secondo: prossima lezione, barra, etichette):
  - fra una lezione e l'altra (o prima della prima) una barra "Ora HH:MM" sta sopra la prossima lezione;
  - durante una lezione, sul bordo sinistro della riga, una traccia verticale con il pallino all'altezza del tempo
    trascorso che **scorre in tempo reale** e **pulsa**, con un bagliore che scende lungo la parte già trascorsa
    (animazione disattivata con _Riduci movimento_);
  - a fine giornata "Lezioni finite per oggi" in fondo e, sotto, la nota **Prossima lezione** con la distanza relativa
    ("Domani", "Tra 4 giorni") e la materia (mostrata solo a lezioni del giorno terminate o se oggi non ci sono lezioni).
    Un tap apre _Orario_ sulla settimana di quella lezione (tornando al proprio corso se ne era scelto un altro), scorre
    fino alla lezione e la evidenzia per qualche secondo. Le lezioni passate sono attenuate.
  - I passaggi fra `INIZIA TRA X MIN`, `IN CORSO` e `ANNULLATA` avvengono in dissolvenza; i minuti del conto alla
    rovescia cambiano con l'animazione numerica; barra e pallino si scambiano con una dissolvenza.
  In `OggiView.swift` c'è una preview (`#Preview("Lezioni di oggi")`) con orari modificabili e un'ora di partenza
  simulata che poi avanza dal vivo.
- **Azioni rapide** su una lezione da 10 minuti prima dell'inizio fino alla fine:
  - **Conferma presenza** → apre _Altro › Presenze_ sulla lezione. Il pulsante scompare a lezione finita, se il server
    risulta già avere la presenza (anche confermata da un altro dispositivo o dal web) o dopo una risposta positiva.
  - **Inizia registrazione** → apre _Registrazioni_ e avvia subito la registrazione dell'insegnamento.
- **Prossimo appello prenotato** (da SIFA), arricchito con aula e sede dal calendario Agenda e pulsante Mappe.
- **Avvisi Ariel** degli ultimi 10 giorni (bacheche dei corsi attivi).
- **Tasse**: importo da pagare e prossima scadenza.

### Orario

- Settimana navigabile, lezioni raggruppate per giorno, dettaglio con aula, sede, docente e **Apri in Mappe**.
- **Vai a data**: scelta una data (es. 7 ottobre 2026) porta alla sua settimana (5–11 ottobre); se la data cade in un
  altro periodo didattico, cambia anche la pillola del periodo.
- **Pillole dei periodi** lette dall'API (semestri, trimestri, quadrimestri, annuale); default: periodo in corso.
- Menu: **Insegnamenti…** (attivazione per anno / singolo insegnamento), **Cambia corso…**
  (scuola → tipo di laurea → corso, con ricerca), **Torna al mio corso**.
- Default: il corso dell'utente, ricavato dal codice corso UNIMIA (es. `DBD`) incrociato con l'albero Agenda.

### Ariel

- Offerta dell'anno accademico corrente: corsi con sito attivo in cima, gli altri in grigio.
- Dettaglio corso: scheda insegnamento (obiettivi, periodo, lingua, docenti, link), **Calendario lezioni**
  (modal con le sole lezioni della materia dalle API Agenda), contenuti per sezione, moduli con descrizione,
  file (anteprima Quick Look), forum e discussioni, partecipanti, valutazioni.

### Registrazioni

- Registrazione vocale collegata a un insegnamento attivato (suggerito automaticamente se c'è una lezione in corso).
- Timer, livello microfono, pausa/ripresa, **segnalibri**, annulla; continua a schermo bloccato e si mette in pausa
  durante le telefonate.
- Archivio ordinato per insegnamento: la schermata principale elenca solo gli insegnamenti che hanno registrazioni
  (numero, durata totale, data dell'ultima); toccandone uno si apre il suo elenco. La ricerca per titolo,
  insegnamento o note mostra i risultati in un'unica lista.
- Dettaglio: player (±15/30 s, velocità 0,75–2×, salto ai segnalibri), titolo, insegnamento, note, condivisione, eliminazione.
- **Trascrizione** in italiano con il framework Speech di Apple:
  - iOS 26+: `SpeechAnalyzer` + `SpeechTranscriber` on-device, pensati per audio lunghi (il modello della lingua viene
    scaricato la prima volta);
  - iOS 17–25: `SFSpeechRecognizer` a blocchi di 50 s, on-device quando supportato, con punteggiatura.
  - Avanzamento e annulla; continua anche uscendo dalla schermata. Testo in paragrafi, modificabile, con **Writing Tools**
    (iOS 18+), conteggio parole, condivisione, nuova trascrizione.
- **Riassunto con Apple Intelligence** (FoundationModels, iOS 26+, solo se disponibile sul dispositivo): la trascrizione è
  divisa in parti (il modello on-device ha un contesto di ~4K token), ogni parte diventa appunti e gli appunti diventano un
  riassunto in Markdown con _Riassunto_, _Punti chiave_ e _Da ripassare_ (domande di verifica). Visualizzazione formattata,
  modifica con Writing Tools, rigenerazione. Se Apple Intelligence è disattivata o in download l'app lo indica.

### Altro

- **Carriera e libretto**: profilo, recapiti, libretto, esiti da accettare, PDF "prossimi appelli" del corso.
- **Tasse e pagamenti**: righe della situazione amministrativa, totali, avvisi, link ai pagamenti SIFA.
- **Esami**
  - _Calendario_: appelli dalle API Agenda per corso e anno (pillole), raggruppati per settimana, corso modificabile
    dal menu; **Vai a data** fa partire il calendario dalla settimana scelta (anche nel passato), _Oggi_ torna al presente.
  - _Iscrizioni_: prenotazioni confermate, esiti da accettare, pulsante **Iscriviti a un appello** che apre la replica di
    "Esami del tuo corso di studio" (ricerca per descrizione, Codice / Descrizione / Crediti, pulsante _Iscrizione_).
- **Aule**: sedi espandibili con le aule e lo stato attuale (libera / occupata fino alle…), ricerca sempre visibile per
  sede, aula o indirizzo, indirizzo cliccabile; _Dove si tiene_ cerca le attività della giornata odierna.
- **Presenze**: registrazione presenza con codice lezione (digitato o da **QR**), risposta del server mostrata così com'è;
  percentuali di frequenza per corso e dettaglio degli slot.
- **Impostazioni**: foto profilo, account, stato delle sessioni, dati salvati, aggiornamento profilo, uscita
  (con scelta se conservare o eliminare registrazioni, foto e cache).

### Mappe

Tutti i collegamenti a Mappe usano l'**indirizzo della sede presa da EasyRoom**: per codice aula (gli appelli usano
lo stesso `room_code` di EasyRoom, es. `33230#4001`), poi per nome aula + sede, poi per sede; ricerca testuale solo come
ultima risorsa.

---

## Requisiti e build

- Xcode 27 (Swift 6.4), target **iOS 17.0+**, iPhone e iPad.
- **Nessuna dipendenza esterna**: HTML, CSS selector, XML, JSON, Keychain, audio e fotocamera usano solo il parser
  interno e i framework di sistema.

```bash
open Statale+.xcodeproj
```

Da riga di comando (simulatore):

```bash
xcodebuild -project Statale+.xcodeproj -scheme "Statale+" -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Impostazioni di progetto rilevanti: `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
`SWIFT_APPROACHABLE_CONCURRENCY = YES`, Info.plist generato + `Statale+-Info.plist` (solo `UIBackgroundModes = audio`).

---

## Architettura

```
Statale+/
├── App/                 AppModel (stato radice, navigazione, refresh), AppServices, Live<T>
├── Core/
│   ├── Auth/            CASSession, ArielSession, KeychainStore
│   ├── HTML/            parser HTML tollerante + selettori CSS (sostituisce librerie esterne)
│   ├── Local/           foto profilo, registrazioni (store, recorder, player), trascrizione (Speech), riassunti (FoundationModels)
│   ├── Networking/      HTTPClient (rate limiting per host, redirect guard, rilevazione Cloudflare)
│   ├── Persistence/     StableStore (cache stabile su disco)
│   └── Util/            formati di data/importi, decodifica tollerante, helper HTML
├── Models/              modelli per fonte (UNIMIA, SIFA, Ariel, Agenda, EasyRoom, EasyBadge)
├── Parsers/             HTML → modelli, XML → modelli, JSON → modelli
├── Services/            un attore per fonte (UnimiaService, SifaService, ArielService, AgendaService, …)
└── Features/            viste SwiftUI per tab (Oggi, Orario, Ariel, Registrazioni, Altro, Shared)
```

- **Concorrenza**: UI e modelli osservabili su `MainActor`; rete e parsing negli **attori** dei servizi; modelli e parser
  `nonisolated` e `Sendable`.
- **Dati live**: `Live<T>` gestisce valore, errore, caricamento e "aggiornato alle HH:MM"; un nuovo caricamento rende
  obsoleto quello in corso (es. cambio periodo durante un fetch).
- **Rete**: tre client HTTP.
  - _CAS_ (UNIMIA + SIFA) e _Ariel_: `HTTPCookieStorage.shared`, sessioni separate.
  - _Pubblico_ (API mobili): **senza cookie**, perché `orari-be.divsi.unimi.it` è un sottodominio di `unimi.it` e
    riceverebbe il `CASTGC` (dominio `.unimi.it`).
  - Richieste distanziate per host (0,7–0,8 s autenticate, 0,3 s pubbliche), User-Agent unico, solo HTTPS,
    redirect verso URL di logout bloccati (una `ClosingPage` SIFA farebbe Single Logout e invaliderebbe il CASTGC).

---

## Autenticazione

Un solo login in onboarding (email `nome.cognome@studenti.unimi.it` + password), salvato nel **Keychain** dopo un login
CAS riuscito. Re-login trasparente quando una sessione scade.

| Meccanismo             | Flusso                                                                                                                                                                                                                                                                                                            |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CAS** (UNIMIA, SIFA) | `GET cas.unimi.it/login?service=…` → campi hidden `lt`, `execution` → `POST /login` (`username`, `password`, `selTipoUtente=S`, `_eventId=submit`, …) → redirect con ticket → sessione. Il cookie `CASTGC` abilita gli altri service senza credenziali.                                                           |
| **SIFA**               | Ogni app è un service CAS: `GET studente.unimi.it/<app>/checkLogin.asp`. A freddo Cloudflare risponde 401: prima un `GET https://studente.unimi.it/` per ottenere `__cf_bm`. App Wicket **stateful**: si usano solo pagine montate a classe, mai URL `?N`.                                                        |
| **Ariel**              | Login **proprio**, non CAS: form ASP.NET su `elearning.unimi.it/authentication/skin/portaleariel/login.aspx` con `tbLogin` (parte locale dell'email), `tbPassword`, `ddlType` (`@studenti.unimi.it`), `hdnSilent=true` + tutti i campi hidden. Cookie `arielauth`; Moodle usa il `sesskey` letto dalla config JS. |
| **API mobili**         | Nessuna autenticazione; EasyBadge richiede solo la matricola **minuscola** nel body.                                                                                                                                                                                                                              |

---

## Fonti dati ed endpoint

### UNIMIA — `https://unimia.unimi.it/portal/server.pt`

| Dato                            | Endpoint                                                                                                                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Profilo, recapiti, codice corso | `/community/unimia/207/home/8993` (`#div_studente`, `#div_anagrafica`, `<h2>Home: NOME</h2>`)                                                                                                     |
| Tasse                           | `/gateway/PTARGS_6_0_219_207_8993_43/` (header `X-Requested-With`, `Referer`)                                                                                                                     |
| Esiti in attesa / iscrizioni    | portlet `240` / `310` (stesso schema)                                                                                                                                                             |
| Libretto                        | `/gateway/PTARGS_0_0_209_207_0_43/http%3B/portlets.alui.unimi.it%3B8880/portale_utenti_cocoon_portlet/carriera.html?modalita=dettaglio&…&matricola=<M>&dottorato=` (niente quote totale del path) |
| PDF prossimi appelli            | `https://studente.unimi.it/foProssimiEsami/pdf/<CODICE_CORSO>`                                                                                                                                    |

### SIFA — `https://studente.unimi.it`

| Dato              | Pagina                                                                                                                                        |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Esami iscrivibili | `foIscrizioneEsami/esamiPack/EsamiNonSostenutiDelCorsoPage` (`table.smart-table`: Codice, Descrizione, Crediti, _Iscrizione_ `ILinkListener`) |
| Prenotazioni      | `foIscrizioneEsami/esamiPack/EsamiIscrizioniConfermatePage` (vuoto: "Nessun esame presente")                                                  |
| Esiti finali      | `foVerbalizzazione/esitiFinali`                                                                                                               |
| Pagamenti         | `fo_pagamenti/` (solo link)                                                                                                                   |

### Ariel / myAriel

| Dato                         | Endpoint                                                                                                                                                                      |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Offerta corsi                | `https://ariel.unimi.it/Offerta/myof` (linguette per anno accademico)                                                                                                         |
| Struttura corso              | `POST myariel.unimi.it/lib/ajax/service.php?sesskey=…&info=core_courseformat_get_state` body `[{"index":0,"methodname":"core_courseformat_get_state","args":{"courseid":N}}]` |
| Scheda insegnamento          | `course/view.php?id=N` (`section.block_w4info`)                                                                                                                               |
| Moduli / forum / discussioni | `mod/<tipo>/view.php?id=…`, `mod/forum/discuss.php?d=…`                                                                                                                       |
| Partecipanti / valutazioni   | `user/index.php?id=N`, `grade/report/index.php?id=N`                                                                                                                          |

### API mobili — `https://orari-be.divsi.unimi.it`

| Dato                      | Endpoint                                                                                                                                                                                                                                                           |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Albero corsi (orario)     | `GET /agendastudenti/api_profilo_aa_scuola_tipo_cdl_pd.php`                                                                                                                                                                                                        |
| Insegnamenti              | `GET /agendastudenti/api_profilo_lista_insegnamenti.php?cdl=<id>&periodo_didattico=<id>`                                                                                                                                                                           |
| Orario insegnamento (XML) | `GET /agendastudenti//App/zipped.php?file=<anno>/<codice>_<periodo>.xml`                                                                                                                                                                                           |
| Albero corsi (esami)      | `GET /agendastudenti/api_profilo_esami_scuola_tipo_cdl.php`                                                                                                                                                                                                        |
| Appelli                   | `GET /agendastudenti/test_call.php?view=easytest&include=et_cdl&et_er=1&datefrom=DD-MM-YYYY&dateto=DD-MM-YYYY&esami_cdl%5B%5D=<CDL>%7C<ANNO>`                                                                                                                      |
| Aule (XML)                | `GET /EasyRoom/do.php`                                                                                                                                                                                                                                             |
| Frequenze                 | `POST /easybadge-new/api/corso_iscritti.php` `{"Matricola":"12345a"}`                                                                                                                                                                                              |
| Slot lezione              | `POST /easybadge-new/api/timbrature.php` `{"Matricola":"12345a","Corsi":[{"codice":"XXX-1_1"}]}`                                                                                                                                                                   |
| Timbratura                | `POST /easybadge-new/api/TimbratureApi.php` `{"matricola_studente","codice_lezione","posto":"","lingua":"it","autenticazione":true,"action":"CreateFromJSON","dati_addizionali":{"timestamp":<epoch ms>,"longitudine":0,"latitudine":0}}` → `{"result","message"}` |

---

## Formati e particolarità dei dati

Verificati su risposte reali; i modelli Swift ne tengono conto.

- **Date**: `DD-MM-YYYY` in Agenda e UNIMIA, `YYYY-MM-DD` nelle festività XML, `YYYY-MM-DD HH:MM:SS` in EasyBadge,
  ISO 8601 con offset nei forum Moodle, epoch in `data-timestamp`.
- **Importi** UNIMIA come testo (`"130 euro"`) → `Decimal`.
- **Tipi misti**: nell'albero orario `valore` è a volte `Int` e a volte `String`; `anno`, `crediti` e gli id sono stringhe.
- **Dizionari PHP**: senza appelli `"Insegnamenti": []` invece di `{}`; gestito da `PHPDictionary`.
- **File orario inesistente** → HTTP 200 con corpo vuoto = nessuna lezione. Risposte `Content-Encoding: gzip`.
- **Moodle**: la risposta AJAX contiene il JSON **come stringa** (doppia decodifica); il tipo modulo è `module`
  (`forum`), `modname` è l'etichetta localizzata (`Forum`).
- **EasyBadge**: i campi `Frequentate`, `OreFatte`, `OreDaFare`, `OreLimite` sono **minuti**; `OreDaFare` è il residuo
  (totale = fatte + da fare; soglia = `percentuale_conseguimento` × totale).
- **EasyRoom**: `<office>` non ha `id`; la sede di un'occupazione si ricava da `class@room` → `<room>` → `<office>`.
  Le occupazioni valgono per il giorno della richiesta.
- **Codici insegnamento** diversi fra sistemi: SIFA `DBD0A0`, Agenda `DBD-28_1` (XML `CodiceGenerale` `DBD-28`,
  `Codice` `ECDBD-28_1`), Ariel `DBD-28`, EasyBadge `DBD-28_1`. I collegamenti usano prefissi di codice o il nome normalizzato.
- **Codici aula**: appelli `33230#4001` = EasyRoom `room_code`; lezioni `9999981-Conf` ≈ EasyRoom `9999981@Conf`
  (separatore normalizzato).

---

## Persistenza

| Dato                                                                                                       | Dove                                                                                                                      |
| ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Credenziali                                                                                                | Keychain (`WhenUnlockedThisDeviceOnly`)                                                                                   |
| Profilo, configurazione Agenda (corso, periodi, insegnamenti attivati), offerta Ariel, schede insegnamento | `Application Support/stable.json` con scadenze (profilo 24 h, offerta 24 h, agenda e schede 7 giorni), esclusa dal backup |
| Foto profilo                                                                                               | `Application Support/profilo.jpg`                                                                                         |
| Registrazioni                                                                                              | `Application Support/Registrazioni/<id>.m4a` + indice `registrazioni.json` (AAC mono 64 kbps, ~29 MB/ora)                 |
| Trascrizioni e riassunti                                                                                   | `Application Support/Registrazioni/<id>.txt` e `<id>.riassunto.md`, separati dall'indice                                  |
| Cookie di sessione                                                                                         | `HTTPCookieStorage` di sistema                                                                                            |
| Orario, appelli, tasse, presenze, aule, esiti, partecipanti                                                | solo in memoria                                                                                                           |

**Uscita**: credenziali, cookie e dati dell'account vengono sempre rimossi; l'utente sceglie se eliminare anche
registrazioni, foto profilo, file scaricati e cache o conservarli per un altro profilo.

---

## Aggiornamento dei dati

- Ogni schermata live si carica all'apertura e ha il **pull-to-refresh** con "Aggiornato alle HH:MM".
- **Refresh automatico ogni 5 minuti** (app in primo piano) di lezioni di oggi, presenze, orario e prenotazioni
  (questi ultimi se già aperti). Il timer riparte da ogni pull-to-refresh su Oggi, Orario o Presenze.

---

## Permessi

| Permesso            | Uso                                                 |
| ------------------- | --------------------------------------------------- |
| Microfono           | registrazione delle lezioni                         |
| Fotocamera          | scansione del QR del codice lezione                 |
| Riconoscimento vocale | trascrizione delle registrazioni (iOS 17–25)      |
| Audio in background | la registrazione continua a schermo bloccato        |
| Libreria foto       | nessun permesso: la foto profilo usa `PhotosPicker` |

---

## Stato dei lavori

Da completare:

- [ ] **Iscrizione agli appelli** da app: `SifaService.iscrivi(_:)` è predisposto (UI completa), manca il flusso Wicket
      (seguire l'`ILinkListener` della riga nella stessa sessione, scelta appello, conferma).
- [ ] **Pagamenti SIFA**
- [ ] **Formato del QR** del codice lezione: `QRLezione.codice(from:)` oggi usa il testo letto così com'è.
- [ ] **Prenotazioni**: le colonne di una prenotazione reale non sono ancora state osservate; data ed esame sono
      ricavati per euristica (`Prenotazione.from`).
- [ ] Libretto, esiti da accettare e cartelle Ariel con file: parsing generico, da rifinire su casi popolati.
- [ ] Piano di studi (SPA con XHR interne) non integrato.
- [ ] Media Aritmetica/Ponderata

---

## Contribuire

- Ogni modifica va accompagnata dall'aggiornamento di questo README (funzionalità, endpoint, formati, stato dei lavori)
  e da una voce nel [Changelog](#changelog).
- Nessuna dipendenza esterna senza una ragione forte.
- Mai dati personali reali (nomi, matricole, indirizzi) nel codice, nei commenti o nei test: usare segnaposto
  (`MARIO ROSSI`, `12345A`).

---

## Changelog

### 2026-09-29 (7)

- Orario: la lezione aperta da "Prossima lezione" viene ora evidenziata davvero e la lista scorre fino a lei.
- Nota "Prossima lezione" ridotta a distanza relativa e materia.

### 2026-09-29 (6)

- Oggi: dissolvenza fra le etichette di stato e fra barra e pallino, conto alla rovescia animato.
- Nota "Prossima lezione" (giorno relativo, data, materia) a lezioni del giorno terminate; un tap apre l'Orario sulla
  settimana della lezione e la evidenzia.

### 2026-09-29 (5)

- Oggi completamente live: prossima lezione, barra, etichette `IN CORSO` / `INIZIA TRA X MIN` aggiornate ogni secondo;
  pallino della lezione in corso animato (scorre, pulsa, bagliore sulla parte trascorsa).

### 2026-09-29 (4)

- Oggi: durante una lezione l'ora corrente è una traccia verticale con pallino proporzionale al tempo trascorso,
  al posto della barra sopra la lezione.
- Etichette `IN CORSO` / `INIZIA TRA X MIN` calcolate sulla stessa ora di barra e grassetto (anche nella preview).

### 2026-09-29 (3)

- Trascrizione delle registrazioni con Speech (SpeechAnalyzer su iOS 26+, SFSpeechRecognizer prima), modificabile con
  Writing Tools.
- Riassunti con Apple Intelligence (FoundationModels): riassunto, punti chiave e domande di ripasso.
- Oggi: avvisi Ariel degli ultimi 10 giorni; prossima lezione in grassetto con barra "Ora" statica; preview locale.

### 2026-09-29 (2)

- Onboarding: accesso riservato agli indirizzi `@studenti.unimi.it`, completamento automatico da `nome.cognome`,
  errore per ogni altro dominio.
- Registrazioni raggruppate per insegnamento con navigazione all'elenco dedicato.
- "Vai a data" nella vista settimanale di Orario ed Esami; appelli raggruppati per settimana.

### 2026-09-29

- Prima versione dell'app: login unico (CAS + Ariel), tab Oggi, Orario, Ariel, Registrazioni, Altro.
- Parser HTML interno al posto di SwiftSoup: nessuna dipendenza esterna.
- Orario ed Esami con scelta di corso (scuola → tipo → corso) e pillole di periodo/anno dalle API mobili.
- Etichette di stato delle lezioni (annullata, in corso, inizia tra X min) e azioni rapide in Oggi
  (conferma presenza, inizia registrazione) con refresh automatico ogni 5 minuti.
- Presenze con invio codice lezione / QR; iscrizione agli appelli predisposta.
- Mappe basate sugli indirizzi EasyRoom.
- Registrazioni vocali locali con segnalibri, note e player.
- Foto profilo locale; uscita con scelta di conservare o eliminare i dati locali.
