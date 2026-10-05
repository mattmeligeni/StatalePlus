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
- **Avvisi Ariel** (discussioni dei forum dei corsi attivi): pallino blu per quelli da leggere, in cima; una
  discussione diventa letta quando la apri nell'app (da Oggi o dal forum del corso) e torna da leggere se arrivano
  risposte dopo. I non letti restano visibili fino a 30 giorni, i letti per 7. Le letture sono salvate sul
  dispositivo (Moodle non le espone) e cancellate all'uscita dall'account. Se Ariel non risponde compare l'errore con
  "Riprova" invece di "Nessun avviso recente".
- Se appello prenotato e avvisi sono **entrambi** vuoti, una sola riga discreta ("Nessun appello prenotato e nessun
  avviso Ariel negli ultimi 7 giorni"); se almeno uno ha elementi, le due sezioni restano separate.
- Durante il primo caricamento ogni sezione mostra una riga segnaposto sfumata al posto della rotellina.
- **Tasse**: importo da pagare oppure "Tasse in regola"; la prossima scadenza è spiegata a partire dagli avvisi UNIMIA
  (es. "Seconda rata non ancora emessa · scadenza 2 febbraio 2027 – Pagabile con PagoPA da un mese prima della
  scadenza"): si ricava a quale rata si riferisce e se è già stata emessa (presente fra le righe della situazione
  amministrativa). La nota riporta solo ciò che dice l'avviso, senza date calcolate.

### Orario

- **Modifiche locali alle lezioni** (per i corsi in cui il docente non aggiorna l'Agenda web): nel dettaglio della lezione,
  sotto "Apri in Mappe", l'interruttore **Lezione annullata** e il pulsante rosso **Modifica** (aula e sede scelte
  dall'elenco EasyRoom, così Mappe porta all'indirizzo giusto, oppure scritte a mano; docente; annullata). Le lezioni
  modificate mostrano "Modificata da te", i valori dell'Agenda e **Ripristina**. Valgono solo sul dispositivo (in Oggi,
  Orario e calendario del corso), con l'avviso che non possono essere verificate; cancellate all'uscita dall'account.
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
  grassetto, corsivo ed elenchi puntati. Un tap sul nome del docente apre il suo **riepilogo** (dal blocco W4
  "Titolare del sito"): ruolo, ricevimento e luogo, email, telefono, dipartimento, indirizzo (Mappe), sede e
  curriculum (PDF aperto nell'app con Quick Look). Email e CV non sono ripetuti nella schermata del corso. Scheda
  insegnamento (obiettivi, periodo, lingua, docenti), **Calendario lezioni**
  (modal compatto con le sole lezioni della materia dalle API Agenda, raggruppate per mese), contenuti per sezione, moduli con descrizione,
  file (anteprima Quick Look), forum e discussioni, partecipanti, valutazioni.

- **Scadenze ed eventi** (calendario myAriel, prossimi 21 giorni più le consegne in ritardo) e **Notifiche**
  (nuovi post nei forum seguiti, valutazioni, consegne; badge con le non lette) in cima alla lista dei corsi.
  Aprire una notifica la segna come letta come sul sito; quelle dei forum aprono la discussione nell'app, le altre
  mostrano il testo completo. Le scadenze sono solo informative (nome, corso, data, luogo, "in ritardo").
- **Scarica tutti i materiali** nel dettaglio del corso: lo zip di "Scaricamento contenuti del corso" (esclusi i file
  oltre 50 MB), scritto direttamente su disco, da aprire con Quick Look o salvare in File.
- In Oggi: sezione **Scadenze Ariel** (consegne in ritardo ed eventi dei prossimi 7 giorni, solo se ce ne sono) e riga
  con le notifiche non lette in cima agli avvisi.

### Registrazioni

- Registrazione vocale collegata a un insegnamento attivato (suggerito automaticamente se c'è una lezione in corso),
  scelto da un selettore a tutta larghezza allineato a sinistra.
- Timer, livello microfono, pausa/ripresa, **segnalibri**, annulla; continua a schermo bloccato e si mette in pausa
  durante le telefonate.
- Archivio ordinato per insegnamento: la schermata principale elenca solo gli insegnamenti che hanno registrazioni
  (numero, durata totale, data dell'ultima); toccandone uno si apre il suo elenco. La ricerca per titolo,
  insegnamento o note mostra i risultati in un'unica lista.
- Dettaglio: player (±15/30 s, velocità 0,75–2×, salto ai segnalibri), titolo, insegnamento, note, condivisione, eliminazione.
  - L'audio continua aprendo trascrizione o riassunto a pagina intera, dove compare un mini player (pausa, ±15/30 s,
    tempo). Quelle schermate "tengono" il player (`AudioPlayer.utilizzatori`); il dettaglio lo chiude solo se, uscendo,
    nessuna lo sta usando. Se era chiuso, il play riapre il file dal punto in cui era.
- **Condivisione dell'audio con un nome leggibile** ("Colloquio e processo anamnestico – 30 set 2026, ore 10.15.m4a"
  invece di `<id>.m4a`), ricavato al momento da titolo, data e ora, quindi anche per le registrazioni già fatte.
  Sul dispositivo i file restano `<id>.m4a`, perché indice, recupero, trascrizioni e riassunti si basano sull'id. La
  copia da condividere è un clone APFS in `tmp/Condivisi`: istantaneo e senza spazio in più; si elimina dopo un'ora.
- **Backup delle registrazioni** (_Impostazioni › Backup delle registrazioni_, `ArchivioRegistrazioni`).
  - Esporta in un unico file `.aar` (AppleArchive, senza compressione: l'audio è già compresso) audio, originali,
    metadati, trascrizioni e riassunti, da salvare in File o iCloud Drive.
  - L'importazione estrae l'archivio, aggiunge solo le registrazioni che mancano e le inserisce nell'elenco tramite il
    normale recupero dai file.
  - Serve per cambiare iPhone e per il passaggio a un altro team di sviluppo: iOS non aggiorna un'app firmata con un
    identificativo diverso, quindi va disinstallata, e disinstallando si perdono i dati.
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
  L'originale resta in `<id>.originale.m4a` e si può ripristinare. La trascrizione usa sempre l'originale: nelle prove
  il miglioramento non aiuta Apple e Parakeet (con Apple i termini riconosciuti scendono da 197 a 180).
- **Trascrizione** in italiano, con tre motori a scelta in _Altro › IA › Trascrizione_ (sotto la
  trascrizione c'è la nota "Sono disponibili altri modelli più accurati" con il collegamento alla scelta):
  - **Apple** (predefinito): locale, privato, veloce e leggero.
    - iOS 26+: `SpeechAnalyzer` + `SpeechTranscriber` con il preset `.transcription` (quello più accurato, per
      dettatura e audio lunghi). Niente parole di contesto (`AnalysisContext`): su una lezione di 2 ore e mezza, un
      vocabolario di 63 termini lascia il testo identico. `DictationTranscriber` perde più di metà delle parole.
      Il modello della lingua viene scaricato la prima volta.
    - iOS 17–25: `SFSpeechRecognizer` a blocchi di 50 s, on-device quando supportato, con punteggiatura.
  - **Parakeet** (NVIDIA Parakeet TDT 0.6B v3, versione "Ultra", con FluidAudio): locale, più accurato, download di
    **632 MB**. Lavora sul Neural Engine con circa 90 MB di memoria e legge il file a blocchi dal disco.
    - Prima del download un avviso mostra dimensione, spazio libero, rete (Wi-Fi consigliato, possibili costi su
      rete cellulare), primo piano, consumi e privacy.
    - Barra del download in MB, calcolata sui byte: file completati più file parziali (0-90%).
    - Dopo il download il telefono prepara il modello, e richiede qualche minuto. La barra continua a muoversi
      (90-99%) perché iOS chiude le attività in background che sembrano ferme.
    - Controlli di integrità:
      - ogni download riparte da capo;
      - alla fine si verificano dimensione (632 314 500 byte) e caricamento dei modelli, prima di scrivere il marcatore;
      - all'avvio un modello segnato come scaricato ma incompleto si elimina, con un avviso;
      - se alla trascrizione il modello non si carica, il marcatore si toglie e si chiede di riscaricarlo.
      Prima un download interrotto lasciava cartelle incomplete che FluidAudio considerava complete: al secondo
      tocco Parakeet risultava scaricato e le trascrizioni fallivano.
    - Un download fermato da iOS mostra un errore ("Download interrotto da iOS…"). Prima veniva trattato come un
      "Annulla" e sembrava non partito.
    - Il modello sta in `Application Support/Modelli/parakeet-ultra`, escluso dal backup, con un marcatore scritto a
      download finito. Si può annullare il download o eliminare il modello.
    - Filtro per le ripetizioni a ciclo (`senzaRipetizioni`), comune a tutti i motori.
  - **Remoto Pro**  - **Remoto Pro**: a pagamento, non ancora disponibile (mostrato disattivato).
  - **Prove**, misurate su Mac M1 Pro.
    - Lezione reale di 2 h 25 min registrata da lontano (−31,7 LUFS); conteggio di circa 60 termini di neuroanatomia:

      | Motore | Tempo | Termini riconosciuti | Ripetizioni a ciclo |
      | --- | --- | --- | --- |
      | Apple | 74 s | 197 | 7 |
      | Whisper Turbo 626 MB | 16–19 min | 202–211 | 52–103 |
      | Parakeet Ultra | 40 s, 92 MB | 241 | 18 |
      | Qwen3-ASR 1.7B (MLX) | ~9 min | 272 | 189 |

    - Testo con riferimento esatto (12,7 min letti da una voce sintetica), errore sulle parole (WER):

      | Motore | Audio pulito | Audio "da fondo aula" |
      | --- | --- | --- |
      | Qwen3-ASR 1.7B | 4,2% | 6,2% |
      | Whisper Turbo | 5,7% | 7,5% |
      | Parakeet Ultra | 6,5% | 7,9% |
      | Apple | 8,1% | 9,3% |

      Nell'app, nel simulatore, Parakeet fa 6,4%.
    - Su audio pulito i motori sono vicini. Parakeet è stato scelto per l'equilibrio: velocità (25 volte Whisper),
      niente frasi inventate né cicli su audio difficile, Neural Engine, pochi consumi.
    - Whisper è stato tolto (il modello scaricato si cancella da solo, 626 MB): è lento e su audio registrato da
      lontano inventa ("Grazie.") e ripete.
    - Qwen3-ASR è il più preciso, ma più lento, usa la GPU e ogni tanto ripete a lungo: per ora non incluso.
  - Avanzamento e annulla; continua anche uscendo dalla schermata. Testo in paragrafi, modificabile, con **Writing Tools**
    (iOS 18+), conteggio parole, condivisione, nuova trascrizione.
- **Riassunto** con due motori a scelta in _Altro › IA › Riassunti_.
  - **Qwen 3.5 4B** (Alibaba, Apache 2.0, `mlx-community/Qwen3.5-4B-4bit`) con MLX sulla GPU: download di **3 GB**, solo
    iPhone con almeno 8 GB di memoria.
    - Lavora a sezioni con memoria: blocchi di circa 2200 parole; per ognuno scrive le sezioni `### Titolo` nuove,
      ricevendo i titoli già scritti per non ripetersi e collegare i concetti. Una passata finale scrive _In breve_,
      _Punti chiave_ e _Da ripassare_.
    - Prove sulla lezione di 2 h 25 min: copre 40 termini su 75, contro i 34 di Apple. Corregge nomi e termini
      storpiati dalla trascrizione ("modo di gambier" → "nodi di Ranvier").
    - Tempi e memoria: circa 5 minuti sul Mac, 4,1 GB di picco con la cache di MLX limitata a 256 MB. Su iPhone si
      stimano 10–15 minuti.
    - In una passata sola è più rapido ma riassume troppo.
    - Prima di iniziare controlla la memoria libera (`os_proc_available_memory`).
    - La GPU non si può usare in background: se si esce dall'app il riassunto va in pausa e riprende al ritorno dalle
      sezioni già scritte.
    - Il tokenizer è quello di swift-transformers, con un adattatore scritto a mano: niente macro di pacchetto da
      abilitare in Xcode.
  - **Apple Intelligence online** (`NuvolaApple`, Private Cloud Compute, iOS 27): il modello più grande di Apple sui
    suoi server, con 32K token di contesto.
    - Usa la stessa pipeline a sezioni di Qwen (`RiassuntoASezioni`), con blocchi da circa 6000 parole.
    - Mostra il limite giornaliero di richieste e l'offerta di Apple per alzarlo con iCloud+.
    - Serve l'entitlement `com.apple.developer.private-cloud-compute`, concesso da Apple su richiesta a chi è
      nell'App Store Small Business Program. Finché manca, `StatalePCCAutorizzata = NO` in Info.plist e l'opzione
      non compare (al suo posto "Remoto Pro · Presto").
  - **Apple Intelligence** (FoundationModels, iOS 26+, modello on-device di sistema, solo se disponibile):
    - La trascrizione è divisa in parti di circa 4000 caratteri, perché il modello ha un contesto di ~4K token. Se una
      parte non ci sta si divide solo quella e si va avanti. Prima si ricominciava da capo con parti più piccole: su
      una lezione di 2 h 25 min si passava da 27 a 41 a 58 parti, 19 minuti invece di circa 6.
    - Ogni parte diventa appunti strutturati con generazione guidata (`@Generable`): titolo, riassunto di un
      paragrafo, 3–6 punti chiave, 2–3 domande.
    - Il documento finale contiene _In breve_, _Riassunto_ con un paragrafo per parte, _Punti chiave_ senza duplicati
      e _Da ripassare_ numerato.
    - Se Apple Intelligence è disattivata o in download, l'app lo indica.
  - Visualizzazione formattata, modifica con Writing Tools, rigenerazione.
  - **PDF A4** da condividere o stampare: è generato dall'app con titolo, insegnamento e data.
- **Glossario del corso** (_Altro › IA › Glossario del corso_, `GlossarioCorso`, `GestoreGlossario`): termini del corso
  per correggere le parole storpiate dalla trascrizione ("dopamila" → "dopamina").
  - Creazione: una richiesta per insegnamento (60 termini: concetti, strutture, sostanze, test, sindromi, metodi,
    autori), più nomi degli insegnamenti e cognomi dei docenti. Modello usato, in ordine: Apple Intelligence online se
    autorizzata, Qwen, Apple Intelligence sul telefono. Si crea da solo alla fine del download di Qwen; i termini si
    possono aggiungere e togliere a mano.
  - Correzione (`CorrettoreTermini`), automatica sulle nuove trascrizioni e su richiesta su quelle già fatte. Una parola
    si sostituisce solo se:
    - il correttore ortografico italiano di iOS non la conosce;
    - non è una parola inglese valida;
    - ha almeno 6 lettere;
    - un solo termine le è vicinissimo: 1 lettera di differenza, 2 dalle 10 lettere in su;
    - non è solo un'altra forma della stessa parola (singolare e plurale, derivati, parola contenuta nell'altra);
    - mantiene la desinenza trascritta, e la maiuscola resta solo per i nomi propri.
  - Prove: su 20 minuti di psicofarmacologia corregge "dopamila", "dopamita", "dopamia" e "serotonnina" in 0,08 s;
    sulla lezione di neuroanatomia corregge "bidollo" e "mitollo" in "midollo" e "cebelletto" in "cervelletto". Le regole
    sono state ristrette dopo correzioni sbagliate ("endogrine" → "endorfine", "neurotrasmettitore" al plurale).
  - FluidAudio ha un sistema per suggerire parole a Parakeet, ma usa un modello aggiuntivo solo in inglese: non
    adatto all'italiano.
- **Catena automatica** (attiva per impostazione predefinita, _Altro › IA › Dopo ogni registrazione_). Alla fine di una
  registrazione partono, uno dopo l'altro, trascrizione, riassunto e miglioramento dell'audio: quando si apre la
  lezione è già tutto pronto. Uno dopo l'altro per non contendersi Neural Engine, GPU e CPU.
- **Lavori lunghi in background** (`EsecuzioneEstesa`): trascrizione, riassunto, miglioramento dell'audio e download dei
  modelli.
  - Da iOS 26 usano `BGContinuedProcessingTask`: si può uscire dall'app e iOS mostra l'attività con barra e pulsante
    per annullare (non si può nascondere, per questo non c'è una Live Activity dell'app). Ha una sola riga di
    sottotitolo: solo fase e tempo stimato, ad esempio "312 di 632 MB · circa 2 min" o "Trascritti 5 di 13 min · meno
    di un minuto". Il titolo è il tipo di lavoro ("Trascrizione", "Riassunto", "Download di Qwen").
  - GPU (Qwen) e, da iOS 27, Neural Engine in background richiedono entitlement ("Background GPU Access",
    "Background Inference") che gli account sviluppatore personali non hanno. Con l'account a pagamento Qwen chiede
    la GPU in background (`EsecuzioneEstesa.esegui(gpu: true)`, `requiredResources = .gpu`, `gpuConcessa`) dove iOS la
    supporta.
    - Senza GPU in background il lavoro non passa dall'attività di sistema: iOS la chiudeva subito e il riassunto
      sembrava non partire.
    - Un'interruzione non chiesta dall'utente ora mostra un errore.
    - Un lavoro che si ferma per questo resta "in pausa" e riparte da solo al ritorno in
      primo piano (`PrimoPiano`, `ElaborazioniAudio.sospendi`).
    - Parakeet nel simulatore continua in background.
  - Prima di iOS 26 c'è il tempo extra di `beginBackgroundTask`.
  - Il lavoro pesante gira fuori dal main thread (attori e funzioni `@concurrent`).
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

- **Carriera e libretto**: profilo, recapiti, libretto, esiti da accettare. Nomi,
  stato d'iscrizione e indirizzi sono normalizzati ("via mario rossi 10 20100 milano MI italia" → "Via Mario Rossi 10,
  20100 Milano (MI), Italia").
- **Tasse e pagamenti**: righe della situazione amministrativa con voci leggibili ("CONTRIB. REGIONE LOMBARDIA" →
  "Contributo Regione Lombardia") e una riga per rata ("Rata 1 · pagata l'11 settembre 2026" con la spunta), totali,
  prossima scadenza, avvisi con la grafia corretta ("E' … puo' … Pago PA" → "È … può … PagoPA").
- **Esami**
  - _Calendario_: appelli dalle API Agenda per corso e anno (pillole), raggruppati per settimana, corso modificabile
    dal menu; **Vai a data** fa partire il calendario dalla settimana scelta (anche nel passato), _Oggi_ torna al presente.
  - _Iscrizioni_: prenotazioni confermate, esiti da accettare, pulsante **Iscriviti a un appello** che apre la replica di
    "Esami del tuo corso di studio" (ricerca per insegnamento, nomi leggibili, codice · CFU). Il pulsante **Iscriviti**
    fa come sul sito: apre _Selezione appello_ con gli appelli disponibili per quell'esame (data, orario e dettagli)
    o "Nessun appello disponibile."; la conferma dell'iscrizione non è ancora nell'app.
  - Appelli con data compatta ("mer 30 settembre · 11:00"), messaggi vuoti riscritti ("Nessuna prenotazione confermata").
- **Aule**: sedi espandibili toccando la riga intera, con le aule e lo stato attuale (libera / occupata fino alle…),
  "1 aula / 2 aule", indirizzo in formato italiano ("Via Celoria 2, 20133 Milano") e **Apri in Mappe**; ricerca sempre
  visibile per sede, aula o indirizzo; _Dove si tiene_ cerca le attività della giornata odierna.
- **Presenze**: registrazione presenza con codice lezione digitato o da **QR** (slider di zoom fino a 5× per i codici
  proiettati lontano; dopo la scansione la richiesta parte subito, perché il QR in aula cambia di continuo).
  Esiti: `ok` → "Presenza registrata", `warning` → "Presenza già registrata" (conta come confermata), `failure` →
  "Rilevazione non riuscita" con spiegazione (docente che ha chiuso la rilevazione, codice sbagliato o scaduto: il
  server usa lo stesso messaggio per tutti i casi). Per `ok` e `failure` l'esito si apre **a tutto schermo** (verde
  "Presenza registrata" / rosso "Presenza NON registrata", con vibrazione e, se fallita, "Scansiona di nuovo"):
  prima era troppo discreto e gli studenti riprovavano per sicurezza. L'esito resta anche in una sezione sotto il pulsante;
  frequenza per corso con barra e **tacca sulla soglia**, dettaglio con riepilogo ("mancano 18 h per la soglia del 50%")
  e lezioni future attenuate.
  - **Soglia di frequenza**: EasyBadge restituisce un proprio valore (`percentuale_conseguimento`, es. 0,7) che non
    coincide con il regolamento; l'app legge l'obbligo di frequenza dal **manifesto degli studi** del corso (es. "almeno
    il 50% del monte ore"); il PDF del manifesto si apre nell'app con Quick Look. In _Impostazioni_ si può scegliere
    una soglia diversa.
- **Impostazioni**: foto profilo, account (nome e corso leggibili), soglia di frequenza, stato delle sessioni (pallino
  verde / grigio), dati salvati, aggiornamento profilo, uscita
  (con scelta se conservare o eliminare registrazioni, foto e cache).
- **IA** (icona processore): raccoglie tutte le impostazioni dei modelli, in vista di eventuali servizi cloud:
  - motore di trascrizione (Apple o Parakeet) e motore dei riassunti (Apple Intelligence o Qwen), con download e
    spazio dei modelli;
  - catena automatica dopo ogni registrazione (trascrizione, riassunto, miglioramento);
  - miglioramento automatico dell'audio dopo ogni registrazione;
  - stato di Apple Intelligence per i riassunti (disponibile, disattivata, in download, non supportata), con cosa
    fare;
  - servizi cloud, ancora "Prossimamente": oggi tutto resta sul dispositivo;
  - nota sui lavori lunghi in background.
- **Crediti** (sezione separata in fondo): servizi dell'Ateneo, piattaforme (Moodle, EasyStaff/EasyAcademy) e tecnologie
  Apple usate, i modelli Parakeet (NVIDIA, CC BY 4.0) e Qwen 3.5 (Apache 2.0) e le librerie FluidAudio, MLX Swift e
  swift-transformers, ciascuno con il proprio link. Disclaimer e copyright con la versione dell'app stanno in fondo ad _Altro_.

### Mappe

Tutti i collegamenti a Mappe usano l'**indirizzo della sede presa da EasyRoom**: per codice aula (gli appelli usano
lo stesso `room_code` di EasyRoom, es. `33230#4001`), poi per nome aula + sede, poi per sede; ricerca testuale solo come
ultima risorsa.

---

### Lingua

Tutte le date e i numeri sono in italiano (`Formats.it`, `Date.italiano(date:time:)`, `relativoItaliano`),
indipendentemente dalla lingua del dispositivo; l'italiano è anche la lingua di sviluppo del progetto.

---

### Tastiera

Uguale in tutta l'app (`Tastiera.swift`):

- si chiude toccando un punto qualsiasi fuori dai campi, con uno swipe verso il basso o trascinando il contenuto verso la
  tastiera; i gesti sono sulla finestra, quindi valgono anche nei fogli;
- pulsante **Chiudi** a destra sopra la tastiera, in vetro, grande quanto la scritta. Non usa la barra della tastiera
  di SwiftUI, che su iOS 26 centra il pulsante o allarga il vetro;
- Invio: nei campi di una riga passa al campo successivo o conferma (login: email → password → accedi; modifica
  lezione: aula → sede → docente). Il titolo della registrazione va a capo da solo ma Invio chiude. Va a capo solo
  nei testi lunghi (note, trascrizione, riassunto);
- niente correttore nei campi con codici, nomi e ricerche. Il **codice lezione** è un `UITextField`
  (`CampoCodice`) senza correttore, suggerimenti né previsioni: da iOS 26 `autocorrectionDisabled()` lascia la barra
  dei suggerimenti, che proponeva parole al posto del codice.

### Nessun collegamento esterno

L'app non apre siti web né il browser: ciò che non si può integrare non c'è. I PDF pubblici dell'Ateneo (curriculum
dei docenti, manifesto degli studi) si scaricano e si mostrano con Quick Look (`DocumentiPubblici`, solo host
`*.unimi.it`). Restano solo le app di sistema (Mail, Telefono, Mappe) e i link della sezione Crediti.

