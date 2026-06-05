# Prompt per Claude design — Transito Torino (app mobile)

Prompt pronti da incollare in **Claude design** per generare la UI dell'app
(milestone M6–M7). Sono pensati per essere usati **in ordine**: prima il prompt
"0. Sistema di design" (definisce stile, palette, componenti), poi una schermata
alla volta. Ogni prompt è autosufficiente ma fa riferimento al sistema di design.

Contesto tecnico utile: l'app è **Flutter** (iOS + Android), lingua **italiano**,
mappa con **OpenStreetMap**. I dati arrivano dalla nostra API (gli schemi reali
sono riportati in ogni prompt così i mockup mostrano dati credibili).

---

## 0. Sistema di design (mandare per primo)

> Stai progettando **Transito Torino**, un'app mobile (iOS + Android, costruita in
> Flutter) per il trasporto pubblico di Torino (rete GTT: bus e tram). Serve a chi
> aspetta alla fermata e vuole sapere **quando passa il mezzo**, vedere i **mezzi in
> movimento sulla mappa**, salvare **preferiti** e ricevere **notifiche** per
> passaggi imminenti e scioperi. Concorre con MATO Live Bus e GTT TO Move, puntando
> a essere più fluida, leggibile e "a colpo d'occhio".
>
> Definisci un **sistema di design** completo, mobile-first, in **italiano**:
>
> **Tono e personalità**: pulito, moderno, urbano, affidabile; alta leggibilità
> all'aperto e in movimento (contrasto forte, tipografia grande). Niente fronzoli:
> l'informazione chiave (minuti all'arrivo) deve dominare.
>
> **Palette**: proponi una palette con un colore primario riconoscibile per il
> trasporto torinese (un blu/teal istituzionale funziona bene), un colore di
> accento per le azioni, e colori semantici per gli stati (in arrivo / in ritardo /
> avviso / sciopero). Fornisci versioni **light e dark** (l'uso notturno alla
> fermata è frequente). Garantisci contrasto AA.
>
> **Tipografia**: scala tipografica con enfasi sui numeri dei minuti (display
> grande, tabular figures), e su nomi linea/fermata. Suggerisci un font di sistema
> o Google Font ben leggibile.
>
> **Componenti da definire (con stati)**:
> - **Pill linea**: badge con il numero/lettera della linea (es. "10", "55", "4"),
>   colore per modalità (tram vs bus) — semplice, riconoscibile, scalabile.
> - **Riga arrivo**: linea + capolinea (headsign) + **minuti all'arrivo** in grande;
>   stato (in arrivo ora, X min, programmato).
> - **Card fermata** e **card linea** (per i preferiti).
> - **Banner avviso** (deviazione/guasto) e **banner sciopero** (più severo).
> - **Marker mezzo** sulla mappa con **freccia di direzione di marcia** (heading).
> - **Barra di ricerca**, **chip filtro**, **bottoni** (primario/secondario/testo),
>   **FAB "posizione"** sulla mappa.
> - **Stati trasversali**: loading (skeleton), vuoto, errore, **offline**.
> - **Bottom navigation** a 4 voci: Arrivi · Mappa · Preferiti · Avvisi (+ accesso a
>   Informazioni).
>
> **Accessibilità**: target touch ≥ 44pt, dynamic type, etichette per screen reader,
> non veicolare informazione col solo colore (icone + testo per gli stati).
>
> **Output desiderato**: foundation (colori light/dark, tipografia, spaziatura,
> raggi, ombre) + la libreria dei componenti sopra, ciascuno nei suoi stati.

---

## 1. Schermata "Arrivi" (ricerca fermata + arrivi in tempo reale)

> Progetta la schermata **Arrivi** di Transito Torino, usando il sistema di design.
> È la schermata d'apertura e la più usata.
>
> **Obiettivo**: l'utente cerca una fermata (per nome o **codice palina**) e vede i
> **prossimi passaggi in tempo reale**, con auto-refresh.
>
> **Flusso**:
> 1. In alto una **barra di ricerca** ("Cerca fermata o numero palina"). Durante la
>    digitazione, lista di risultati (nome fermata + codice + eventuale zona).
> 2. Selezionata una fermata, mostra l'**intestazione** (nome fermata + codice +
>    bottone "aggiungi ai preferiti" a forma di stella) e la **lista degli arrivi**
>    ordinata per minuti crescenti.
> 3. **Auto-refresh** ogni ~15 s con un indicatore discreto di "aggiornato ora" e
>    pull-to-refresh manuale.
>
> **Dato reale (una riga arrivo)**:
> ```json
> { "line": "10", "headsign": "Corso Settembrini", "eta_minutes": 4, "eta_seconds": 240 }
> ```
> Ogni riga: **pill linea** + capolinea (headsign) + **minuti in grande** a destra.
> "in arrivo" quando ≤ 1 min. Possibilità di **filtrare per linea** con chip.
>
> **Stati**: ricerca vuota (suggerisci fermate preferite / vicine), nessun risultato,
> caricamento (skeleton di righe), nessun passaggio previsto, errore di rete, offline.
>
> Mostra **light e dark**. Includi una variante con 5–6 arrivi di linee diverse.

---

## 2. Schermata "Mappa" (mezzi live)

