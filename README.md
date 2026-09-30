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
- Pulsante per mostrare la password (utile anche nel simulatore, dove la tastiera fisica del Mac può essere interpretata
  con un layout diverso). Se CAS rifiuta l'accesso viene mostrato il suo messaggio; un log diagnostico
  (sottosistema `com.mattiameligeni.Statale`, categoria `login`) riporta esito, pagina e messaggio, mai la password.

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
  - I due pulsanti sono affiancati, con il testo su due righe se serve; a presenza registrata il primo diventa
    l'etichetta verde "Presenza registrata" con il sigillo pieno (lo stesso simbolo di "Tasse in regola").
- Aula e sede su due righe (aula in evidenza, sede in grigio) in lezioni, appelli e prenotazioni.
- **Prossimo appello prenotato** (da SIFA), arricchito con aula e sede dal calendario Agenda e pulsante Mappe.
- **Avvisi Ariel** degli ultimi 7 giorni (bacheche dei corsi attivi).
- Se appello prenotato e avvisi sono **entrambi** vuoti, una sola riga discreta ("Nessun appello prenotato e nessun
  avviso Ariel negli ultimi 7 giorni"); se almeno uno ha elementi, le due sezioni restano separate.
- Durante il primo caricamento ogni sezione mostra una riga segnaposto sfumata al posto della rotellina.
- **Tasse**: importo da pagare oppure "Tasse in regola"; la prossima scadenza è spiegata a partire dagli avvisi UNIMIA
  (es. "Seconda rata non ancora emessa · scadenza 2 febbraio 2027 – Pagabile con PagoPA da un mese prima della
  scadenza"): si ricava a quale rata si riferisce e se è già stata emessa (presente fra le righe della situazione
  amministrativa). La nota riporta solo ciò che dice l'avviso, senza date calcolate.

### Orario

- Settimana navigabile, lezioni raggruppate per giorno, dettaglio con aula, sede, docente e **Apri in Mappe**; nel dettaglio
  il nome completo dell'insegnamento è in alto e, se lungo, si espande con un tap; "Quando" riporta il giorno della
  settimana e, sotto, l'orario (es. "08:30 – 12:30").
- Pillole dei periodi **centrate** nello stesso blocco dell'intestazione della settimana (riga con angoli superiori
  squadrati, senza separatore); se non ci stanno passano a una versione
  compatta e poi a etichette brevi ("1° trimestre", "2° trimestre", "3° trimestre"), e solo come ultima risorsa
  scorrono. Lo stesso vale per gli anni negli Esami.
- Nomi dei corsi leggibili ovunque: "DBD - NEUROPSICOLOGIA CLINICA E SPERIMENTALE (Classe LM-51 R) (CDS MAGISTRALE)"
  diventa "Neuropsicologia clinica e sperimentale · LM-51 R"; i docenti passano da "ROSSI MARIO" a "Rossi Mario".
- **Vai a data**: scelta una data (es. 7 ottobre 2026) porta alla sua settimana (5–11 ottobre); se la data cade in un
  altro periodo didattico, cambia anche la pillola del periodo.
- **Pillole dei periodi** lette dall'API (semestri, trimestri, quadrimestri, annuale); default: periodo in corso.
- Menu: **Insegnamenti…** (attivazione per anno / singolo insegnamento), **Cambia corso…**
  (scuola → tipo di laurea → corso, con ricerca), **Torna al mio corso**.
- Default: il corso dell'utente, ricavato dal codice corso UNIMIA (es. `DBD`) incrociato con l'albero Agenda.

### Ariel

- Offerta dell'anno accademico corrente: corsi con sito attivo in cima; quelli senza sito didattico sono raccolti in
  un gruppo richiudibile. Ogni riga: titolo, codice e titolari su una riga.
- Dettaglio corso: titolo in alto, una sezione per ogni sezione Moodle con icone allineate; descrizioni e post con
  grassetto, corsivo ed elenchi puntati. Scheda insegnamento (obiettivi, periodo, lingua, docenti, link), **Calendario lezioni**
  (modal compatto con le sole lezioni della materia dalle API Agenda, raggruppate per mese), contenuti per sezione, moduli con descrizione,
  file (anteprima Quick Look), forum e discussioni, partecipanti, valutazioni.

### Registrazioni