## Requisiti e build

- Xcode 27 (Swift 6.4), target **iOS 17.0+**, iPhone e iPad.
- **Dipendenze esterne**, solo per i modelli locali:
  - [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.17.x (Apache 2.0): Parakeet su Core ML;
  - [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) 3.32.x (MIT): Qwen con MLX;
  - [swift-transformers](https://github.com/huggingface/swift-transformers) 1.3.x (Apache 2.0): tokenizer.

  Si portano dietro mlx-swift, swift-huggingface, swift-jinja, swift-collections, swift-crypto e altri pacchetti di
  base. HTML, CSS selector, XML, JSON, Keychain, audio, fotocamera, trascrizione Apple e riassunti Apple usano il
  parser interno e i framework di sistema.

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
`SWIFT_APPROACHABLE_CONCURRENCY = YES`, Info.plist generato + `Statale+-Info.plist` (`UIBackgroundModes = audio,
processing`; `BGTaskSchedulerPermittedIdentifiers = com.mattiameligeni.Statale-.elaborazione.*` per i lavori lunghi),
`ITSAppUsesNonExemptEncryption = NO` (solo HTTPS di sistema) e `StatalePCCAutorizzata` (vedi sopra).
`PrivacyInfo.xcprivacy`: nessun tracciamento, nessun dato raccolto dallo sviluppatore. API dichiarate:
UserDefaults (CA92.1), date dei file (C617.1) e spazio su disco (85F4.1, E174.1).

`Statale+.entitlements` è pronto per l'account Apple Developer a pagamento ma non è ancora collegato al progetto
(`CODE_SIGN_ENTITLEMENTS`): con il team personale la firma fallisce. Contiene _Background GPU Access_ e _Increased
Memory Limit_ (più memoria per Qwen). _Background Inference_ non è ancora assegnabile; Private Cloud Compute si
aggiunge quando Apple concede l'entitlement.

### Versione dimostrativa

Per App Review, TestFlight e chi vuole provare l'app senza un account d'Ateneo:

- **email** `tester@apple-developer.com`
- **password** `StatalePlus-Demo`

Con queste credenziali (`Demo`, `DatiDemo`, `DatiDemoAriel`) l'app non contatta UNIMIA, SIFA, Ariel né l'Agenda: ogni
servizio restituisce dati inventati e coerenti, con una breve attesa come per una richiesta vera. I dati sono:

- lo studente MARIO ROSSI (12345A), al secondo anno di un corso magistrale di neuroscienze (codice `NCN`), con sei
  insegnamenti e docenti di fantasia;
- sedi e aule reali dell'Ateneo, con indirizzi pubblici;
- orario settimanale da sei settimane fa a otto settimane da oggi, una lezione annullata e, in orario di lezione, una
  lezione in corso per provare presenze e registrazione;
- presenze con soglia al 70% e timbratura che riesce sempre;
- appelli passati e futuri, una prenotazione, esami iscrivibili con appelli;
- tasse in regola con la prossima scadenza, libretto del primo anno;
- su Ariel bacheche con avvisi recenti (compaiono in Oggi), materiali (PDF dimostrativi), forum con risposte, scadenze
  (una in ritardo), notifiche lette e non lette, partecipanti e valutazioni;
- due registrazioni, create all'accesso:
  - una già trascritta con Parakeet e riassunta con Qwen: audio di 6 minuti letto da una voce sintetica, con il testo
    di una lezione scritta per la demo; file in `Risorse/Demo`;
  - una da trascrivere, per provare trascrizione e riassunto.

Trascrizioni, riassunti e download dei modelli funzionano come nella versione normale. Uscendo, la demo si spegne.

---

## Architettura

```
Statale+/
├── App/                 AppModel (stato radice, navigazione, refresh), AppServices, Live<T>
├── Core/
│   ├── Auth/            CASSession, ArielSession, KeychainStore
│   ├── HTML/            parser HTML tollerante + selettori CSS (sostituisce librerie esterne)
│   ├── Demo/            versione dimostrativa (credenziali, dati inventati)
│   ├── Local/           foto profilo, registrazioni (store, recorder, player), trascrizione (Speech, Parakeet), riassunti (FoundationModels, Qwen/MLX), modelli, lavori in background
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
- **Titolare del sito** (myAriel, blocco `.block_w4info`, `#accordionDocenti`): un `div.div-chiedove[data-p]` per
  docente, già nell'HTML del server (nessuna chiamata in più). Le righe dei contatti variano (un professore a contratto
  può avere solo email, CV e "Chi e dove"): si riconoscono dall'icona Font Awesome (`fa-university`, `fa-map-marker`
  con link = indirizzo / senza link = sede, `fa-envelope-o`, `fa-phone`, `fa-file-text`, `fa-address-book`).
  `.div-ricevimento`: testo del ricevimento, poi "Luogo ricevimento" in grassetto e il luogo.
