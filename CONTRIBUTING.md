# Contribuire a Statale Plus

Grazie dell'interesse! Statale Plus è un progetto a codice visibile (*source-available*), non open source: leggi
[LICENSE](LICENSE) e [ADDITIONAL-PERMISSIONS.md](ADDITIONAL-PERMISSIONS.md) prima di iniziare. Si possono proporre
contributi con una pull request al repository ufficiale; non si possono pubblicare versioni proprie dell'app.

## Prima di aprire una pull request

1. **Una cosa per volta.** Per modifiche grandi apri prima una segnalazione e parliamone.
2. **Documentazione aggiornata.** Ogni modifica aggiorna la documentazione tecnica in `README.it.md` (funzionalità,
   endpoint, formati, stato dei lavori), la vetrina in inglese `README.md` se cambia qualcosa di visibile, e aggiunge
   una voce in `CHANGELOG.md`.
3. **Mai dati personali reali** (nomi, matricole, email, codici fiscali, indirizzi, registrazioni di lezioni) nel
   codice, nei commenti, nei test, negli screenshot o nei messaggi dei commit: usa i segnaposto `MARIO ROSSI`,
   `12345A`, `mario.rossi@studenti.unimi.it`. Niente catture di traffico (`.har`) né credenziali.
4. **Nessuna dipendenza nuova** senza una ragione forte (oggi solo FluidAudio).
5. **Nessun collegamento esterno** nell'app (browser, web view, link a siti): se qualcosa non si può integrare in modo
   nativo, non si aggiunge.
6. **Stile del codice**: Swift 6 con isolamento predefinito sul MainActor, nomi e commenti in italiano come nel resto
   del progetto, `@concurrent` o attori per il lavoro pesante.
7. **Compila**: la build per il simulatore deve riuscire senza errori né avvisi nuovi (lo controlla anche la GitHub
   Action).

## Compilare in locale

- Xcode 27, iOS 26.0 o successivo.
- Apri `StatalePlus.xcodeproj`. Per installare l'app su un tuo dispositivo imposta il tuo team di sviluppo (e, se
  serve, un tuo identificativo) in *Signing & Capabilities*: sono modifiche locali, da non includere nelle pull
  request.
- Per provare l'app senza un account dell'Ateneo c'è la modalità dimostrativa: vedi la sezione *Versione
  dimostrativa* del README.

## Accordo per i contributi (CLA)

Statale Plus potrà diventare un'app a pagamento o in abbonamento. Per questo i contributi devono poter essere usati
dall'autore senza limiti. Inviando un contributo (codice, testi, grafica, documentazione) al repository ufficiale
accetti che:

1. **Licenza all'autore.** Concedi a Mattia Meligeni (il *licensor*) una licenza mondiale, perpetua, irrevocabile,
   non esclusiva, gratuita e trasferibile, con diritto di sublicenza, per usare, riprodurre, modificare, distribuire,
   concedere in licenza (anche con licenze diverse, incluse quelle commerciali) e sfruttare commercialmente il tuo
   contributo, da solo o come parte di Statale Plus o di altri prodotti. Concedi anche una licenza sui tuoi brevetti
   eventualmente necessari a usare il contributo.
2. **Diritti tuoi.** Il contributo è opera tua, o hai il diritto di concederlo così. Se lo hai realizzato per un
   datore di lavoro o con materiale di terzi, hai le autorizzazioni necessarie e lo indichi nella pull request.
3. **Niente compensi.** Non hai diritto a compensi o royalty. Il licensor non è obbligato a usare il contributo.
4. **Nessuna garanzia.** Il contributo è fornito così com'è.
5. **Il tuo contributo resta tuo.** Mantieni i diritti d'autore e puoi usarlo come vuoi, ma non puoi usare il resto
   del progetto oltre quanto consentono [LICENSE](LICENSE) e [ADDITIONAL-PERMISSIONS.md](ADDITIONAL-PERMISSIONS.md).

Per indicare l'accordo, firma ogni commit con `git commit -s`, che aggiunge la riga:

```
Signed-off-by: Nome Cognome <email>
```

e spunta la casella dell'accordo nella pull request. Senza firma il contributo non può essere accettato.
