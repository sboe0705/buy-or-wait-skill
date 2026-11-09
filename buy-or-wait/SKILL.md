---
name: buy-or-wait
description: Gives a clear entry recommendation for a stock, ETF or cryptocurrency – BUY, DON'T BUY or WAIT – based on the current price and recent price action (trend, overheating, dip, volatility), using real price data from Yahoo Finance. Always use this skill when someone wants to know whether now is a good time to buy, get in or add to a position, whether something is overvalued or has run too hot, or whether to buy a dip or rather wait – e.g. "Should I buy Nvidia now?", "Is Bitcoin worth it right now?", "Is the MSCI World expensive at the moment?", "buy the dip on Tesla?", "should I buy ETH now or wait?" – in any language, even if the word "skill" is not mentioned and only a ticker symbol or name is given.
license: Apache-2.0
metadata:
  author: Sebastian Böhm
---

# Buy or Wait

Goal: a transparent, honest assessment of the **entry timing** for an investment horizon of
**a few weeks to months**. The question is not whether a company is fundamentally good, but
whether *now* is a favorable moment to buy.

The three possible outcomes:

| Verdict | Meaning | Typical situation |
|---|---|---|
| 🟢 **BUY** | Good entry likely | Pullback (dip) within an intact uptrend, price is already stabilizing |
| 🔴 **DON'T BUY** | Price has probably run too hot | Steep rise, heavily overbought, far above the averages – a setback is more likely than another sprint |
| 🟡 **WAIT** | No clear opportunity | Mixed signals, sideways phase, falling knife without a bottom, extreme uncertainty |

WAIT is the normal case, not a cop-out: most of the time there is neither a clear dip nor
clear overheating. A buy recommendation should mean something, so it is only given when the
situation really looks favorable.

## Workflow

### 1. Determine the symbol

The script needs a Yahoo Finance symbol. Examples: `AAPL`, `NVDA`, `SAP.DE`, `RHM.DE`,
`EUNL.DE` (iShares Core MSCI World, Xetra), `VWCE.DE`, `BTC-EUR`, `ETH-EUR`, `SOL-EUR`.

- If the person gives a name instead of a symbol, search:
  `python3 <skill-dir>/scripts/analyze.py --search "Rheinmetall"`
- Pick the main listing: for German stocks and European UCITS ETFs the Xetra listing
  (`.DE`), for US stocks the US symbol without suffix. For crypto use `-EUR`, unless the person
  talks in dollars (then `-USD`). Avoid OTC listings (e.g. `RNMBY`).
- If the person gives an ISIN or WKN, try searching with it; if that fails, ask for the name.
- If it is unclear which security is meant (e.g. "the Vanguard ETF"), ask briefly instead of
  guessing – a recommendation for the wrong security is worse than a follow-up question.

### 2. Run the analysis

```bash
python3 <skill-dir>/scripts/analyze.py <SYMBOL>
```

The script fetches ~2 years of daily prices and returns JSON with performance, moving averages
(SMA20/50/200), RSI(14), distance to highs/lows, volatility and a rule-based
**pre-assessment** (`pre_assessment.verdict`, `score`, list of `signals` with points).
On errors (e.g. HTTP 404) the symbol is usually wrong → use the search.

For several securities in one question: run it for each one and assess each separately.

If the person asks about a past point in time ("Should I have bought in June 2024?"), use
`--as-of YYYY-MM-DD`. Then only prices up to that day count, and earnings dates are not
fetched. Assess as if today were that day. Afterwards you may add the later price development
in one sentence as the resolution, if the person asks for it or is obviously interested.

### 3. Assess

The script's pre-assessment is the starting point. It is deliberately simple and transparent.
Adopt it in the normal case; only deviate if the numbers clearly show something the rules do
not capture – and then say openly why.

What the rules look at, so you can explain the signals:

- **Trend (SMA200):** price above a *rising* 200-day average = intact uptrend. A dip within it
  is often bought back. Below a *falling* SMA200, on the other hand, a price decline is often
  part of a larger downtrend ("falling knife").
- **Stretch:** distance to the SMA50 divided by the monthly volatility. This makes calm ETFs
  and wild cryptos comparable: +8 % above the SMA50 is extreme for an MSCI World, normal for
  Bitcoin. Above ~1.5 = heavily stretched, below ~−1 = clear pullback.
- **RSI(14):** above ~70 overbought, below ~30 oversold.
- **Rise in sigma:** monthly return relative to the usual fluctuation; above 2 means
  "unusually steep".
- **Stabilization:** no new lows in the last 5 days. Without stabilization a dip is not over
  yet – then rather WAIT, even if the price looks "cheap".
- **Volatility regime:** if current volatility is clearly higher than the yearly average, the
  forecast is less certain.

- **Earnings:** for stocks the script returns `next_earnings` (date, days until then). If they
  are within ~2 weeks, that is an event risk: the results can move the price sharply in either
  direction. Always mention the date in the answer then – even if it does not flip the
  verdict. If the field is `null` (ETF, crypto or no date available), leave the topic out.

Limits you should name honestly: this is pure price/chart analysis. Whether a crash has a
fundamental reason (bad results, scandal, profit warning) is invisible to the script. If it
reports an "exceptionally sharp drop", point out that the person should check the cause
before buying.

### 4. Write the answer

Answer in the person's language, short and clear. Translate the verdict label into that
language if it is not English (e.g. German: KAUFEN / NICHT KAUFEN / ABWARTEN). Structure:

```
## <Emoji> <VERDICT> – <Name> (<Symbol>)

**Price:** <price> <currency> (as of <date>) · 1 month <±x %> · 3 months <±x %> · 1 year <±x %>
<only for stocks with earnings in ≤ 14 days: **📅 Earnings on <date> (in <n> days)** – briefly what that means>

**In short:** <one or two sentences on why – in plain language>

**The signals:**
- <2–5 most important signals, with concrete numbers, explained clearly>

**What would change the picture:** <concrete, with price levels where possible – e.g. "A
pullback towards the SMA50 (~185 USD) would be a better entry" or "Only once the price closes
above the SMA200 (~41,000 EUR) again, …">

<One line of disclaimer: not investment advice, pure price analysis without fundamentals/news.>
```

Notes on tone:
- Round numbers (one decimal place is enough) and briefly explain technical terms the first
  time they appear ("RSI 78 – a value above 70 is considered overbought").
- Do not water down the verdict. If the result is BUY, say so clearly – along with the risk.
  If it is WAIT, explain what to wait for.
- The "What would change the picture" section is the most useful part for the person, because
  it turns a "no" into a plan.
- Do not invent price targets or probabilities that do not follow from the data.
- **Stick to the timing question.** The person wants a quick decision aid for the entry
  timing – not general investment advice. So do not suggest alternative strategies such as a
  savings plan, cost averaging or "buying in tranches", and do not lecture about
  diversification, emergency funds, taxes or "timing doesn't work". Whoever uses this skill
  knows the risks and has consciously chosen a one-off decision. The answer should answer the
  question "buy now or not?", not a different one.