- **myAriel AJAX** (`lib/ajax/service.php?sesskey=…`): `core_courseformat_get_state` risponde con il JSON **dentro
  una stringa**, calendario e notifiche con un oggetto; `ArielSession.ajax` restituisce il campo `data` grezzo.
  `core_calendar_get_calendar_upcoming_view` (`courseid: 1` = tutti i corsi), `core_calendar_get_action_events_by_timesort`,
  `message_popup_get_popup_notifications` (`useridto: 0` = utente corrente; `unreadcount` incluso, mentre
  `message_popup_get_unread_popup_notification_count` risponde "accessdenied"), `core_message_mark_notification_read`.
- **Contenuti del corso**: `contextid` dal link `course/downloadcontent.php?contextid=…` della pagina del corso, poi
  POST `contextid`, `download=1`, `sesskey` → `application/x-zip` (verificato: 12,5 MB per un corso con 2 cartelle).
- **QR della lezione**: testo Base64 (`UVJfOXRwNG02YW4tMTc5MDc3MzY2MDAwMA==` → `QR_9tp4m6an-1790773660000`); il codice
  lezione è la parte prima del trattino, il numero è un istante in ms che cambia a ogni rotazione del QR e non serve
  (la richiesta usa l'ora attuale). Risposte della timbratura: `{"result":"ok"|"warning"|"failure","message":…}`.
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
| Modelli locali (se scaricati)                                                                              | `Application Support/Modelli/parakeet-ultra` e `qwen3.5-4b-4bit` + marcatori `installato-*`, esclusi dal backup              |
| Motori scelti e catena automatica                                                                          | `UserDefaults` (`motoreTrascrizione`: `apple`/`parakeet`, `motoreRiassunto`: `apple`/`qwen`, `elaborazioneAutomatica`)      |
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
- **Refresh automatico ogni 5 minuti** (app in primo piano) e **al ritorno in primo piano** se sono passati più di
  5 minuti: lezioni di oggi, presenze, orario, prenotazioni, notifiche e scadenze Ariel; la lista corsi di Ariel e il
  corso aperto si ricaricano da soli se i loro dati sono più vecchi (segnale `segnaleAggiornamento`). Il timer riparte
  da ogni pull-to-refresh su Oggi, Orario o Presenze.

---

## Permessi

| Permesso            | Uso                                                 |
| ------------------- | --------------------------------------------------- |
| Microfono           | registrazione delle lezioni                         |
| Fotocamera          | scansione del QR del codice lezione                 |
| Riconoscimento vocale | trascrizione delle registrazioni (iOS 17–25)      |
| Audio in background | la registrazione continua a schermo bloccato        |
| Elaborazione in background | trascrizione, miglioramento e download proseguono fuori dall'app (iOS 26+); Qwen va in pausa e riprende |
| Libreria foto       | nessun permesso: la foto profilo usa `PhotosPicker` |

---

## Stato dei lavori

Da completare:

- [ ] **Iscrizione agli appelli** da app: la lista degli appelli disponibili (`SifaService.appelliDisponibili`) funziona;
      mancano la scelta dell'appello e la conferma, da osservare quando ci saranno appelli aperti (struttura delle
      righe di `ul.nomarker`, campo del modulo, pagina di conferma).
