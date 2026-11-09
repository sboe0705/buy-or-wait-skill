#!/usr/bin/env bash
# Prüft den buy-or-wait Skill und baut das Skill-Paket nach dist/.
#
#   ./build.sh
#
# Ergebnis:
#   dist/buy-or-wait.zip   Skill-Ordner (mit LICENSE) als reproduzierbares Zip,
#                          direkt als Skill importierbar
set -euo pipefail

SKILL_NAME="buy-or-wait"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$ROOT/$SKILL_NAME"
DIST="$ROOT/dist"

echo "🔍 Prüfe Skill ($SKILL_NAME)"
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

echo "📦 Baue Paket"
rm -rf "$DIST"
mkdir -p "$DIST"
python3 - "$ROOT" "$SKILL_NAME" "$DIST" <<'EOF'
import sys, zipfile, pathlib
root, name, dist = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
skill = root / name

def add(z, path, arcname):
    info = zipfile.ZipInfo(str(arcname), date_time=(1980, 1, 1, 0, 0, 0))  # reproduzierbar
    info.external_attr = (0o755 if path.stat().st_mode & 0o111 else 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, path.read_bytes())

with zipfile.ZipFile(dist / f"{name}.zip", "w") as z:
    for p in sorted(skill.rglob("*")):
        rel = p.relative_to(root)
        if not p.is_file() or "__pycache__" in rel.parts or p.suffix == ".pyc":
            continue
        if len(rel.parts) > 1 and rel.parts[1] == "evals":   # Testfälle nicht ausliefern
            continue
        add(z, p, rel)
    # LICENSE liegt im Repo-Root und kommt beim Packen in den Skill-Ordner
    add(z, root / "LICENSE", pathlib.Path(name) / "LICENSE")
EOF

ls -l "$DIST"
echo "✅ Fertig"
