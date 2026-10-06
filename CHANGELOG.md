# Changelog

Storico delle modifiche di Statale Plus (fino al 2026-10-06 "Statale+"), dal più recente. Documentazione completa in [README.it.md](README.it.md).

## 2026-10-06 (10)

- **Presentazione** dopo il primo accesso: quattro pagine sulle funzioni principali e sull'IA, con i pulsanti per
  scaricare Parakeet e creare il glossario; si rivede da Altro › IA. Build 4.

## 2026-10-06 (9)

- Parakeet trascrive a blocchi di circa 10 minuti, tagliati nei silenzi: le lezioni lunghe non vengono più chiuse da
  iOS in background o a schermo bloccato (prima la barra restava ferma durante la conversione di tutto il file).
  Un lavoro interrotto riprende dal blocco successivo, non da zero.
- Avanzamento regolare dentro ogni blocco, stimato dal tempo; registro dei lavori su file nelle build di sviluppo.

## 2026-10-06 (8)

- GitHub Action: runner `xcode-27` (l'immagine `macos-26` non ha Xcode 27 e la prima esecuzione falliva), Xcode 27.0
  scelto esplicitamente invece delle beta, `actions/checkout@v5` (Node 24).

## 2026-10-06 (7)

- README rifatto per GitHub: vetrina in inglese (`README.md`) con icona, badge di versione e requisiti, galleria di
  screenshot della versione dimostrativa e modalità scura; versione italiana con tutta la documentazione tecnica
  (`README.it.md`); storico in `CHANGELOG.md`.
- Argomenti di avvio solo per le build di sviluppo (`-accessoDemo`, `-schermata`, `-altro`) per rifare gli screenshot.

## 2026-10-06 (6)

- Trascrizioni: corretto lo stato non sincronizzato con l'attività di sistema (lavoro annullato che cancellava lo
  stato di quello rilanciato, caricamento del modello non annullabile, attività chiusa da iOS durante il caricamento).
  Parakeet si prepara alla prima apertura dopo ogni aggiornamento. Build 3.

## 2026-10-06 (5)

- Licenza **PolyForm Strict 1.0.0** con permessi aggiuntivi (compilazione in locale, contributi), nome e icona
  riservati; `NOTICE`, `CONTRIBUTING.md` con accordo per i contributi, `SECURITY.md`.
- GitHub: Action di compilazione, schema condiviso, modelli per segnalazioni e pull request; sintesi in inglese nel
  README. La cartella del progetto ora si chiama `StatalePlus`.

## 2026-10-06 (4)

- Requisito minimo **iOS 26.0**: tolti i controlli di versione e i ripieghi per iOS 17–25 (pulsanti senza vetro,
  testi per i lavori in primo piano, blocchi condizionali di FoundationModels).
- Repository pronto per GitHub: impostazioni personali di Xcode fuori dal controllo di versione.

## 2026-10-06 (3)

- Nuova icona: libro aperto con una fiamma, in vettoriale, nelle varianti chiara, scura e tinted. Build 2.

## 2026-10-06 (2)

- Nome **Statale Plus** (prima "Statale+") e nuovo identificativo `com.mattiameligeni.StatalePlus`; progetto, target e
  cartelle rinominati. Le registrazioni della vecchia app si portano con il backup.
- **Importazione dal menu Condividi**: l'app compare fra quelle a cui inviare l'archivio delle registrazioni e lo
  importa subito, senza salvarlo prima.
- _Background Inference_ attivo: Parakeet trascrive anche fuori dall'app (iOS 27).
- Glossario più ricco (tre richieste per insegnamento: 356 termini contro 89 nella prova) e che **impara dalle
  lezioni**: i termini riconosciuti nei riassunti entrano nel glossario e la trascrizione si ricorregge.

## 2026-10-06

- **Qwen tolto**: troppo lento ed energivoro su iPhone (glossario 6-7 minuti e 6% di batteria, riassunto di 20
  minuti 3 minuti e 3%). Il modello scaricato (3 GB) si cancella da solo; via anche MLX e swift-transformers.
- Riassunti e glossario con **Apple Intelligence**: online quando Apple la abilita (predefinita, con ripiego sul
  telefono senza rete o oltre il limite), altrimenti sul telefono.
- Riassunti sul telefono ottimizzati: parti dimensionate sul contesto reale del modello (8K token da iOS 27),
  memoria degli argomenti, termini del glossario nel prompt per correggere gli errori di trascrizione, sintesi finale
  guidata, nuovi tentativi quando iOS limita il modello in background, errori di iOS 27 gestiti.