- [ ] **Pagamenti SIFA**
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
- Nessuna dipendenza esterna senza una ragione forte (oggi solo quelle dei modelli locali: FluidAudio, mlx-swift-lm,
  swift-transformers).
- Mai dati personali reali (nomi, matricole, indirizzi) nel codice, nei commenti o nei test: usare segnaposto
  (`MARIO ROSSI`, `12345A`).

---

## Changelog

### 2026-10-05 (11)

- Backup delle registrazioni: esportazione e importazione di un archivio con audio, trascrizioni, riassunti e note.

### 2026-10-05 (10)

- **Glossario del corso** per correggere le parole storpiate dalla trascrizione, creato con Apple Intelligence
  online, Qwen o Apple Intelligence.
- Riassunti con **Apple Intelligence online** (Private Cloud Compute) pronti, attivabili quando Apple concede
  l'entitlement.
- Qwen: GPU in background con l'account a pagamento. Prima il riassunto sembrava non partire, ora le interruzioni di
  iOS mostrano un errore.
- Player: l'audio continua aprendo trascrizione e riassunto, con un mini player.
- Dettaglio lezione: pulsante "Modifica" senza icona.
- Pronti per TestFlight: manifest della privacy, dichiarazione sulla crittografia, entitlement per l'account a
  pagamento (da collegare quando il team compare in Xcode).