> Progetta la schermata **Mappa** di Transito Torino, usando il sistema di design.
>
> **Obiettivo**: vedere in tempo reale **dove sono i mezzi** di una linea e come si
> muovono, con animazione fluida.
>
> **Layout**:
> - Mappa a tutto schermo (tile **OpenStreetMap**) centrata su Torino.
> - In alto un **selettore di linea** (la linea attiva, es. "10"); possibilità di
>   cambiarla. Sopra la mappa, **chip** della linea selezionata e conteggio mezzi.
> - **Marker mezzo** = forma direzionale (freccia/triangolo) **ruotata secondo
>   l'heading** (direzione di marcia), colorata per linea; tap → mini-scheda col
>   capolinea e (se presente) velocità.
> - **FAB** in basso a destra per ricentrare sulla posizione dell'utente; **FAB**
>   secondario per ricentrare su Torino/linea.
> - Crediti mappa "© OpenStreetMap contributors" in basso (obbligo di licenza).
>
> **Dato reale (un mezzo)**:
> ```json
> { "vehicle_id": "BUS001", "headsign": "Corso Settembrini",
>   "lat": 45.0701, "lon": 7.6601, "bearing": 90.0, "speed": 8.5 }
> ```
> Le posizioni arrivano via WebSocket (~ogni 4 s); i marker **interpolano** tra un
> aggiornamento e l'altro per un movimento fluido.
>
> **Stati**: caricamento mappa, nessun mezzo in servizio sulla linea, connessione
> realtime persa (badge "aggiornamenti in pausa" + fallback), offline, permesso
> posizione negato.
>
> Mostra **light e dark** (la dark è importante: mappa notturna).

---

## 3. Schermata "Preferiti" / Home

> Progetta la schermata **Preferiti** di Transito Torino, usando il sistema di
> design. È anche la "home a colpo d'occhio".
>
> **Obiettivo**: accesso immediato a fermate e linee salvate, con i **prossimi
> passaggi** dei preferiti senza dover cercare.
>
> **Contenuto**:
> - Sezione **"I tuoi passaggi"** in cima: per ogni coppia (fermata, linea)
>   preferita, una card con **pill linea + fermata + minuti al prossimo passaggio**
>   (il dato più prezioso, in grande). Pensata come widget "casa".
> - Sezione **Fermate preferite** (card con nome + codice palina + azione rapida
>   "vedi arrivi").
> - Sezione **Linee preferite** (pill linea + capolinea + azione "vedi sulla mappa").
> - Gesti: swipe per rimuovere, riordino, tap per aprire la schermata Arrivi/Mappa.
>
> **Dati reali**:
> ```json
> { "type": "stop", "ref": "350" }          // fermata preferita
> { "type": "line", "ref": "10" }           // linea preferita
> ```
>
> **Stati**: nessun preferito (empty state invitante con CTA "Cerca una fermata"),
> caricamento, errore. Mostra **light e dark**, con uno stato pieno realistico
> (2–3 passaggi, 3 fermate, 2 linee).

---

## 4. Schermata "Avvisi" (servizio GTT + scioperi)

> Progetta la schermata **Avvisi** di Transito Torino, usando il sistema di design.
>
> **Obiettivo**: comunicare con chiarezza disservizi e scioperi, distinguendo la
> gravità.
>
> **Due tipi di contenuto**:
> - **Avvisi di servizio** (deviazioni, guasti, lavori): banner/list item con
>   icona per **effetto** (deviazione, ritardi, soppressione), titolo, descrizione,
>   e le **linee interessate** (pill).
> - **Scioperi**: trattamento visivo più forte/serio. Mostra **data inizio–fine**,
>   **settore** (es. "Trasporto pubblico locale"), **area** (Piemonte/Torino o
>   Nazionale), e (se utile) sindacati. Distingui chiaramente "in programma" vs
>   "in corso oggi".
>
> **Dati reali**:
> ```json
> // avviso di servizio
> { "header": "Deviazione linea 10", "description": "Lavori in Corso Regina",
>   "effect": "DETOUR", "lines": ["10"] }
> // sciopero
> { "start_date": "2026-06-10", "end_date": "2026-06-10",
>   "sector": "Trasporto pubblico locale", "area": "Piemonte", "relevance": "Locale" }
> ```
>
> **Filtri**: tutti / solo le mie linee preferite. **Stati**: nessun avviso (buono!),
> caricamento, errore, offline. Mostra **light e dark**, con un mix di 2 avvisi di
> servizio + 1 sciopero.

---

## 5. Schermata "Informazioni / Fonti dati"

> Progetta la schermata **Informazioni / Fonti dati** di Transito Torino, usando il
> sistema di design. Schermata semplice ma curata.
>
> **Contenuto**:
> - Breve descrizione dell'app e versione.
> - **Crediti dati obbligatori** (requisito di licenza), ben leggibili:
>   - "Dati di trasporto: **Città di Torino / GTT** — licenza CC BY 4.0"
>   - "Scioperi: **MIT — Osservatorio sui Conflitti Sindacali**"
>   - "Mappa: **© OpenStreetMap contributors**"
> - Link a privacy policy e contatti; toggle tema (chiaro/scuro/auto).
>
> Mostra **light e dark**.

---

## 6. Navigation shell (opzionale, da fare dopo le schermate)

> Definisci la **shell di navigazione** di Transito Torino: **bottom navigation** a
> 4 voci — **Arrivi · Mappa · Preferiti · Avvisi** — con icone chiare ed etichette
> in italiano, badge per gli avvisi non letti, e accesso a "Informazioni" (icona in
> alto o quinta voce a menu). Mostra come cambia la barra in light e dark e lo stato
> attivo/inattivo delle voci. Includi il comportamento con notch/safe-area su iOS e
> Android.

---

### Note per chi implementa (non per il designer)
- I componenti dovrebbero mappare 1:1 su widget Flutter riutilizzabili
  (`LinePill`, `ArrivalRow`, `StopCard`, `AlertBanner`, `VehicleMarker`, ...).
- Gli stati (loading/empty/error/offline) vanno previsti fin dal design perché i
  feed possono essere non raggiungibili.
- La freccia di direzione del marker usa il campo `bearing` (gradi) del mezzo.