- Registrazione vocale collegata a un insegnamento attivato (suggerito automaticamente se c'è una lezione in corso),
  scelto da un selettore a tutta larghezza allineato a sinistra.
- Timer, livello microfono, pausa/ripresa, **segnalibri**, annulla; continua a schermo bloccato e si mette in pausa
  durante le telefonate.
- Archivio ordinato per insegnamento: la schermata principale elenca solo gli insegnamenti che hanno registrazioni
  (numero, durata totale, data dell'ultima); toccandone uno si apre il suo elenco. La ricerca per titolo,
  insegnamento o note mostra i risultati in un'unica lista.
- Dettaglio: player (±15/30 s, velocità 0,75–2×, salto ai segnalibri), titolo, insegnamento, note, condivisione, eliminazione.
- **Eliminazione** (dal dettaglio o con lo swipe) sempre con conferma: rimuove audio, metadati, trascrizione, riassunto e la
  voce di `registrazioni.json`, e ferma trascrizioni o riassunti in corso per quella registrazione.
- **Riconciliazione all'avvio** fra file e indice:
  - audio senza voce nell'indice → ripristinato dal file di metadati `<id>.json`; se manca (registrazioni fatte con
    versioni precedenti), data e durata si ricavano dal file audio e l'insegnamento dalla lezione in orario a quell'ora;
  - registrazione interrotta dalla chiusura dell'app → ripristinata dai metadati provvisori scritti all'avvio;
  - voce senza audio → rimossa; trascrizioni, riassunti e metadati rimasti senza audio → eliminati.
  Un avviso all'avvio chiede se controllare subito o più tardi; le registrazioni ricostruite restano nella sezione
  **Da verificare** in fondo a Registrazioni (ascolto, data e ora modificabili, insegnamento, "I dati sono corretti").
- **Miglioramento dell'audio** (automatico dopo ogni registrazione, disattivabile in Impostazioni; manuale dal
  dettaglio per le registrazioni precedenti), pensato per lezioni registrate da lontano, in `MiglioramentoAudio`:
  riduzione del rumore spettrale (STFT con vDSP, stima continua del fondo per frequenza, massimo −12 dB), equalizzazione
  per la voce (passa-alto 90 Hz, −2 dB a 250 Hz, +4 dB a 3 kHz, passa-basso 7,5 kHz), espansore e compressore con
  soglie ricavate dalla registrazione, normalizzazione a −16 LUFS con limitatore a −3 dBFS. Tutto in streaming, senza
  file temporanei PCM. Su una lezione reale di 2 h 41 min (−38,9 LUFS): −16,6 LUFS, distanza voce/pause da 8,9 a
  17,8 dB (`ffmpeg loudnorm` arriva a −23 LUFS e lascia la distanza a 8,5 dB); 48 s su Mac, 32 MB di memoria.
  L'originale resta in `<id>.originale.m4a` e si può ripristinare; la trascrizione usa la versione migliorata.
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
- **Protezioni** contro elaborazioni inutili e riassunti inventati:
  - trascrizione solo per registrazioni di almeno **1 minuto**, riassunto solo da **5 minuti** (controllo sia nell'interfaccia
    sia nel gestore dei lavori, con il motivo mostrato al posto del pulsante);
  - riassunto solo se la trascrizione ha almeno **150 parole** e **60 parole diverse** (il parlato di riempimento
    ripetuto viene scartato);
  - verifica preliminare con il modello ("il testo spiega argomenti di una lezione?"): saluti, attese, prove microfono
    e chiacchiere vengono rifiutati;
  - il nome della materia **non** entra nei prompt e il modello deve usare solo il testo trascritto, rispondendo con un
    segnale dedicato quando non c'è materiale (convertito in errore, mai mostrato come riassunto).

### Altro

- **Carriera e libretto**: profilo, recapiti, libretto, esiti da accettare, PDF "prossimi appelli" del corso. Nomi,
  stato d'iscrizione e indirizzi sono normalizzati ("via mario rossi 10 20100 milano MI italia" → "Via Mario Rossi 10,
  20100 Milano (MI), Italia").
- **Tasse e pagamenti**: righe della situazione amministrativa con voci leggibili ("CONTRIB. REGIONE LOMBARDIA" →
  "Contributo Regione Lombardia") e una riga per rata ("Rata 1 · pagata l'11 settembre 2026" con la spunta), totali,
  prossima scadenza, avvisi con la grafia corretta ("E' … puo' … Pago PA" → "È … può … PagoPA"), link ai pagamenti SIFA.
