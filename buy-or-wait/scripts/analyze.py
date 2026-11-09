#!/usr/bin/env python3
"""Price analysis for the decision "Buy / Don't buy / Wait".

Fetches daily prices from Yahoo Finance (no API key needed), computes technical
indicators and a transparent, rule-based pre-assessment. Outputs JSON.

Usage:
    python3 analyze.py AAPL
    python3 analyze.py BTC-EUR
    python3 analyze.py --search "iShares MSCI World"

Python standard library only.
"""

import argparse
import http.cookiejar
import json
import math
import statistics
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

UA = {"User-Agent": "Mozilla/5.0 (buy-or-wait-skill)"}


def fetch_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def fetch_earnings(symbol):
    """Next earnings date (stocks only). Best effort: None on errors.

    The quoteSummary endpoint requires a cookie + crumb, which we obtain without login.
    """
    try:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        opener.addheaders = list(UA.items())
        try:
            opener.open("https://fc.yahoo.com", timeout=10)
        except urllib.error.HTTPError:
            pass  # returns 404 but sets the cookie
        crumb = opener.open("https://query2.finance.yahoo.com/v1/test/getcrumb", timeout=10).read().decode()
        url = (f"https://query2.finance.yahoo.com/v10/finance/quoteSummary/{urllib.parse.quote(symbol)}"
               f"?modules=calendarEvents&crumb={urllib.parse.quote(crumb)}")
        data = json.load(opener.open(url, timeout=10))
        ev = data["quoteSummary"]["result"][0]["calendarEvents"]["earnings"]
        now = datetime.now(timezone.utc).timestamp()
        dates = sorted(d["raw"] for d in ev.get("earningsDate", []) if d["raw"] >= now - 86400)
        if not dates:
            return None
        d = datetime.fromtimestamp(dates[0], tz=timezone.utc)
        return {
            "date": d.date().isoformat(),
            "days_until": max(0, (d.date() - datetime.now(timezone.utc).date()).days),
            "estimated": bool(ev.get("isEarningsDateEstimate")),
        }
    except Exception:
        return None


def search(query, limit=8):
    q = urllib.parse.quote(query)
    url = (f"https://query1.finance.yahoo.com/v1/finance/search?q={q}"
           f"&quotesCount={limit}&newsCount=0")
    data = fetch_json(url)
    return [
        {
            "symbol": x.get("symbol"),
            "name": x.get("longname") or x.get("shortname"),
            "type": x.get("quoteType"),
            "exchange": x.get("exchDisp") or x.get("exchange"),
        }
        for x in data.get("quotes", [])
        if x.get("symbol")
    ]


def fetch_history(symbol, rng="2y", as_of=None):
    s = urllib.parse.quote(symbol)
    if as_of:
        end = int(datetime.fromisoformat(as_of).replace(tzinfo=timezone.utc).timestamp()) + 86400
        span = f"period1={end - 800 * 86400}&period2={end}"
    else:
        span = f"range={rng}"
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/{s}"
           f"?{span}&interval=1d&includeAdjustedClose=true")
    data = fetch_json(url)
    res = (data.get("chart") or {}).get("result")
    if not res:
        err = (data.get("chart") or {}).get("error")
        raise SystemExit(json.dumps({"error": f"No data for {symbol}", "detail": err}))
    res = res[0]
    meta = res["meta"]
    ts = res.get("timestamp") or []
    q = res["indicators"]["quote"][0]
    adj = (res["indicators"].get("adjclose") or [{}])[0].get("adjclose")
    closes = adj or q["close"]
    rows = [
        (t, c, h, l)
        for t, c, h, l in zip(ts, closes, q["high"], q["low"])
        if c is not None and h is not None and l is not None
    ]
    return meta, rows


def sma(xs, n):
    return sum(xs[-n:]) / n if len(xs) >= n else None


def rsi(xs, n=14):
    if len(xs) <= n:
        return None
    gains, losses = [], []
    for a, b in zip(xs[:-1], xs[1:]):
        d = b - a
        gains.append(max(d, 0))
        losses.append(max(-d, 0))
    # Wilder smoothing
    ag = sum(gains[:n]) / n
    al = sum(losses[:n]) / n
    for g, l in zip(gains[n:], losses[n:]):
        ag = (ag * (n - 1) + g) / n
        al = (al * (n - 1) + l) / n
    if al == 0:
        return 100.0
    return 100 - 100 / (1 + ag / al)


def pct(a, b):
    return None if a is None or b in (None, 0) else (a / b - 1) * 100


def ret(xs, days):
    return pct(xs[-1], xs[-1 - days]) if len(xs) > days else None


def r1(x, nd=1):
    return None if x is None else round(x, nd)


