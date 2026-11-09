#!/usr/bin/env bash
# Validates the buy-or-wait skill and builds the skill package into dist/.
#
#   ./build.sh
#
# Result:
#   dist/buy-or-wait.zip   skill folder (with LICENSE) as a reproducible zip,
#                          importable directly as a skill
set -euo pipefail

SKILL_NAME="buy-or-wait"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$ROOT/$SKILL_NAME"
DIST="$ROOT/dist"

echo "🔍 Checking skill ($SKILL_NAME)"
python3 - "$SKILL_DIR" "$SKILL_NAME" <<'EOF'
import re, sys, pathlib
skill_dir, name = pathlib.Path(sys.argv[1]), sys.argv[2]
text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    sys.exit("SKILL.md: YAML frontmatter missing")
fm = dict(line.split(":", 1) for line in m.group(1).splitlines() if ":" in line and not line.startswith(" "))
fm = {k.strip(): v.strip() for k, v in fm.items()}
errors = []
if fm.get("name") != name:
    errors.append(f"name must be '{name}', is '{fm.get('name')}'")
desc = fm.get("description", "")
if not desc:
    errors.append("description missing")
elif len(desc) > 1024:
    errors.append(f"description too long ({len(desc)} > 1024 characters)")
if "<" in desc or ">" in desc:
    errors.append("description must not contain angle brackets")
if len(text.splitlines()) > 500:
    errors.append("SKILL.md has more than 500 lines")
if errors:
    sys.exit("SKILL.md invalid:\n  - " + "\n  - ".join(errors))
print(f"  SKILL.md ok (description {len(desc)} characters)")
EOF

[[ -f "$ROOT/LICENSE" ]] || { echo "LICENSE missing" >&2; exit 1; }
[[ -f "$SKILL_DIR/NOTICE" ]] || { echo "$SKILL_NAME/NOTICE missing" >&2; exit 1; }
python3 -m py_compile "$SKILL_DIR"/scripts/*.py
python3 "$SKILL_DIR/scripts/analyze.py" --help >/dev/null
find "$SKILL_DIR" -name __pycache__ -type d -prune -exec rm -rf {} +
echo "  Scripts ok"

echo "📦 Building package"
rm -rf "$DIST"
mkdir -p "$DIST"
python3 - "$ROOT" "$SKILL_NAME" "$DIST" <<'EOF'
import sys, zipfile, pathlib
root, name, dist = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
skill = root / name

def add(z, path, arcname):
    info = zipfile.ZipInfo(str(arcname), date_time=(1980, 1, 1, 0, 0, 0))  # reproducible
    info.external_attr = (0o755 if path.stat().st_mode & 0o111 else 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, path.read_bytes())

with zipfile.ZipFile(dist / f"{name}.zip", "w") as z:
    for p in sorted(skill.rglob("*")):
        rel = p.relative_to(root)
        if not p.is_file() or "__pycache__" in rel.parts or p.suffix == ".pyc":
            continue
        if len(rel.parts) > 1 and rel.parts[1] == "evals":   # do not ship test cases
            continue
        add(z, p, rel)
    # LICENSE lives in the repo root and is added to the skill folder when packing
    add(z, root / "LICENSE", pathlib.Path(name) / "LICENSE")
EOF

ls -l "$DIST"
echo "✅ Done"