- Glossario: richieste guidate di parole tecniche specifiche, filtro di parole inventate e nomi di persona, niente
  cognomi dei docenti; i glossari creati con Qwen si ripuliscono da soli. Correttore più prudente con forme diverse
  della stessa parola e parole che il dizionario riconosce come altro.
- Parakeet **pre-riscaldato** all'inizio della registrazione: la trascrizione parte subito.
- _Background Inference_: verificato che è disponibile per l'account, da attivare sull'App ID; GPU in background
  tolta.

## 2026-10-05 (12)

- Account Apple Developer a pagamento: permessi di GPU in background e memoria aumentata collegati al progetto e
  presenti nel profilo.
- Icona provvisoria dell'app (chiara, scura, tinted); archivio ed esportazione per App Store Connect verificati.

## 2026-10-05 (11)

- Backup delle registrazioni: esportazione e importazione di un archivio con audio, trascrizioni, riassunti e note.

## 2026-10-05 (10)

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

## 2026-10-05 (9)

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

## 2026-10-05 (8)

- Trascrizione: **Parakeet** (NVIDIA, versione Ultra, FluidAudio, Neural Engine) al posto di Whisper. Più accurato
  di Apple, 25 volte più veloce di Whisper, niente frasi inventate. Il modello Whisper scaricato si cancella da solo.
- Riassunti: **Qwen 3.5 4B** con MLX come motore opzionale (3 GB, iPhone con 8 GB), a sezioni con memoria.
- Catena automatica dopo ogni registrazione: trascrizione, riassunto, miglioramento dell'audio.
- La trascrizione usa sempre l'audio originale.
- **Live Activity** di Statale+ per download e lavori lunghi (schermata di blocco e Dynamic Island).
- Pausa e ripresa automatica dei lavori che iOS ferma in background.
- Tolti gli entitlement di GPU e Neural Engine in background: non firmabili con un team personale.
- Prove con testo di riferimento esatto (WER) e su una lezione reale di 2 h 25 min.

## 2026-10-05 (7)

- Riassunti: quando una parte supera il contesto si divide solo quella, senza ricominciare. Su una lezione lunga
  si passa da 19 a circa 6 minuti.
- Trascrizione Apple: tolte le parole di contesto, che non avevano alcun effetto.

## 2026-10-05 (6)

- Nuova voce **IA** in Altro: tutte le impostazioni di trascrizione, audio e riassunti in un posto solo.

## 2026-10-05 (5)

- Audio condiviso con nome leggibile (titolo, data, ora), anche per le registrazioni esistenti.
- Whisper: filtro per le ripetizioni a ciclo.
- Prove su una lezione reale di 20 minuti e su una sintetica di circa 1 h 45 min: Apple contro Whisper per la
  trascrizione; per il riassunto, Apple on-device contro Qwen 3.5 (4B e 2B) e Gemma 4 E2B con MLX. I file delle
  prove restano fuori dalla repo.

## 2026-10-05 (4)

- Download di Whisper con barra in MB calcolata sui byte (prima restava ferma sul file più grande).
- Tastiera uguale ovunque: chiusura con tocco fuori, swipe o trascinamento, pulsante "Chiudi" in vetro a destra, Invio
  coerente, niente correttore e suggerimenti nel codice lezione, nei nomi e nelle ricerche.
- Lavori in background: sottotitolo dell'attività di sistema con fase e tempo stimato; entitlement per GPU e Neural
  Engine in background.

## 2026-10-05 (3)

- Trascrizione: scelta del motore fra Apple (predefinito, preset più accurato con parole di contesto), Whisper Large v3
  Turbo locale con WhisperKit (download di 626 MB con avviso su rete, spazio e batteria) e Remoto Pro (non ancora
  disponibile).
- Trascrizioni, riassunti, miglioramento dell'audio e download proseguono in background (`BGContinuedProcessingTask`
  su iOS 26+), con una nota che consiglia il primo piano.
- Riassunto più completo (in breve, riassunto per parti, punti chiave, da ripassare) ed esportabile in PDF A4 da
  condividere o stampare.

## 2026-10-05 (2)