def analyze(symbol, as_of=None):
    meta, rows = fetch_history(symbol, as_of=as_of)
    if len(rows) < 60:
        raise SystemExit(json.dumps({"error": f"Not enough price history for {symbol} ({len(rows)} days)"}))

    closes = [r[1] for r in rows]
    highs = [r[2] for r in rows]
    lows = [r[3] for r in rows]
    price = closes[-1] if as_of else (meta.get("regularMarketPrice") or closes[-1])
    closes[-1] = price  # use the most recent price

    is_crypto = meta.get("instrumentType") == "CRYPTOCURRENCY"
    days_per_year = 365 if is_crypto else 252
    days_per_month = 30 if is_crypto else 21

    daily = [math.log(b / a) for a, b in zip(closes[:-1], closes[1:]) if a > 0 and b > 0]
    vol_d = statistics.pstdev(daily[-60:])          # daily volatility (60 days)
    vol_m = vol_d * math.sqrt(days_per_month)        # monthly volatility
    vol_a = vol_d * math.sqrt(days_per_year)         # annualized
    vol_a_long = statistics.pstdev(daily[-days_per_year:]) * math.sqrt(days_per_year)

    sma20, sma50, sma200 = sma(closes, 20), sma(closes, 50), sma(closes, 200)
    sma200_prev = (sum(closes[-221:-21]) / 200) if len(closes) >= 221 else None
    sma200_slope = pct(sma200, sma200_prev)          # change of SMA200 over ~1 month in %

    yr = days_per_year
    hi_52 = max(highs[-yr:])
    lo_52 = min(lows[-yr:])
    hi_3m = max(highs[-3 * days_per_month:])
    dd_from_hi52 = pct(price, hi_52)
    dd_from_hi3m = pct(price, hi_3m)

    dev50 = pct(price, sma50)
    dev200 = pct(price, sma200)
    # "Stretch": deviation from the SMA50 in units of monthly volatility.
    # Makes stocks, ETFs and crypto comparable.
    stretch50 = (dev50 / 100) / vol_m if vol_m else None
    r1m = ret(closes, days_per_month)
    r3m = ret(closes, 3 * days_per_month)
    z1m = (math.log(1 + r1m / 100) / vol_m) if (r1m is not None and vol_m) else None

    rsi14 = rsi(closes[-250:], 14)
    low_10 = min(lows[-10:])
    low_5 = min(lows[-5:])
    bounce_from_10d_low = pct(price, low_10)
    # Stabilization: no new lows in the last 5 days compared with the 5 days before
    prev_low = min(lows[-10:-5])
    stabilizing = low_5 >= prev_low

    # ---------------- Rule-based pre-assessment ----------------
    signals = []  # (points, text)

    def add(points, text):
        signals.append({"points": points, "signal": text})

    uptrend = sma200 is not None and price > sma200 and (sma200_slope or 0) > 0
    downtrend = sma200 is not None and price < sma200 and (sma200_slope or 0) < 0

    if sma200 is None:
        add(0, "Less than 200 days of history – long-term trend cannot be determined")
    elif uptrend:
        add(+1, "Long-term uptrend (price above rising SMA200)")
    elif downtrend:
        add(-2, "Long-term downtrend (price below falling SMA200)")
    else:
        add(0, "Long-term trend unclear (price and SMA200 direction contradict each other)")

    # Overheating (separate subtotal: decides "DON'T BUY")
    heat = 0
    if stretch50 is not None and stretch50 > 1.5:
        add(-2, f"Price heavily stretched above SMA50 ({dev50:+.1f} %, {stretch50:.1f}x monthly volatility)")
        heat -= 2
    elif stretch50 is not None and stretch50 > 1.0:
        add(-1, f"Price clearly above SMA50 ({dev50:+.1f} %)")
        heat -= 1
    if rsi14 is not None and rsi14 > 75:
        add(-2, f"RSI {rsi14:.0f} – heavily overbought")
        heat -= 2
    elif rsi14 is not None and rsi14 > 68:
        add(-1, f"RSI {rsi14:.0f} – overbought")
        heat -= 1
    if z1m is not None and z1m > 2.0:
        add(-1, f"Unusually steep rise over the last month ({r1m:+.1f} %, {z1m:.1f} sigma)")
        heat -= 1
    overheated = heat <= -2

    # Dip
    dip = False
    if stretch50 is not None and stretch50 < -1.0:
        dip = True
        if uptrend:
            add(+2, f"Pullback below SMA50 ({dev50:+.1f} %) within an uptrend")
        elif downtrend:
            add(-1, f"Price far below SMA50 ({dev50:+.1f} %) in a downtrend – risk of a 'falling knife'")
        else:
            add(+1, f"Price clearly below SMA50 ({dev50:+.1f} %)")
    elif stretch50 is not None and -1.0 <= stretch50 < -0.3 and uptrend:
        dip = True
        add(+1, f"Pullback within an uptrend ({dev50:+.1f} % to SMA50)")
    if rsi14 is not None and rsi14 < 30:
        add(+1 if not downtrend else 0, f"RSI {rsi14:.0f} – oversold")
        dip = True
    elif rsi14 is not None and rsi14 < 40 and uptrend:
        add(+1, f"RSI {rsi14:.0f} – cooled off within an uptrend")

    if dip:
        if stabilizing and (bounce_from_10d_low or 0) > 1:
            add(+1, f"Stabilization: no new lows in 5 days, {bounce_from_10d_low:+.1f} % above 10-day low")
        else:
            add(-1, "No stabilization yet – price keeps making new lows")

    # Extreme drops (possibly a fundamental reason)
    if dd_from_hi3m is not None and vol_m and (dd_from_hi3m / 100) / vol_m < -3:
        add(-1, f"Exceptionally sharp drop from 3-month high ({dd_from_hi3m:.1f} %) – check the cause")

    # Uncertainty from volatility
    vol_regime = vol_a / vol_a_long if vol_a_long else 1
    if vol_regime > 1.5:
        add(-1, f"Volatility currently {vol_regime:.1f}x the yearly average – increased uncertainty")

    # Event risk: upcoming earnings (stocks only, live analysis only)
    earnings = None
    if meta.get("instrumentType") == "EQUITY" and not as_of:
        earnings = fetch_earnings(meta.get("symbol", symbol))
        if earnings and earnings["days_until"] <= 14:
            add(-1, f"Earnings in {earnings['days_until']} days ({earnings['date']}) – price jump in either direction possible")

    score = sum(s["points"] for s in signals)
    # DON'T BUY = overheated/probably overvalued.
    # BUY       = dip with a good chance of recovery (no downtrend).
    # WAIT      = everything unclear, incl. falling markets without a bottom.
    if overheated:
        verdict = "DON'T BUY"
    elif score >= 3 and dip and not downtrend:
        verdict = "BUY"
    else:
        verdict = "WAIT"

    last_date = datetime.fromtimestamp(rows[-1][0], tz=timezone.utc).date().isoformat()
    market_time = None if as_of else meta.get("regularMarketTime")

    return {
        "symbol": meta.get("symbol", symbol),
        "name": meta.get("longName") or meta.get("shortName"),
        "type": meta.get("instrumentType"),
        "currency": meta.get("currency"),
        "exchange": meta.get("fullExchangeName") or meta.get("exchangeName"),
        "price": r1(price, 4 if price < 10 else 2),
        "price_time_utc": datetime.fromtimestamp(market_time, tz=timezone.utc).isoformat() if market_time else last_date,
        "performance_pct": {
            "1_day": r1(ret(closes, 1)),
            "1_week": r1(ret(closes, 5 if not is_crypto else 7)),
            "1_month": r1(r1m),
            "3_months": r1(r3m),
            "6_months": r1(ret(closes, 6 * days_per_month)),
            "1_year": r1(ret(closes, days_per_year)),
        },
        "trend": {
            "sma20": r1(sma20, 2),
            "sma50": r1(sma50, 2),
            "sma200": r1(sma200, 2),
            "dist_sma50_pct": r1(dev50),
            "dist_sma200_pct": r1(dev200),
            "sma200_slope_1m_pct": r1(sma200_slope, 2),
            "stretch_sma50_in_monthly_vol": r1(stretch50, 2),
        },
        "momentum": {
            "rsi14": r1(rsi14),
            "rise_1m_in_sigma": r1(z1m, 2),
        },
        "range": {
            "high_52w": r1(hi_52, 2),
            "low_52w": r1(lo_52, 2),
            "dist_52w_high_pct": r1(dd_from_hi52),
            "dist_3m_high_pct": r1(dd_from_hi3m),
            "dist_10d_low_pct": r1(bounce_from_10d_low),
            "stabilized_5d": stabilizing,
        },
        "volatility": {
            "annualized_60d_pct": r1(vol_a * 100),
            "annualized_1y_pct": r1(vol_a_long * 100),
            "monthly_pct": r1(vol_m * 100),
            "regime_factor": r1(vol_regime, 2),
        },
        "next_earnings": earnings,
        "pre_assessment": {
            "score": score,
            "verdict": verdict,
            "overheated": overheated,
            "overheat_points": heat,
            "dip": dip,
            "uptrend": uptrend,
            "downtrend": downtrend,
            "signals": signals,
        },
        "last_30_closes": [r1(c, 4 if c < 10 else 2) for c in closes[-30:]],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("symbol", nargs="?", help="Yahoo Finance symbol, e.g. AAPL, SAP.DE, EUNL.DE, BTC-EUR")
    p.add_argument("--search", help="Search for a symbol by name")
    p.add_argument("--as-of", help="Historical analysis as of date YYYY-MM-DD (for testing the logic)")
    a = p.parse_args()
    try:
        if a.search:
            out = search(a.search)
        elif a.symbol:
            out = analyze(a.symbol, a.as_of)
        else:
            p.error("Specify a symbol or --search")
    except urllib.error.HTTPError as e:
        out = {"error": f"HTTP {e.code} from Yahoo Finance", "detail": str(e)}
    except urllib.error.URLError as e:
        out = {"error": "Network error", "detail": str(e.reason)}
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