### 2026-10-05 (9)

- **Versione dimostrativa** con credenziali dedicate e dati realistici in tutte le sezioni (vedi _Requisiti e build_).
- Download dei modelli più robusti:
  - verifica di dimensione e caricamento, controllo all'avvio;
  - errore visibile se iOS interrompe il download;
  - barra che non si ferma durante la preparazione del modello.
- Tolta la Live Activity dell'app: iOS mostra già la sua e non si può nascondere. Sottotitolo dell'attività di
  sistema ridotto a fase e tempo stimato.
- Testi delle impostazioni IA più brevi e senza termini tecnici, con i compromessi chiari: download, velocità,
  precisione e privacy (opzioni online in arrivo).
- Il miglioramento dell'audio è indicato come solo per l'ascolto.
- Tolta una riga di log del login.

### 2026-10-05 (8)

- Trascrizione: **Parakeet** (NVIDIA, versione Ultra, FluidAudio, Neural Engine) al posto di Whisper. Più accurato
  di Apple, 25 volte più veloce di Whisper, niente frasi inventate. Il modello Whisper scaricato si cancella da solo.
- Riassunti: **Qwen 3.5 4B** con MLX come motore opzionale (3 GB, iPhone con 8 GB), a sezioni con memoria.
- Catena automatica dopo ogni registrazione: trascrizione, riassunto, miglioramento dell'audio.
- La trascrizione usa sempre l'audio originale.
- **Live Activity** di Statale+ per download e lavori lunghi (schermata di blocco e Dynamic Island).
- Pausa e ripresa automatica dei lavori che iOS ferma in background.
- Tolti gli entitlement di GPU e Neural Engine in background: non firmabili con un team personale.
- Prove con testo di riferimento esatto (WER) e su una lezione reale di 2 h 25 min.

