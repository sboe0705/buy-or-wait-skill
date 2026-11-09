#!/usr/bin/env bash
#
# release.sh – taggt ein neues Release des buy-or-wait Skills.
#
# Zeigt das letzte Release-Tag und die Commits seitdem, schlägt die nächste
# semantische Version vor (vorausgefüllt, editierbar), prüft das Repo
# (shellcheck + build.sh), legt dann auf main ein annotiertes Tag vX.Y.Z an und
# pusht es. Der Push startet .github/workflows/release.yml, das das Zip baut
# und das Release veröffentlicht.
#
# Vorgeschlagene Version, abgeleitet aus den Commits seit dem letzten Tag:
#   "BREAKING" irgendwo in einer Commit-Nachricht      → Major
#   ein Betreff, der mit "add" oder "remove" beginnt   → Minor
#   alles andere                                       → Patch
# Optionen: ./release.sh --help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REMOTE=origin
BRANCH=main

usage() {
  cat <<USAGE
Aufruf: ./release.sh [Optionen]

Taggt den aktuellen Stand von $BRANCH als neue Version (vX.Y.Z) und pusht das Tag.

Optionen:
  --version X.Y.Z  diese Version verwenden statt zu fragen (das "v" ist optional)
  --yes            nicht nachfragen
  --skip-tests     shellcheck und build.sh vor dem Taggen überspringen
  --dry-run        nur anzeigen, was passieren würde, nichts ändern
  -h, --help       diese Hilfe anzeigen
USAGE
}

VERSION=""
ASSUME_YES=0
RUN_TESTS=1
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Fehler: --version braucht einen Wert" >&2; exit 1; }
      VERSION="$2"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    --skip-tests) RUN_TESTS=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Fehler: unbekanntes Argument '$1' (siehe --help)" >&2; exit 1 ;;
  esac
done

die() { echo "Fehler: $*" >&2; exit 1; }
run() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "  (Probelauf) $*"; else "$@"; fi
}
confirm() {  # confirm "Frage" → 0 bei Ja (Standard: Ja)
  [[ $ASSUME_YES -eq 1 ]] && return 0
  [[ -t 0 ]] || die "kein Terminal, um '$1' zu fragen (--yes verwenden)"
  local answer
  read -r -p "$1 [J/n] " answer
  [[ -z "$answer" || "$answer" =~ ^[JjYy] ]]
}

# --- Voraussetzungen -------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || die "kein Git-Repository"
current=$(git symbolic-ref --short -q HEAD || true)
[[ "$current" == "$BRANCH" ]] || die "Releases werden auf $BRANCH getaggt, du bist aber auf '${current:-einem losgelösten HEAD}'"
git diff --quiet && git diff --cached --quiet || die "es gibt nicht committete Änderungen; erst committen oder stashen"

echo "Hole $REMOTE…"
if ! git fetch --quiet --tags "$REMOTE" "$BRANCH"; then
  echo "Warnung: $REMOTE nicht erreichbar; verwende den lokalen Stand" >&2
fi

if upstream=$(git rev-parse -q --verify "$REMOTE/$BRANCH"); then
  read -r behind ahead < <(git rev-list --left-right --count "$upstream...HEAD")
  [[ $behind -eq 0 ]] || die "$BRANCH liegt $behind Commit(s) hinter $REMOTE/$BRANCH; erst pullen"
else
  ahead=0
fi

# --- Letztes Release und Änderungen seitdem --------------------------------
latest=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)

echo
if [[ -n "$latest" ]]; then
  echo "Letztes Release: $latest ($(git log -1 --format='%cs' "$latest"))"
  range="$latest..HEAD"
else
  echo "Letztes Release: noch keins"
  range="HEAD"
fi

commits=$(git log --format='%h %s' "$range")
[[ -n "$commits" ]] || die "keine Commits seit $latest; nichts zu releasen"
echo
echo "Commits seit ${latest:-Beginn}:"
sed 's/^/  /' <<<"$commits"

# --- Nächste Version vorschlagen -------------------------------------------
if [[ -z "$latest" ]]; then
  suggestion="v1.0.0"; reason="erstes Release"
else
  IFS=. read -r major minor patch <<<"${latest#v}"
  if git log --format='%B' "$range" | grep -q 'BREAKING'; then
    suggestion="v$((major + 1)).0.0"; reason="Major: ein Commit enthält BREAKING"
  elif git log --format='%s' "$range" | grep -qiE '^(add|remove)\b'; then
    suggestion="v$major.$((minor + 1)).0"; reason="Minor: Funktionen hinzugefügt oder entfernt"
  else
    suggestion="v$major.$minor.$((patch + 1))"; reason="Patch: nur Korrekturen und Änderungen"
  fi
fi

echo
echo "Vorgeschlagene Version: $suggestion ($reason)"
if [[ -z "$VERSION" ]]; then
  if [[ -t 0 && $ASSUME_YES -eq 0 ]]; then
    read -r -e -i "$suggestion" -p "Zu veröffentlichende Version: " VERSION
  else
    VERSION="$suggestion"
  fi
fi

VERSION="v${VERSION#v}"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'$VERSION' ist keine Version wie v1.2.3"
git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null && die "Tag $VERSION existiert bereits"
if [[ -n "$latest" ]]; then
  highest=$(printf '%s\n%s\n' "$latest" "$VERSION" | sort -V | tail -n1)
  [[ "$highest" == "$VERSION" ]] || die "$VERSION ist niedriger als das letzte Release $latest"
fi

# --- Prüfen ----------------------------------------------------------------
if [[ $RUN_TESTS -eq 1 ]]; then
  echo
  if command -v shellcheck >/dev/null 2>&1; then
    echo "Prüfe Shell-Skripte…"
    shellcheck install.sh build.sh release.sh || die "shellcheck fehlgeschlagen; kein Tag (--skip-tests zum Übergehen)"
  else
    echo "Warnung: shellcheck nicht installiert; übersprungen (die CI prüft es)" >&2
  fi
  ./build.sh || die "build.sh fehlgeschlagen; kein Tag (--skip-tests zum Übergehen)"
fi

# --- Taggen und pushen -----------------------------------------------------
echo
if [[ $ahead -gt 0 ]]; then
  echo "$BRANCH hat $ahead Commit(s), die noch nicht auf $REMOTE sind; sie werden zuerst gepusht."
fi
confirm "$(git rev-parse --short HEAD) als $VERSION taggen und nach $REMOTE pushen?" || { echo "Abgebrochen."; exit 1; }

if [[ $ahead -gt 0 ]]; then
  run git push "$REMOTE" "$BRANCH"
fi
run git tag -a "$VERSION" -m "$VERSION"
run git push "$REMOTE" "$VERSION"

url=$(git remote get-url "$REMOTE" | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')
echo
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Probelauf: nichts getaggt oder gepusht."
  exit 0
fi
echo "$VERSION veröffentlicht. Der Release-Workflow baut das Zip und veröffentlicht es:"
echo "  $url/actions/workflows/release.yml"
echo "  $url/releases/tag/$VERSION"