- **Esami**
  - _Calendario_: appelli dalle API Agenda per corso e anno (pillole), raggruppati per settimana, corso modificabile
    dal menu; **Vai a data** fa partire il calendario dalla settimana scelta (anche nel passato), _Oggi_ torna al presente.
  - _Iscrizioni_: prenotazioni confermate, esiti da accettare, pulsante **Iscriviti a un appello** che apre la replica di
    "Esami del tuo corso di studio" (ricerca per insegnamento, nomi leggibili, codice · CFU). Il pulsante **Iscriviti**
    fa come sul sito: apre _Selezione appello_ con gli appelli disponibili per quell'esame (data, orario e dettagli)
    o "Nessun appello disponibile."; la conferma dell'iscrizione per ora resta sul sito ufficiale (link in fondo).
  - Appelli con data compatta ("mer 30 settembre · 11:00"), messaggi vuoti riscritti ("Nessuna prenotazione confermata").
- **Aule**: sedi espandibili toccando la riga intera, con le aule e lo stato attuale (libera / occupata fino alle…),
  "1 aula / 2 aule", indirizzo in formato italiano ("Via Celoria 2, 20133 Milano") e **Apri in Mappe**; ricerca sempre
  visibile per sede, aula o indirizzo; _Dove si tiene_ cerca le attività della giornata odierna.
- **Presenze**: registrazione presenza con codice lezione (digitato o da **QR**, con slider di zoom fino a 5× per i
  codici proiettati lontano), risposta del server mostrata così com'è;
  frequenza per corso con barra e **tacca sulla soglia**, dettaglio con riepilogo ("mancano 18 h per la soglia del 50%")
  e lezioni future attenuate.
  - **Soglia di frequenza**: EasyBadge restituisce un proprio valore (`percentuale_conseguimento`, es. 0,7) che non
    coincide con il regolamento; l'app legge l'obbligo di frequenza dal **manifesto degli studi** del corso (es. "almeno
    il 50% del monte ore"), con link al PDF. In _Impostazioni_ si può scegliere una soglia diversa.
- **Impostazioni**: foto profilo, account (nome e corso leggibili), soglia di frequenza, stato delle sessioni (pallino
  verde / grigio), dati salvati, aggiornamento profilo, uscita
  (con scelta se conservare o eliminare registrazioni, foto e cache).
- **Crediti** (sezione separata in fondo): servizi dell'Ateneo, piattaforme (Moodle, EasyStaff/EasyAcademy) e tecnologie
  Apple usate, ciascuno con il proprio link. Disclaimer e copyright con la versione dell'app stanno in fondo ad _Altro_.

### Mappe

Tutti i collegamenti a Mappe usano l'**indirizzo della sede presa da EasyRoom**: per codice aula (gli appelli usano
lo stesso `room_code` di EasyRoom, es. `33230#4001`), poi per nome aula + sede, poi per sede; ricerca testuale solo come
ultima risorsa.

---

### Lingua

Tutte le date e i numeri sono in italiano (`Formats.it`, `Date.italiano(date:time:)`, `relativoItaliano`),
indipendentemente dalla lingua del dispositivo; l'italiano è anche la lingua di sviluppo del progetto.

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

Per installare nel simulatore conviene la build firmata ("Sign to Run Locally", senza `CODE_SIGNING_ALLOWED=NO`):
una build non firmata non ha l'`application-identifier` del team e quindi non vede le credenziali salvate nel
Portachiavi dalla build di Xcode.

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
| Selezione appello | GET del link _Iscrizione_ della riga (`../wicket/page?N-1.ILinkListener-form-listEsamiPanel-table-body-rows-K-cells-4-cell-actionButton`, valido solo per la pagina appena caricata) → `iscrizioneAppelloPack/SelezioneAppelloPage?M`: `h4` esame, `ul.nomarker` appelli, "Nessun appello disponibile.", form `esame/selezioneAppello?M-1.IFormSubmitListener-form` con pulsante _Indietro_ |
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

### Manifesti degli studi — `https://apps.unimi.it/files/manifesti/`

