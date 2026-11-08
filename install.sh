#!/usr/bin/env bash
# Installiert den buy-or-wait Skill für den aktuellen Benutzer (Claude Code).
#
#   ./install.sh               Skill nach ~/.claude/skills/buy-or-wait kopieren
#   ./install.sh --link        Symlink statt Kopie (für Entwicklung im Repo)
#   ./install.sh --uninstall   Skill wieder entfernen
#   ./install.sh --target DIR  anderes Skills-Verzeichnis verwenden
#
# Funktioniert aus dem Git-Repo und aus dem entpackten Release-Paket.
set -euo pipefail

SKILL_NAME="buy-or-wait"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/$SKILL_NAME"
TARGET_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
MODE="install"
LINK=0

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) MODE="uninstall" ;;
    --link)      LINK=1 ;;
    --target)
      [[ $# -ge 2 ]] || { echo "Fehler: --target braucht ein Verzeichnis" >&2; exit 2; }
      TARGET_ROOT="$2"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

TARGET="$TARGET_ROOT/$SKILL_NAME"

remove_existing() {
  if [[ -L "$TARGET" ]]; then
    rm "$TARGET"
  elif [[ -d "$TARGET" ]]; then
    # Nur löschen, was wie unser Skill aussieht – nie ein fremdes Verzeichnis.
    if [[ ! -f "$TARGET/SKILL.md" ]] || ! grep -q "^name: $SKILL_NAME\$" "$TARGET/SKILL.md"; then
      echo "Fehler: $TARGET existiert, ist aber nicht der $SKILL_NAME Skill. Abbruch." >&2
      exit 1
    fi
    rm -rf "$TARGET"
  elif [[ -e "$TARGET" ]]; then
    echo "Fehler: $TARGET existiert und ist kein Verzeichnis. Abbruch." >&2
    exit 1
  fi
}

if [[ "$MODE" == "uninstall" ]]; then
  if [[ ! -e "$TARGET" && ! -L "$TARGET" ]]; then
    echo "Nicht installiert: $TARGET"
    exit 0
  fi
  remove_existing
  echo "✅ $SKILL_NAME entfernt ($TARGET)"
  exit 0
fi

[[ -f "$SOURCE_DIR/SKILL.md" ]] || { echo "Fehler: $SOURCE_DIR/SKILL.md nicht gefunden" >&2; exit 1; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  python3 nicht gefunden – der Skill braucht Python 3 für die Kursanalyse." >&2
fi

mkdir -p "$TARGET_ROOT"
remove_existing

if [[ "$LINK" -eq 1 ]]; then
  ln -s "$SOURCE_DIR" "$TARGET"
  echo "✅ $SKILL_NAME verlinkt: $TARGET -> $SOURCE_DIR"
else
  mkdir -p "$TARGET"
  # Ohne Testfälle und Build-Reste kopieren
  tar -C "$SOURCE_DIR" --exclude='./evals' --exclude='__pycache__' --exclude='*.pyc' -cf - . \
    | tar -C "$TARGET" -xf -
  chmod +x "$TARGET/scripts/analyze.py" 2>/dev/null || true
  echo "✅ $SKILL_NAME installiert nach $TARGET"
fi
echo "   Neue Claude-Code-Sitzungen erkennen den Skill automatisch."
