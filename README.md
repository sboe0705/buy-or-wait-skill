# buy-or-wait

A [Claude Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview) that gives a clear entry recommendation for a stock, ETF or cryptocurrency: **🟢 BUY**, **🔴 DON'T BUY** or **🟡 WAIT**.

It is based on real daily prices from Yahoo Finance (no API key needed) and a transparent, rule-based chart analysis: trend (SMA200), distance to the SMA50 relative to volatility, RSI(14), stabilization after dips, volatility regime and, for stocks, upcoming earnings. The investment horizon is a few weeks to months.

Example questions:

- "Should I buy Nvidia now?"
- "Is Bitcoin worth it right now?"
- "Is the MSCI World expensive at the moment?"
- "Should I have bought Nvidia in June 2024?"

> Not investment advice. Pure price analysis without fundamentals or news.

## Installation

### Claude Code

```bash
./install.sh
```

Copies the skill to `~/.claude/skills/buy-or-wait` (or `$CLAUDE_CONFIG_DIR/skills`). More options:

```bash
./install.sh --link        # symlink instead of copy, for development in the repo
./install.sh --target DIR  # different skills directory
./install.sh --uninstall   # remove again
```

### Claude.ai / Claude Desktop

Download [`buy-or-wait.zip`](https://github.com/sboe0705/buy-or-wait-skill/releases/latest/download/buy-or-wait.zip) from the latest release and upload it in Claude's skill settings.

**Requirement:** Python 3 (standard library only).

## Using the analysis script directly

```bash
python3 buy-or-wait/scripts/analyze.py NVDA
python3 buy-or-wait/scripts/analyze.py BTC-EUR
python3 buy-or-wait/scripts/analyze.py NVDA --as-of 2024-06-18
python3 buy-or-wait/scripts/analyze.py --search "Rheinmetall"
```

The output is JSON with indicators and a pre-assessment (`pre_assessment.verdict`, `score`, `signals`).

## Development

```bash
./build.sh
```

Checks `SKILL.md` and the scripts and builds `dist/buy-or-wait.zip`: the skill folder including `LICENSE`, importable directly as a skill. The file name is version-independent, so `releases/latest/download/buy-or-wait.zip` always points to the latest build.

Test cases for skill evals live in `buy-or-wait/evals/` and are not shipped. A `v*` tag triggers a release via GitHub Actions; `./release.sh` suggests the next version, runs the checks and pushes the tag.

## Support

If you find this skill useful, you can support its development with a coffee: [buymeacoffee.com/sboe0705](https://buymeacoffee.com/sboe0705) ☕

## License

[Apache License 2.0](LICENSE) · Copyright 2026 Sebastian Böhm. The skill package contains `LICENSE` and `NOTICE`.