PDF pubblici, nessun cookie: `ita_manifesto_{CODICE}of{N}_{anno di fine a.a.}.pdf` (es. `ita_manifesto_DBDof2_2027.pdf`
per l'a.a. 2026/27). Nello stesso anno ogni `ofN` è una **coorte** diversa (`of1` = immatricolati 2025/26, `of2` =
immatricolati 2026/27, riga "Immatricolati nell'Anno Accademico …"): l'app prova gli indici in ordine e sceglie quello
della coorte dello studente (anno di corso da UNIMIA). Dal testo (PDFKit) legge "È richiesta una frequenza di almeno
il **50%** del monte ore…". Il risultato è salvato e riletto solo quando cambiano corso, anno di corso o anno accademico.

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
  (totale = fatte + da fare; soglia EasyBadge = `percentuale_conseguimento` × totale, sostituita in app da quella del
  manifesto).
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
| Registrazioni                                                                                              | `Application Support/Registrazioni/<id>.m4a` (AAC mono 64 kbps, ~29 MB/ora) + metadati `<id>.json` + indice `registrazioni.json` |
| Trascrizioni e riassunti                                                                                   | `Application Support/Registrazioni/<id>.txt` e `<id>.riassunto.md`, separati dall'indice                                  |
| Audio originale (se migliorato)                                                                            | `Application Support/Registrazioni/<id>.originale.m4a`; `<id>.m4a` è la versione migliorata                                |
| Cookie di sessione                                                                                         | `HTTPCookieStorage` di sistema                                                                                            |
| Orario, appelli, tasse, presenze, aule, esiti, partecipanti                                                | solo in memoria                                                                                                           |

**Registrazioni**: `<id>.json` contiene gli stessi campi della voce dell'indice (data e ora d'inizio, durata, insegnamento,
titolo, segnalibri, note, date di trascrizione e riassunto) e viene scritto all'avvio della registrazione (`inCorso: true`)
e a ogni modifica: l'indice si può sempre ricostruire dai file. Date in ISO 8601 sia in scrittura sia in lettura.

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

- [ ] **Iscrizione agli appelli** da app: la lista degli appelli disponibili (`SifaService.appelliDisponibili`) funziona;
      mancano la scelta dell'appello e la conferma, da osservare quando ci saranno appelli aperti (struttura delle
      righe di `ul.nomarker`, campo del modulo, pagina di conferma).
- [ ] **Pagamenti SIFA**
- [ ] **Formato del QR** del codice lezione: `QRLezione.codice(from:)` oggi usa il testo letto così com'è.
- [ ] **Prenotazioni**: le colonne di una prenotazione reale non sono ancora state osservate; data ed esame sono
      ricavati per euristica (`Prenotazione.from`).
- [ ] Libretto, esiti da accettare e cartelle Ariel con file: parsing generico, da rifinire su casi popolati.
- [ ] Piano di studi (SPA con XHR interne) non integrato.
- [ ] Media Aritmetica/Ponderata

---

## Copyright

© 2026 Mattia Meligeni. Tutti i diritti riservati.

Statale+ è un'app indipendente e non ufficiale: non è affiliata, sponsorizzata né approvata dall'Università degli Studi
di Milano. Nomi e marchi dei servizi citati appartengono ai rispettivi titolari. I dati sono letti dai servizi
dell'Ateneo e potrebbero non essere aggiornati: in caso di dubbio fa fede sempre il sito ufficiale.

---

## Contribuire

