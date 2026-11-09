#!/usr/bin/env bash
# Prüft den buy-or-wait Skill und baut die Pakete nach dist/.
#
#   ./build.sh [VERSION]
#
# Ergebnis:
#   dist/buy-or-wait.skill            Skill-Paket (Zip) zum Hochladen in Claude
#   dist/buy-or-wait-<VERSION>.zip    Skill + install.sh für die lokale Installation
#   dist/SHA256SUMS                   Prüfsummen
#
# VERSION: Argument, sonst $VERSION, sonst `git describe`, sonst "dev".
set -euo pipefail

SKILL_NAME="buy-or-wait"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$ROOT/$SKILL_NAME"
DIST="$ROOT/dist"

VERSION="${1:-${VERSION:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}}"
VERSION="${VERSION#v}"

echo "🔍 Prüfe Skill ($SKILL_NAME, Version $VERSION)"
python3 - "$SKILL_DIR" "$SKILL_NAME" <<'EOF'
import re, sys, pathlib
skill_dir, name = pathlib.Path(sys.argv[1]), sys.argv[2]
text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    sys.exit("SKILL.md: YAML-Frontmatter fehlt")
fm = dict(line.split(":", 1) for line in m.group(1).splitlines() if ":" in line and not line.startswith(" "))
fm = {k.strip(): v.strip() for k, v in fm.items()}
errors = []
if fm.get("name") != name:
    errors.append(f"name muss '{name}' sein, ist '{fm.get('name')}'")
desc = fm.get("description", "")
if not desc:
    errors.append("description fehlt")
elif len(desc) > 1024:
    errors.append(f"description zu lang ({len(desc)} > 1024 Zeichen)")
if "<" in desc or ">" in desc:
    errors.append("description darf keine spitzen Klammern enthalten")
if len(text.splitlines()) > 500:
    errors.append("SKILL.md hat mehr als 500 Zeilen")
if errors:
    sys.exit("SKILL.md ungültig:\n  - " + "\n  - ".join(errors))
print(f"  SKILL.md ok (description {len(desc)} Zeichen)")
EOF

[[ -f "$ROOT/LICENSE" ]] || { echo "LICENSE fehlt" >&2; exit 1; }
[[ -f "$SKILL_DIR/NOTICE" ]] || { echo "$SKILL_NAME/NOTICE fehlt" >&2; exit 1; }
python3 -m py_compile "$SKILL_DIR"/scripts/*.py
python3 "$SKILL_DIR/scripts/analyze.py" --help >/dev/null
find "$SKILL_DIR" -name __pycache__ -type d -prune -exec rm -rf {} +
echo "  Skripte ok"

echo "📦 Baue Pakete"
rm -rf "$DIST"
mkdir -p "$DIST"
python3 - "$ROOT" "$SKILL_NAME" "$DIST" "$VERSION" <<'EOF'
import sys, zipfile, pathlib
root, name, dist, version = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3]), sys.argv[4]
skill = root / name

def skill_files():
    for p in sorted(skill.rglob("*")):
        rel = p.relative_to(root)
        if not p.is_file() or "__pycache__" in rel.parts or p.suffix == ".pyc":
            continue
        if len(rel.parts) > 1 and rel.parts[1] == "evals":   # Testfälle nicht ausliefern
            continue
        yield p, rel

def add(z, path, arcname):
    info = zipfile.ZipInfo(str(arcname), date_time=(1980, 1, 1, 0, 0, 0))  # reproduzierbar
    info.external_attr = (0o755 if path.stat().st_mode & 0o111 else 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, path.read_bytes())

# LICENSE liegt im Repo-Root und kommt beim Packen in den Skill-Ordner
license_file = root / "LICENSE"

with zipfile.ZipFile(dist / f"{name}.skill", "w") as z:
    for p, rel in skill_files():
        add(z, p, rel)
    add(z, license_file, pathlib.Path(name) / "LICENSE")

bundle = f"{name}-{version}"
with zipfile.ZipFile(dist / f"{bundle}.zip", "w") as z:
    for p, rel in skill_files():
        add(z, p, pathlib.Path(bundle) / rel)
    add(z, license_file, pathlib.Path(bundle) / name / "LICENSE")
    add(z, root / "install.sh", pathlib.Path(bundle) / "install.sh")
EOF

if command -v sha256sum >/dev/null; then SHA=(sha256sum); else SHA=(shasum -a 256); fi
(cd "$DIST" && "${SHA[@]}" -- * > SHA256SUMS)
ls -l "$DIST"
echo "✅ Fertig"
