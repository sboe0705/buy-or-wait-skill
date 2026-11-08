---
name: buy-or-wait
description: Gibt für eine Aktie, einen ETF oder eine Kryptowährung eine klare Einstiegsempfehlung – KAUFEN, NICHT KAUFEN oder ABWARTEN – auf Basis des aktuellen Kurses und der jüngsten Kursentwicklung (Trend, Überhitzung, Dip, Volatilität), mit echten Kursdaten von Yahoo Finance. Verwende diesen Skill immer, wenn jemand wissen will, ob jetzt ein guter Zeitpunkt zum Kaufen/Einsteigen/Nachkaufen ist, ob etwas überbewertet oder heißgelaufen ist, ob man einen Dip kaufen soll oder lieber warten – z. B. "Soll ich jetzt Nvidia kaufen?", "Lohnt sich Bitcoin gerade?", "Ist der MSCI World gerade teuer?", "buy the dip bei Tesla?", "should I buy ETH now or wait?" – auch wenn das Wort "Skill" nicht fällt und nur ein Tickersymbol oder Name genannt wird.
---

# Buy or Wait

Ziel: eine nachvollziehbare, ehrliche Einschätzung des **Einstiegszeitpunkts** für einen
Anlagehorizont von **einigen Wochen bis Monaten**. Es geht nicht darum, ob ein Unternehmen
grundsätzlich gut ist, sondern ob *jetzt* ein günstiger Moment zum Kaufen ist.

Die drei möglichen Ergebnisse:

| Empfehlung | Bedeutung | Typische Lage |
|---|---|---|
| 🟢 **KAUFEN** | Guter Einstieg wahrscheinlich | Rücksetzer (Dip) in einem intakten Aufwärtstrend, Kurs stabilisiert sich bereits |
| 🔴 **NICHT KAUFEN** | Kurs vermutlich heißgelaufen | Steiler Anstieg, stark überkauft, weit über den Durchschnitten – Rückschlag wahrscheinlicher als weiterer Sprint |
| 🟡 **ABWARTEN** | Keine klare Chance | Gemischte Signale, Seitwärtsphase, fallendes Messer ohne Bodenbildung, extreme Unsicherheit |

ABWARTEN ist der Normalfall und keine Verlegenheitsantwort: Meistens gibt es weder einen
klaren Dip noch eine klare Überhitzung. Eine Kaufempfehlung soll etwas bedeuten, deshalb
gibt es sie nur, wenn die Lage wirklich günstig aussieht.

## Ablauf

### 1. Symbol bestimmen

Das Skript braucht ein Yahoo-Finance-Symbol. Beispiele: `AAPL`, `NVDA`, `SAP.DE`, `RHM.DE`,
`EUNL.DE` (iShares Core MSCI World, Xetra), `VWCE.DE`, `BTC-EUR`, `ETH-EUR`, `SOL-EUR`.

- Nennt die Person einen Namen statt eines Symbols, suche:
  `python3 <skill-dir>/scripts/analyze.py --search "Rheinmetall"`
- Wähle die Hauptnotierung: bei deutschen Werten und europäischen UCITS-ETFs die Xetra-Notierung
  (`.DE`), bei US-Aktien das US-Symbol ohne Suffix. Bei Krypto `-EUR`, außer die Person spricht
  in Dollar. OTC-Ableger (z. B. `RNMBY`) meiden.
- Gibt die Person eine ISIN oder WKN an, versuche die Suche damit; klappt das nicht, frag nach
  dem Namen.
- Ist unklar, welches Wertpapier gemeint ist (z. B. "der Vanguard ETF"), frag kurz nach,
  statt zu raten – eine Empfehlung zum falschen Papier ist schlimmer als eine Rückfrage.

### 2. Analyse ausführen

```bash
python3 <skill-dir>/scripts/analyze.py <SYMBOL>
```

Das Skript holt ~2 Jahre Tageskurse und liefert JSON mit Performance, gleitenden Durchschnitten
(SMA20/50/200), RSI(14), Abstand zu Hochs/Tiefs, Volatilität und einer regelbasierten
**Vorbewertung** (`vorbewertung.empfehlung`, `score`, Liste der `signale` mit Punkten).
Bei Fehlern (z. B. HTTP 404) ist das Symbol meist falsch → Suche nutzen.

Bei mehreren Werten in einer Frage: für jeden einzeln ausführen und jeweils bewerten.

Fragt die Person nach einem vergangenen Zeitpunkt ("Hätte ich im Juni 2024 kaufen sollen?"),
nutze `--as-of YYYY-MM-DD`. Dann zählen nur Kurse bis zu diesem Tag, und Quartalszahlen-Termine
werden nicht abgefragt. Bewerte so, als wäre heute dieser Tag. Den späteren Kursverlauf darfst
du danach in einem Satz als Auflösung ergänzen, wenn die Person danach fragt oder es offensichtlich
interessiert.

### 3. Bewerten

Die Vorbewertung des Skripts ist der Ausgangspunkt. Sie ist bewusst einfach und transparent
gehalten. Übernimm sie im Normalfall; weiche nur ab, wenn die Zahlen erkennbar etwas zeigen,
das die Regeln nicht abbilden – und sag dann offen, warum.