- Ogni modifica va accompagnata dall'aggiornamento di questo README (funzionalità, endpoint, formati, stato dei lavori)
  e da una voce nel [Changelog](#changelog).
- Nessuna dipendenza esterna senza una ragione forte.
- Mai dati personali reali (nomi, matricole, indirizzi) nel codice, nei commenti o nei test: usare segnaposto
  (`MARIO ROSSI`, `12345A`).

---

## Changelog

### 2026-09-30 (7)

- Registratore e player spostati dentro l'attore `MotoreAudio`: anche `record()`, `play()`, `pause()` e `stop()`
  (che attivano o disattivano la sessione audio da soli) girano fuori dal main thread. Le API asincrone di
  attivazione esistono solo da iOS 27.
- **Miglioramento dell'audio** delle registrazioni (volume, rumore di fondo, voce), automatico o manuale, con
  ripristino dell'originale.
- Slider di zoom nella scansione del QR della lezione.

### 2026-09-30 (6)

- Sessione audio configurata, attivata e disattivata fuori dal main thread (attore `SessioneAudio`), anche per il player
  (tolto `prepareToPlay()`, che la attivava in modo sincrono): risolto l'avviso "AVAudioSession Hang Risk" di Xcode.

### 2026-09-30 (5)

- **Registrazioni, persistenza**: `registrazioni.json` veniva scritto con le date in ISO 8601 ma letto con il formato
  predefinito (numero): all'avvio la lettura falliva in silenzio, la lista partiva vuota e il primo salvataggio scriveva
  `[]` (i file restavano sul disco senza voce). Ora lettura e scrittura usano lo stesso formato (con lettura tollerante),
  e gli errori di scrittura ed eliminazione vengono registrati e mostrati invece di essere ignorati.
- Quarto file per registrazione, `<id>.json` con i metadati; riconciliazione all'avvio con avviso e sezione "Da verificare".
- Eliminazione con conferma che toglie anche trascrizione, riassunto, metadati e voce dell'indice.

### 2026-09-30 (4)

- Esami › Iscrizioni: **Iscriviti** apre la lista degli appelli disponibili, come "Selezione appello" di SIFA
  (verificato sul sito e nell'app: al momento nessun appello aperto per nessun esame del corso).
- Orario: riga della settimana di nuovo attaccata alle pillole, con angoli superiori squadrati.

### 2026-09-30 (3)

- Oggi: pulsanti di nuovo affiancati con testo su due righe, sigillo pieno per "Presenza registrata"; appello e avvisi
  uniti in una riga solo se entrambi vuoti; data con il mese minuscolo; righe segnaposto durante il caricamento.
- Orario ed Esami: pillole centrate insieme all'intestazione della settimana / "Vai a data" (versione compatta ed
  etichette brevi per tre trimestri); spazio fra selettore Calendario/Iscrizioni e nome del corso, niente fascia bianca.
- Presenze: soglia di frequenza dal manifesto degli studi (50% invece del 70% di EasyBadge) o scelta in Impostazioni;
  tacca sulla barra, riepilogo nel dettaglio, matricola in maiuscolo.
- Tasse: nota PagoPA fedele all'avviso (nessuna data calcolata), voci e date leggibili, avvisi con accenti corretti,
  titolo "Tasse e pagamenti".
- Esami › Iscrizioni: nomi leggibili, ricerca "Cerca insegnamento", pulsante leggero, messaggi vuoti riscritti.
- Aule: riga intera toccabile, "1 aula", indirizzo in formato italiano, Apri in Mappe.
- Impostazioni: nome e corso leggibili, sessioni con pallino; Crediti senza disclaimer doppio, sezione "Ateneo".
- "Aggiornato alle…" sempre in una sezione propria (non taglia più gli angoli della riga sopra).

### 2026-09-30 (2)

- Oggi: pulsanti rapidi mai a capo, "Presenza registrata" compatta, nota delle tasse allineata al testo, sezioni vuote
  raccolte in una riga, aula e sede su due righe anche per appelli e prenotazioni.
- Orario ed Esami: pillole e settimana in blocchi separati; nomi dei corsi e dei docenti leggibili anche nel selettore
  dei corsi e negli insegnamenti.
- Dettaglio lezione: giorno della settimana e orari "08:30", meno spazio in alto, sfondo pieno.
- Ariel: corsi senza sito in un gruppo richiudibile, titolo del corso e sezioni Moodle, icone allineate, testo con
  grassetto/corsivo/elenchi, calendario lezioni compatto per mese.
- Carriera: corso, stato e indirizzi normalizzati.
- Registrazioni: selettore dell'insegnamento allineato a sinistra.

### 2026-09-30

- Date sempre in italiano (niente più "last week", "Sep", "February"); italiano come lingua di sviluppo.
- Tasse in Oggi e nella schermata Tasse: scadenza spiegata (quale rata, se emessa, da quando si può pagare).
- Avvisi Ariel di nuovo sugli ultimi 7 giorni.
- Pulsanti rapidi in Oggi senza icone; icona bianca su "Avvia registrazione"; più spazio nella schermata Registrazioni.
- Dettaglio lezione con nome completo espandibile.
- Login: mostra password, messaggio di CAS in caso di rifiuto, log diagnostico; codifica corretta delle lettere accentate
  nella password.

### 2026-09-29 (8)

- Altro: sezione **Crediti** con i servizi usati e i relativi link; nota di disclaimer e copyright in fondo.
- Registrazioni: soglie minime (trascrizione ≥ 1 min, riassunto ≥ 5 min e ≥ 150 parole / 60 diverse), verifica
  preliminare del contenuto e prompt senza nome della materia, per evitare riassunti inventati su audio vuoti.

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