### 2026-10-05 (7)

- Riassunti: quando una parte supera il contesto si divide solo quella, senza ricominciare. Su una lezione lunga
  si passa da 19 a circa 6 minuti.
- Trascrizione Apple: tolte le parole di contesto, che non avevano alcun effetto.

### 2026-10-05 (6)

- Nuova voce **IA** in Altro: tutte le impostazioni di trascrizione, audio e riassunti in un posto solo.

### 2026-10-05 (5)

- Audio condiviso con nome leggibile (titolo, data, ora), anche per le registrazioni esistenti.
- Whisper: filtro per le ripetizioni a ciclo.
- Prove su una lezione reale di 20 minuti e su una sintetica di circa 1 h 45 min: Apple contro Whisper per la
  trascrizione; per il riassunto, Apple on-device contro Qwen 3.5 (4B e 2B) e Gemma 4 E2B con MLX. I file delle
  prove restano fuori dalla repo.

### 2026-10-05 (4)

- Download di Whisper con barra in MB calcolata sui byte (prima restava ferma sul file più grande).
- Tastiera uguale ovunque: chiusura con tocco fuori, swipe o trascinamento, pulsante "Chiudi" in vetro a destra, Invio
  coerente, niente correttore e suggerimenti nel codice lezione, nei nomi e nelle ricerche.
