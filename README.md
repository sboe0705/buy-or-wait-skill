# buy-or-wait

Ein [Claude Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview), der für eine Aktie, einen ETF oder eine Kryptowährung eine klare Einstiegsempfehlung gibt: **🟢 KAUFEN**, **🔴 NICHT KAUFEN** oder **🟡 ABWARTEN**.

Grundlage sind echte Tageskurse von Yahoo Finance (kein API-Key nötig) und eine transparente, regelbasierte Chartanalyse: Trend (SMA200), Abstand zum SMA50 relativ zur Volatilität, RSI(14), Stabilisierung nach Dips, Volatilitätsregime und bei Aktien anstehende Quartalszahlen. Der Anlagehorizont liegt bei einigen Wochen bis Monaten.

Beispielfragen:

- „Soll ich jetzt Nvidia kaufen?“
- „Lohnt sich Bitcoin gerade?“
- „Ist der MSCI World gerade teuer?“
- „Hätte ich im Juni 2024 Nvidia kaufen sollen?“

> Keine Anlageberatung. Reine Kursanalyse ohne Fundamentaldaten oder News.

## Installation

### Claude Code

```bash
./install.sh
```

Kopiert den Skill nach `~/.claude/skills/buy-or-wait` (bzw. `$CLAUDE_CONFIG_DIR/skills`). Weitere Optionen:

```bash
./install.sh --link        # Symlink statt Kopie, für die Entwicklung im Repo
./install.sh --target DIR  # anderes Skills-Verzeichnis
./install.sh --uninstall   # wieder entfernen
```

### Claude.ai / Claude Desktop

Lade `buy-or-wait.skill` aus dem [neuesten Release](https://github.com/sboe0705/buy-or-wait-skill/releases/latest) herunter und lade es in den Skill-Einstellungen von Claude hoch.

**Voraussetzung:** Python 3 (nur Standardbibliothek).

## Analyse-Skript direkt nutzen

```bash
python3 buy-or-wait/scripts/analyze.py NVDA
python3 buy-or-wait/scripts/analyze.py BTC-EUR
python3 buy-or-wait/scripts/analyze.py NVDA --as-of 2024-06-18
python3 buy-or-wait/scripts/analyze.py --search "Rheinmetall"
```

Die Ausgabe ist JSON mit Kennzahlen und einer Vorbewertung (`vorbewertung.empfehlung`, `score`, `signale`).

## Entwicklung

```bash
./build.sh [VERSION]
```

Prüft `SKILL.md` und die Skripte und baut nach `dist/`:

- `buy-or-wait.skill`: Skill-Paket zum Hochladen
- `buy-or-wait-<VERSION>.zip`: Skill plus `install.sh`
- `SHA256SUMS`

Testfälle für Skill-Evals liegen unter `buy-or-wait/evals/` und werden nicht mit ausgeliefert. Ein Tag `v*` löst über GitHub Actions ein Release aus.

## Support

Wenn dir dieser Skill nützlich ist, kannst du seine Weiterentwicklung mit einem Kaffee unterstützen: [buymeacoffee.com/sboe0705](https://buymeacoffee.com/sboe0705) ☕
