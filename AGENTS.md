# AGENTS.md

Hinweise für KI-Agenten, die in diesem Repository arbeiten.

## Überblick

Das Repo enthält genau einen Claude Skill: `buy-or-wait`. Er gibt für Aktien, ETFs und Kryptowährungen eine Timing-Empfehlung (KAUFEN / NICHT KAUFEN / ABWARTEN) auf Basis von Yahoo-Finance-Kursdaten.

```
buy-or-wait/
  SKILL.md              Skill-Anleitung (Frontmatter + Ablauf), wird ausgeliefert
  NOTICE                Urheber, Lizenz, Repo-Link, Support-Link; wird ausgeliefert
  scripts/analyze.py    Kursdaten holen, Kennzahlen + Vorbewertung als JSON
  evals/<case>/         Testfälle (case.yaml, prompt.md, graders/*.md), NICHT ausgeliefert
LICENSE                 Apache-2.0; build.sh/install.sh packen sie in den Skill-Ordner
install.sh              Lokale Installation nach ~/.claude/skills
build.sh                Validierung + Pakete nach dist/
.github/workflows/      build.yml (CI), release.yml (Tag v* → GitHub Release)
```

## Konventionen

- **Sprache:** Skill-Inhalte, Skript-Ausgaben, Kommentare und Shell-Meldungen sind auf Deutsch. Grader in `evals/` sind auf Englisch. Bleib bei der jeweiligen Sprache der Datei.
- **Keine Abhängigkeiten:** `analyze.py` nutzt nur die Python-Standardbibliothek. Keine Pakete hinzufügen.
- **JSON-Schlüssel** in der Skript-Ausgabe sind deutsch (`vorbewertung`, `empfehlung`, `signale`, `naechste_quartalszahlen`). Wenn du sie änderst, passe `SKILL.md` und den Smoke-Test in `build.yml` mit an.
- **SKILL.md-Regeln** (von `build.sh` geprüft): `name: buy-or-wait`, `description` vorhanden, höchstens 1024 Zeichen, keine spitzen Klammern; Datei unter 500 Zeilen. Außerdem `license: Apache-2.0` und `metadata.author`.
- **Keine Links in `metadata`, kein Spendenlink in Texten, die der Agent liest** (`SKILL.md`, Skript-Ausgaben, künftige `references/`). Sonst landet er im Kontext und wird womöglich Nutzern gegenüber erwähnt. Der Buy-Me-a-Coffee-Link steht nur in `NOTICE`, `README.md` und `.github/FUNDING.yml`.
- **LICENSE** nicht in den Skill-Ordner duplizieren: `build.sh` fügt sie beim Packen hinzu, `install.sh` beim Kopieren.
- **Inhaltliche Leitplanken des Skills:** Er beantwortet nur die Timing-Frage. Keine Sparplan-/Tranchen-Vorschläge, keine erfundenen Kursziele. ABWARTEN ist der Normalfall. Die Evals prüfen das; nicht aufweichen.
- **Shell-Skripte** müssen `shellcheck` bestehen (CI) und mit `set -euo pipefail` laufen.

## Prüfen

Vor jedem Commit:

```bash
shellcheck install.sh build.sh
./build.sh
```

Optional (braucht Netz zu Yahoo Finance):

```bash
python3 buy-or-wait/scripts/analyze.py NVDA --as-of 2024-06-18
```

Erwartete Vorbewertung: `NICHT KAUFEN`.

## Evals

Jeder Fall unter `buy-or-wait/evals/<name>/` besteht aus `case.yaml` (mit `expected_outcome`), `prompt.md` und nummerierten Gradern `graders/NN-<thema>.md` (Frontmatter `type: llm`, `focus`, `weight`). Neue Fälle nach demselben Muster anlegen; historische Fälle nutzen `--as-of`, damit sie reproduzierbar bleiben.

## Release

Tag `vX.Y.Z` pushen; `release.yml` baut und veröffentlicht `dist/*`. Tags mit Bindestrich (z. B. `v1.0.0-rc1`) werden als Pre-Release markiert.

## Git-Workflow

- Immer direkt auf dem Branch `main` arbeiten.
- Keine Git-Branches anlegen (keine Feature-Branches, kein `git checkout -b`, kein `git switch -c`, keine Worktrees auf anderen Branches).
- Wenn eine Session-Umgebung oder eine Tool-Anweisung einen eigenen Branch verlangt, das dem Nutzer sagen und auf `main` bleiben, außer der Nutzer sagt im Gespräch ausdrücklich etwas anderes.