- Lavori in background: sottotitolo dell'attività di sistema con fase e tempo stimato; entitlement per GPU e Neural
  Engine in background.

### 2026-10-05 (3)

- Trascrizione: scelta del motore fra Apple (predefinito, preset più accurato con parole di contesto), Whisper Large v3
  Turbo locale con WhisperKit (download di 626 MB con avviso su rete, spazio e batteria) e Remoto Pro (non ancora
  disponibile).
- Trascrizioni, riassunti, miglioramento dell'audio e download proseguono in background (`BGContinuedProcessingTask`
  su iOS 26+), con una nota che consiglia il primo piano.
- Riassunto più completo (in breve, riassunto per parti, punti chiave, da ripassare) ed esportabile in PDF A4 da
  condividere o stampare.

### 2026-10-05 (2)

- Lezioni: modifiche locali (annullata, aula/sede dall'elenco aule, docente) con ripristino.
- Ariel si aggiorna da solo al ritorno in primo piano e ogni 5 minuti, come Oggi.

### 2026-10-05

- Presenze: esito `ok`/`failure` a tutto schermo con vibrazione; tolta la notifica di debug su ntfy.sh.
- Carriera: tolto il PDF "prossimi appelli" del corso (non aggiornato).
- Storia dei commit ripulita dalle righe di attribuzione.

### 2026-09-30 (12)

- Avvisi Ariel in Oggi: pallino blu e ordinamento da leggere/letti, letture salvate sul dispositivo; i non letti
  restano fino a 30 giorni. Prima sparivano perché uscivano dalla finestra di 7 giorni (in un primo momento era di
  10 giorni per le prove) e gli errori di accesso ad Ariel venivano mostrati come "nessun avviso".

### 2026-09-30 (11)

- Tolti tutti i collegamenti a siti esterni: pagina myAriel dentro l'app e Safari, programma dell'insegnamento, "Chi e
  dove", sito del dipartimento, link a SIFA (iscrizione, esiti, pagamenti). Curriculum e manifesto degli studi ora
  si aprono nell'app con Quick Look; notifiche non di forum mostrano il testo completo; scadenze solo informative.

### 2026-09-30 (10)

- Ariel: scadenze ed eventi del calendario, notifiche con badge e segna-come-letta, pagina myAriel dentro l'app,
  scaricamento dello zip con tutti i materiali del corso; in Oggi scadenze vicine e notifiche non lette.
- Timeout complessivo delle richieste portato a 15 minuti (resta il limite di 30 s senza dati) per i download grandi.

### 2026-09-30 (9)

- Ariel: riepilogo del docente (titolare del sito) con contatti e ricevimento, aperto dal nome nella scheda
  insegnamento; le schede in cache senza questi dati vengono riscaricate.

### 2026-09-30 (8)

- Timbratura tramite QR: decodifica del QR Base64 in codice lezione, invio immediato dopo la scansione, esiti
  `ok`/`warning`/`failure` con messaggi chiari, esito in una sezione separata (il pulsante non si sposta più).
- Debug: esito di ogni timbratura inviato a ntfy.sh/StatalePlus nelle build Debug; tolto un `print` della richiesta
  (conteneva la matricola).

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
