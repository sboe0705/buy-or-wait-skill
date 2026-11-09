#!/usr/bin/env bash
#
# release.sh – tags a new release of the buy-or-wait skill.
#
# Shows the latest release tag and the commits since then, suggests the next
# semantic version (prefilled, editable), checks the repo (shellcheck +
# build.sh), then creates an annotated tag vX.Y.Z on main and pushes it. The
# push triggers .github/workflows/release.yml, which builds the zip and
# publishes the release.
#
# Suggested version, derived from the commits since the last tag:
#   "BREAKING" anywhere in a commit message           → major
#   a subject starting with "add" or "remove"         → minor
#   anything else                                     → patch
# Options: ./release.sh --help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REMOTE=origin
BRANCH=main

usage() {
  cat <<USAGE
Usage: ./release.sh [options]

Tags the current state of $BRANCH as a new version (vX.Y.Z) and pushes the tag.

Options:
  --version X.Y.Z  use this version instead of asking (the "v" is optional)
  --yes            do not ask for confirmation
  --skip-tests     skip shellcheck and build.sh before tagging
  --dry-run        only show what would happen, change nothing
  -h, --help       show this help
USAGE
}

VERSION=""
ASSUME_YES=0
RUN_TESTS=1
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Error: --version requires a value" >&2; exit 1; }
      VERSION="$2"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    --skip-tests) RUN_TESTS=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument '$1' (see --help)" >&2; exit 1 ;;
  esac
done

die() { echo "Error: $*" >&2; exit 1; }
run() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "  (dry run) $*"; else "$@"; fi
}
confirm() {  # confirm "question" → 0 on yes (default: yes)
  [[ $ASSUME_YES -eq 1 ]] && return 0
  [[ -t 0 ]] || die "no terminal to ask '$1' (use --yes)"
  local answer
  read -r -p "$1 [Y/n] " answer
  [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}

# --- Prerequisites ---------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || die "not a Git repository"
current=$(git symbolic-ref --short -q HEAD || true)
[[ "$current" == "$BRANCH" ]] || die "releases are tagged on $BRANCH, but you are on '${current:-a detached HEAD}'"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "there are uncommitted changes; commit or stash them first"
fi

echo "Fetching $REMOTE…"
if ! git fetch --quiet --tags "$REMOTE" "$BRANCH"; then
  echo "Warning: $REMOTE unreachable; using the local state" >&2
fi

if upstream=$(git rev-parse -q --verify "$REMOTE/$BRANCH"); then
  read -r behind ahead < <(git rev-list --left-right --count "$upstream...HEAD")
  [[ $behind -eq 0 ]] || die "$BRANCH is $behind commit(s) behind $REMOTE/$BRANCH; pull first"
else
  ahead=0
fi

# --- Latest release and changes since then ---------------------------------
latest=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)

echo
if [[ -n "$latest" ]]; then
  echo "Latest release: $latest ($(git log -1 --format='%cs' "$latest"))"
  range="$latest..HEAD"
else
  echo "Latest release: none yet"
  range="HEAD"
fi

commits=$(git log --format='%h %s' "$range")
[[ -n "$commits" ]] || die "no commits since $latest; nothing to release"
echo
echo "Commits since ${latest:-the beginning}:"
sed 's/^/  /' <<<"$commits"

# --- Suggest the next version ----------------------------------------------
if [[ -z "$latest" ]]; then
  suggestion="v1.0.0"; reason="first release"
else
  IFS=. read -r major minor patch <<<"${latest#v}"
  if git log --format='%B' "$range" | grep -q 'BREAKING'; then
    suggestion="v$((major + 1)).0.0"; reason="major: a commit contains BREAKING"
  elif git log --format='%s' "$range" | grep -qiE '^(add|remove)\b'; then
    suggestion="v$major.$((minor + 1)).0"; reason="minor: features added or removed"
  else
    suggestion="v$major.$minor.$((patch + 1))"; reason="patch: only fixes and changes"
  fi
fi

echo
echo "Suggested version: $suggestion ($reason)"
if [[ -z "$VERSION" ]]; then
  if [[ -t 0 && $ASSUME_YES -eq 0 ]]; then
    read -r -e -i "$suggestion" -p "Version to release: " VERSION
  else
    VERSION="$suggestion"
  fi
fi

VERSION="v${VERSION#v}"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'$VERSION' is not a version like v1.2.3"
git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null && die "tag $VERSION already exists"
if [[ -n "$latest" ]]; then
  highest=$(printf '%s\n%s\n' "$latest" "$VERSION" | sort -V | tail -n1)
  [[ "$highest" == "$VERSION" ]] || die "$VERSION is lower than the latest release $latest"
fi

# --- Checks ----------------------------------------------------------------
if [[ $RUN_TESTS -eq 1 ]]; then
  echo
  if command -v shellcheck >/dev/null 2>&1; then
    echo "Checking shell scripts…"
    shellcheck install.sh build.sh release.sh || die "shellcheck failed; no tag (--skip-tests to override)"
  else
    echo "Warning: shellcheck not installed; skipped (CI checks it)" >&2
  fi
  ./build.sh || die "build.sh failed; no tag (--skip-tests to override)"
fi

# --- Tag and push ----------------------------------------------------------
echo
if [[ $ahead -gt 0 ]]; then
  echo "$BRANCH has $ahead commit(s) not yet on $REMOTE; they will be pushed first."
fi
confirm "Tag $(git rev-parse --short HEAD) as $VERSION and push to $REMOTE?" || { echo "Aborted."; exit 1; }

if [[ $ahead -gt 0 ]]; then
  run git push "$REMOTE" "$BRANCH"
fi
run git tag -a "$VERSION" -m "$VERSION"
run git push "$REMOTE" "$VERSION"

url=$(git remote get-url "$REMOTE" | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')
echo
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run: nothing tagged or pushed."
  exit 0
fi
echo "$VERSION pushed. The release workflow builds the zip and publishes it:"
echo "  $url/actions/workflows/release.yml"
echo "  $url/releases/tag/$VERSION"
