#!/usr/bin/env bash
# Installs the buy-or-wait skill for the current user (Claude Code).
#
#   ./install.sh               copy the skill to ~/.claude/skills/buy-or-wait
#   ./install.sh --link        symlink instead of copy (for development in the repo)
#   ./install.sh --uninstall   remove the skill again
#   ./install.sh --target DIR  use a different skills directory
#
# Works from the Git repo and from the unpacked release package.
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
      [[ $# -ge 2 ]] || { echo "Error: --target requires a directory" >&2; exit 2; }
      TARGET_ROOT="$2"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

TARGET="$TARGET_ROOT/$SKILL_NAME"

remove_existing() {
  if [[ -L "$TARGET" ]]; then
    rm "$TARGET"
  elif [[ -d "$TARGET" ]]; then
    # Only delete what looks like our skill – never someone else's directory.
    if [[ ! -f "$TARGET/SKILL.md" ]] || ! grep -q "^name: $SKILL_NAME\$" "$TARGET/SKILL.md"; then
      echo "Error: $TARGET exists but is not the $SKILL_NAME skill. Aborting." >&2
      exit 1
    fi
    rm -rf "$TARGET"
  elif [[ -e "$TARGET" ]]; then
    echo "Error: $TARGET exists and is not a directory. Aborting." >&2
    exit 1
  fi
}

if [[ "$MODE" == "uninstall" ]]; then
  if [[ ! -e "$TARGET" && ! -L "$TARGET" ]]; then
    echo "Not installed: $TARGET"
    exit 0
  fi
  remove_existing
  echo "✅ $SKILL_NAME removed ($TARGET)"
  exit 0
fi

[[ -f "$SOURCE_DIR/SKILL.md" ]] || { echo "Error: $SOURCE_DIR/SKILL.md not found" >&2; exit 1; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  python3 not found – the skill needs Python 3 for the price analysis." >&2
fi

mkdir -p "$TARGET_ROOT"
remove_existing

if [[ "$LINK" -eq 1 ]]; then
  ln -s "$SOURCE_DIR" "$TARGET"
  echo "✅ $SKILL_NAME linked: $TARGET -> $SOURCE_DIR"
else
  mkdir -p "$TARGET"
  # Copy without test cases and build leftovers
  tar -C "$SOURCE_DIR" --exclude='./evals' --exclude='__pycache__' --exclude='*.pyc' -cf - . \
    | tar -C "$TARGET" -xf -
  # In the Git repo LICENSE is in the root, in the release package already in the skill folder
  if [[ ! -f "$TARGET/LICENSE" && -f "$SCRIPT_DIR/LICENSE" ]]; then
    cp "$SCRIPT_DIR/LICENSE" "$TARGET/LICENSE"
  fi
  chmod +x "$TARGET/scripts/analyze.py" 2>/dev/null || true
  echo "✅ $SKILL_NAME installed to $TARGET"
fi
echo "   New Claude Code sessions pick up the skill automatically."
