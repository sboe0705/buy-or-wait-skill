# AGENTS.md

Notes for AI agents working in this repository.

## Overview

The repo contains exactly one Claude Skill: `buy-or-wait`. It gives a timing recommendation (BUY / DON'T BUY / WAIT) for stocks, ETFs and cryptocurrencies based on Yahoo Finance price data.

```
buy-or-wait/
  SKILL.md              skill instructions (frontmatter + workflow), shipped
  NOTICE                author, license, repo link, support link; shipped
  scripts/analyze.py    fetch price data, indicators + pre-assessment as JSON
  evals/<case>/         test cases (case.yaml, prompt.md, graders/*.md), NOT shipped
LICENSE                 Apache-2.0; build.sh/install.sh put it into the skill folder
install.sh              local installation to ~/.claude/skills
build.sh                validation + dist/buy-or-wait.zip
release.sh              suggest next version, check, push tag vX.Y.Z
.github/workflows/      build.yml (CI), release.yml (tag v* → GitHub release)
```

## Conventions

- **Language:** everything in the repo is in English: skill content, script output, comments, shell messages, evals and docs. The skill itself answers in the user's language.
- **No dependencies:** `analyze.py` uses only the Python standard library. Do not add packages.
- **JSON keys** in the script output (`pre_assessment`, `verdict`, `signals`, `next_earnings`, …) are referenced by `SKILL.md` and the smoke test in `build.yml`. If you change them, update both.
- **SKILL.md rules** (checked by `build.sh`): `name: buy-or-wait`, `description` present, at most 1024 characters, no angle brackets; file under 500 lines. Also `license: Apache-2.0` and `metadata.author`.
- **No links in `metadata`, no donation link in texts the agent reads** (`SKILL.md`, script output, future `references/`). Otherwise it ends up in the context and might be mentioned to users. The Buy Me a Coffee link lives only in `NOTICE`, `README.md` and `.github/FUNDING.yml`.
- **Do not duplicate LICENSE** into the skill folder: `build.sh` adds it when packing, `install.sh` when copying.
- **Content guardrails of the skill:** it only answers the timing question. No savings-plan/tranche suggestions, no invented price targets. WAIT is the normal case. The evals check this; do not soften it.
- **Shell scripts** must pass `shellcheck` (CI) and run with `set -euo pipefail`.

## Checks

Before every commit:

```bash
shellcheck install.sh build.sh release.sh
./build.sh
```

Optional (needs network access to Yahoo Finance):

```bash
python3 buy-or-wait/scripts/analyze.py NVDA --as-of 2024-06-18
```

Expected pre-assessment: `DON'T BUY`.

## Evals

Each case under `buy-or-wait/evals/<name>/` consists of `case.yaml` (with `expected_outcome`), `prompt.md` and numbered graders `graders/NN-<topic>.md` (frontmatter `type: llm`, `focus`, `weight`). Create new cases following the same pattern; historical cases use `--as-of` so they stay reproducible.

## Release

`./release.sh` suggests the next version based on the commits since the last tag, checks with `shellcheck` and `./build.sh` and pushes the tag (`--dry-run` to try it out, `--help` for all options). Alternatively push a `vX.Y.Z` tag by hand. `release.yml` builds and publishes `dist/buy-or-wait.zip` (version-independent name). Tags with a hyphen (e.g. `v1.0.0-rc1`) are marked as pre-releases.

## Git workflow

- Always work directly on the `main` branch.
- Do not create Git branches (no feature branches, no `git checkout -b`, no `git switch -c`, no worktrees on other branches).
- If a session environment or a tool instruction requires a separate branch, tell the user and stay on `main`, unless the user explicitly says otherwise in the conversation.