Worauf die Regeln achten, damit du die Signale erklären kannst:

- **Trend (SMA200):** Kurs über einem *steigenden* 200-Tage-Durchschnitt = intakter
  Aufwärtstrend. Ein Dip darin wird oft wieder gekauft. Unter einem *fallenden* SMA200 ist ein
  Kursrückgang dagegen oft Teil eines größeren Abwärtstrends ("fallendes Messer").
- **Stretch:** Abstand zum SMA50, geteilt durch die Monatsvolatilität. Dadurch sind ruhige ETFs
  und wilde Kryptos vergleichbar: +8 % über dem SMA50 ist für einen MSCI World extrem, für
  Bitcoin normal. Über ~1,5 = stark gestreckt, unter ~−1 = deutlicher Rücksetzer.
- **RSI(14):** über ~70 überkauft, unter ~30 überverkauft.
- **Anstieg in Sigma:** Monatsrendite im Verhältnis zur üblichen Schwankung; über 2 heißt
  "ungewöhnlich steil".
- **Stabilisierung:** keine neuen Tiefs in den letzten 5 Tagen. Ohne Stabilisierung ist ein
  Dip noch nicht vorbei – dann lieber ABWARTEN, auch wenn der Kurs "billig" aussieht.
- **Volatilitätsregime:** Ist die aktuelle Schwankung deutlich höher als im Jahresschnitt,
  ist die Prognose unsicherer.

- **Quartalszahlen:** Bei Aktien liefert das Skript `naechste_quartalszahlen` (Datum, Tage bis
  dahin). Liegen sie innerhalb von ~2 Wochen, ist das ein Ereignisrisiko: Die Zahlen können den
  Kurs kräftig in beide Richtungen bewegen. Nenn den Termin dann immer in der Antwort – auch
  wenn er die Empfehlung nicht kippt. Ist das Feld `null` (ETF, Krypto oder kein Termin
  abrufbar), lass das Thema weg.

Grenzen, die du ehrlich benennen solltest: Das ist reine Kurs- bzw. Chartanalyse. Ob ein
Einbruch einen fundamentalen Grund hat (schlechte Zahlen, Skandal, Gewinnwarnung), sieht das
Skript nicht. Meldet es einen "außergewöhnlich starken Einbruch", weise darauf hin, dass die
Person die Ursache prüfen sollte, bevor sie kauft.

### 4. Antwort formulieren

Antworte in der Sprache der Person (meist Deutsch), kurz und klar. Struktur:

```
## <Emoji> <EMPFEHLUNG> – <Name> (<Symbol>)

**Kurs:** <Kurs> <Währung> (Stand <Datum>) · 1 Monat <±x %> · 3 Monate <±x %> · 1 Jahr <±x %>
<nur bei Aktien mit Zahlen in ≤ 14 Tagen: **📅 Quartalszahlen am <Datum> (in <n> Tagen)** – kurz, was das bedeutet>

**Kurz gesagt:** <ein bis zwei Sätze, warum – in Alltagssprache>

**Die Signale:**
- <2–5 wichtigste Signale, mit konkreten Zahlen, verständlich erklärt>

**Was die Lage ändern würde:** <konkret, mit Kursmarken wo möglich – z. B. "Ein Rücksetzer
Richtung SMA50 (~185 USD) wäre ein besserer Einstieg" oder "Erst wenn der Kurs wieder über
dem SMA200 (~41.000 EUR) schließt, …">

<Eine Zeile Hinweis: keine Anlageberatung, reine Kursanalyse ohne Fundamentaldaten/News.>
```

Hinweise zum Ton:
- Zahlen runden (eine Nachkommastelle reicht) und Fachbegriffe beim ersten Auftreten kurz
  erklären ("RSI 78 – ein Wert über 70 gilt als überkauft").
- Die Empfehlung nicht verwässern. Wenn das Ergebnis KAUFEN ist, sag es klar – mit dem
  Risiko dazu. Wenn es ABWARTEN ist, erklär, worauf man warten sollte.
- Der Abschnitt "Was die Lage ändern würde" ist der nützlichste Teil für die Person, denn
  er macht aus einem "Nein" einen Plan.
- Keine Kursziele oder Wahrscheinlichkeiten erfinden, die nicht aus den Daten folgen.
- **Bleib bei der Timing-Frage.** Die Person will eine schnelle Entscheidungshilfe für den
  Einstiegszeitpunkt – keine allgemeine Anlageberatung. Schlag deshalb keine Ausweichstrategien
  wie Sparplan, Cost-Average oder "in Tranchen kaufen" vor, und halte keine Vorträge über
  Risikostreuung, Notgroschen, Steuern oder "Timing funktioniert nicht". Wer diesen Skill nutzt,
  kennt die Risiken und hat sich bewusst für eine Einmal-Entscheidung entschieden. Die Antwort
  soll die Frage "jetzt kaufen oder nicht?" beantworten, nicht eine andere.