- Lezioni: modifiche locali (annullata, aula/sede dall'elenco aule, docente) con ripristino.
- Ariel si aggiorna da solo al ritorno in primo piano e ogni 5 minuti, come Oggi.

## 2026-10-05

- Presenze: esito `ok`/`failure` a tutto schermo con vibrazione; tolta la notifica di debug su ntfy.sh.
- Carriera: tolto il PDF "prossimi appelli" del corso (non aggiornato).
- Storia dei commit ripulita dalle righe di attribuzione.

## 2026-09-30 (12)

- Avvisi Ariel in Oggi: pallino blu e ordinamento da leggere/letti, letture salvate sul dispositivo; i non letti
  restano fino a 30 giorni. Prima sparivano perché uscivano dalla finestra di 7 giorni (in un primo momento era di
  10 giorni per le prove) e gli errori di accesso ad Ariel venivano mostrati come "nessun avviso".

## 2026-09-30 (11)

- Tolti tutti i collegamenti a siti esterni: pagina myAriel dentro l'app e Safari, programma dell'insegnamento, "Chi e
  dove", sito del dipartimento, link a SIFA (iscrizione, esiti, pagamenti). Curriculum e manifesto degli studi ora
  si aprono nell'app con Quick Look; notifiche non di forum mostrano il testo completo; scadenze solo informative.

## 2026-09-30 (10)

- Ariel: scadenze ed eventi del calendario, notifiche con badge e segna-come-letta, pagina myAriel dentro l'app,
  scaricamento dello zip con tutti i materiali del corso; in Oggi scadenze vicine e notifiche non lette.
- Timeout complessivo delle richieste portato a 15 minuti (resta il limite di 30 s senza dati) per i download grandi.

## 2026-09-30 (9)

- Ariel: riepilogo del docente (titolare del sito) con contatti e ricevimento, aperto dal nome nella scheda
  insegnamento; le schede in cache senza questi dati vengono riscaricate.

## 2026-09-30 (8)

- Timbratura tramite QR: decodifica del QR Base64 in codice lezione, invio immediato dopo la scansione, esiti
  `ok`/`warning`/`failure` con messaggi chiari, esito in una sezione separata (il pulsante non si sposta più).
- Debug: esito di ogni timbratura inviato a ntfy.sh/StatalePlus nelle build Debug; tolto un `print` della richiesta
  (conteneva la matricola).

## 2026-09-30 (7)

- Registratore e player spostati dentro l'attore `MotoreAudio`: anche `record()`, `play()`, `pause()` e `stop()`
  (che attivano o disattivano la sessione audio da soli) girano fuori dal main thread. Le API asincrone di
  attivazione esistono solo da iOS 27.
- **Miglioramento dell'audio** delle registrazioni (volume, rumore di fondo, voce), automatico o manuale, con
  ripristino dell'originale.
- Slider di zoom nella scansione del QR della lezione.

## 2026-09-30 (6)

- Sessione audio configurata, attivata e disattivata fuori dal main thread (attore `SessioneAudio`), anche per il player
  (tolto `prepareToPlay()`, che la attivava in modo sincrono): risolto l'avviso "AVAudioSession Hang Risk" di Xcode.

## 2026-09-30 (5)

- **Registrazioni, persistenza**: `registrazioni.json` veniva scritto con le date in ISO 8601 ma letto con il formato
  predefinito (numero): all'avvio la lettura falliva in silenzio, la lista partiva vuota e il primo salvataggio scriveva
  `[]` (i file restavano sul disco senza voce). Ora lettura e scrittura usano lo stesso formato (con lettura tollerante),
  e gli errori di scrittura ed eliminazione vengono registrati e mostrati invece di essere ignorati.
- Quarto file per registrazione, `<id>.json` con i metadati; riconciliazione all'avvio con avviso e sezione "Da verificare".
- Eliminazione con conferma che toglie anche trascrizione, riassunto, metadati e voce dell'indice.

## 2026-09-30 (4)

- Esami › Iscrizioni: **Iscriviti** apre la lista degli appelli disponibili, come "Selezione appello" di SIFA
  (verificato sul sito e nell'app: al momento nessun appello aperto per nessun esame del corso).
- Orario: riga della settimana di nuovo attaccata alle pillole, con angoli superiori squadrati.

## 2026-09-30 (3)

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

## 2026-09-30 (2)

- Oggi: pulsanti rapidi mai a capo, "Presenza registrata" compatta, nota delle tasse allineata al testo, sezioni vuote
  raccolte in una riga, aula e sede su due righe anche per appelli e prenotazioni.
- Orario ed Esami: pillole e settimana in blocchi separati; nomi dei corsi e dei docenti leggibili anche nel selettore
  dei corsi e negli insegnamenti.
- Dettaglio lezione: giorno della settimana e orari "08:30", meno spazio in alto, sfondo pieno.
- Ariel: corsi senza sito in un gruppo richiudibile, titolo del corso e sezioni Moodle, icone allineate, testo con
  grassetto/corsivo/elenchi, calendario lezioni compatto per mese.
- Carriera: corso, stato e indirizzi normalizzati.
- Registrazioni: selettore dell'insegnamento allineato a sinistra.

## 2026-09-30

- Date sempre in italiano (niente più "last week", "Sep", "February"); italiano come lingua di sviluppo.
- Tasse in Oggi e nella schermata Tasse: scadenza spiegata (quale rata, se emessa, da quando si può pagare).
- Avvisi Ariel di nuovo sugli ultimi 7 giorni.
- Pulsanti rapidi in Oggi senza icone; icona bianca su "Avvia registrazione"; più spazio nella schermata Registrazioni.
- Dettaglio lezione con nome completo espandibile.
- Login: mostra password, messaggio di CAS in caso di rifiuto, log diagnostico; codifica corretta delle lettere accentate
  nella password.

## 2026-09-29 (8)

- Altro: sezione **Crediti** con i servizi usati e i relativi link; nota di disclaimer e copyright in fondo.
- Registrazioni: soglie minime (trascrizione ≥ 1 min, riassunto ≥ 5 min e ≥ 150 parole / 60 diverse), verifica
  preliminare del contenuto e prompt senza nome della materia, per evitare riassunti inventati su audio vuoti.

## 2026-09-29 (7)

- Orario: la lezione aperta da "Prossima lezione" viene ora evidenziata davvero e la lista scorre fino a lei.
- Nota "Prossima lezione" ridotta a distanza relativa e materia.

## 2026-09-29 (6)

- Oggi: dissolvenza fra le etichette di stato e fra barra e pallino, conto alla rovescia animato.
- Nota "Prossima lezione" (giorno relativo, data, materia) a lezioni del giorno terminate; un tap apre l'Orario sulla
  settimana della lezione e la evidenzia.

## 2026-09-29 (5)

- Oggi completamente live: prossima lezione, barra, etichette `IN CORSO` / `INIZIA TRA X MIN` aggiornate ogni secondo;
  pallino della lezione in corso animato (scorre, pulsa, bagliore sulla parte trascorsa).

## 2026-09-29 (4)

- Oggi: durante una lezione l'ora corrente è una traccia verticale con pallino proporzionale al tempo trascorso,
  al posto della barra sopra la lezione.
- Etichette `IN CORSO` / `INIZIA TRA X MIN` calcolate sulla stessa ora di barra e grassetto (anche nella preview).

## 2026-09-29 (3)

- Trascrizione delle registrazioni con Speech (SpeechAnalyzer su iOS 26+, SFSpeechRecognizer prima), modificabile con
  Writing Tools.
- Riassunti con Apple Intelligence (FoundationModels): riassunto, punti chiave e domande di ripasso.
- Oggi: avvisi Ariel degli ultimi 10 giorni; prossima lezione in grassetto con barra "Ora" statica; preview locale.

## 2026-09-29 (2)

- Onboarding: accesso riservato agli indirizzi `@studenti.unimi.it`, completamento automatico da `nome.cognome`,
  errore per ogni altro dominio.
- Registrazioni raggruppate per insegnamento con navigazione all'elenco dedicato.
- "Vai a data" nella vista settimanale di Orario ed Esami; appelli raggruppati per settimana.

## 2026-09-29

- Prima versione dell'app: login unico (CAS + Ariel), tab Oggi, Orario, Ariel, Registrazioni, Altro.
- Parser HTML interno al posto di SwiftSoup: nessuna dipendenza esterna.
- Orario ed Esami con scelta di corso (scuola → tipo → corso) e pillole di periodo/anno dalle API mobili.
- Etichette di stato delle lezioni (annullata, in corso, inizia tra X min) e azioni rapide in Oggi
  (conferma presenza, inizia registrazione) con refresh automatico ogni 5 minuti.
- Presenze con invio codice lezione / QR; iscrizione agli appelli predisposta.
- Mappe basate sugli indirizzi EasyRoom.
- Registrazioni vocali locali con segnalibri, note e player.
- Foto profilo locale; uscita con scelta di conservare o eliminare i dati locali.
