#!/usr/bin/env python3
"""Kursanalyse für die Kaufentscheidung "Kaufen / Nicht kaufen / Abwarten".

Holt Tageskurse von Yahoo Finance (kein API-Key nötig), berechnet technische
Kennzahlen und eine transparente, regelbasierte Vorbewertung. Gibt JSON aus.

Nutzung:
    python3 analyze.py AAPL
    python3 analyze.py BTC-EUR
    python3 analyze.py --search "iShares MSCI World"

Nur Python-Standardbibliothek.
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
    """Nächster Termin für Quartalszahlen (nur Aktien). Best effort: None bei Fehlern.

    Der quoteSummary-Endpunkt verlangt Cookie + Crumb, die wir uns ohne Login holen.
    """
    try:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        opener.addheaders = list(UA.items())
        try:
            opener.open("https://fc.yahoo.com", timeout=10)
        except urllib.error.HTTPError:
            pass  # liefert 404, setzt aber das Cookie
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
            "datum": d.date().isoformat(),
            "tage_bis": max(0, (d.date() - datetime.now(timezone.utc).date()).days),
            "geschaetzt": bool(ev.get("isEarningsDateEstimate")),
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
        raise SystemExit(json.dumps({"error": f"Keine Daten für {symbol}", "detail": err}))
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
    # Wilder-Glättung
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
        raise SystemExit(json.dumps({"error": f"Zu wenig Kurshistorie für {symbol} ({len(rows)} Tage)"}))

    closes = [r[1] for r in rows]
    highs = [r[2] for r in rows]
    lows = [r[3] for r in rows]
    price = closes[-1] if as_of else (meta.get("regularMarketPrice") or closes[-1])
    closes[-1] = price  # aktuellsten Kurs verwenden

    is_crypto = meta.get("instrumentType") == "CRYPTOCURRENCY"
    days_per_year = 365 if is_crypto else 252
    days_per_month = 30 if is_crypto else 21

    daily = [math.log(b / a) for a, b in zip(closes[:-1], closes[1:]) if a > 0 and b > 0]
    vol_d = statistics.pstdev(daily[-60:])          # tägliche Vola (60 Tage)
    vol_m = vol_d * math.sqrt(days_per_month)        # Monats-Vola
    vol_a = vol_d * math.sqrt(days_per_year)         # annualisiert
    vol_a_long = statistics.pstdev(daily[-days_per_year:]) * math.sqrt(days_per_year)

    sma20, sma50, sma200 = sma(closes, 20), sma(closes, 50), sma(closes, 200)
    sma200_prev = (sum(closes[-221:-21]) / 200) if len(closes) >= 221 else None
    sma200_slope = pct(sma200, sma200_prev)          # Veränderung SMA200 über ~1 Monat in %

    yr = days_per_year
    hi_52 = max(highs[-yr:])
    lo_52 = min(lows[-yr:])
    hi_3m = max(highs[-3 * days_per_month:])
    dd_from_hi52 = pct(price, hi_52)
    dd_from_hi3m = pct(price, hi_3m)

    dev50 = pct(price, sma50)
    dev200 = pct(price, sma200)
    # "Stretch": Abweichung vom SMA50 in Einheiten der Monatsvolatilität.
    # Macht Aktie, ETF und Krypto vergleichbar.
    stretch50 = (dev50 / 100) / vol_m if vol_m else None
    r1m = ret(closes, days_per_month)
    r3m = ret(closes, 3 * days_per_month)
    z1m = (math.log(1 + r1m / 100) / vol_m) if (r1m is not None and vol_m) else None

    rsi14 = rsi(closes[-250:], 14)
    low_10 = min(lows[-10:])
    low_5 = min(lows[-5:])
    bounce_from_10d_low = pct(price, low_10)
    # Stabilisierung: keine neuen Tiefs in den letzten 5 Tagen gegenüber den 5 Tagen davor
    prev_low = min(lows[-10:-5])
    stabilizing = low_5 >= prev_low

    # ---------------- Regelbasierte Vorbewertung ----------------
    signals = []  # (punkte, text)

    def add(points, text):
        signals.append({"punkte": points, "signal": text})

    uptrend = sma200 is not None and price > sma200 and (sma200_slope or 0) > 0
    downtrend = sma200 is not None and price < sma200 and (sma200_slope or 0) < 0

    if sma200 is None:
        add(0, "Weniger als 200 Tage Historie – langfristiger Trend nicht bestimmbar")
    elif uptrend:
        add(+1, "Langfristiger Aufwärtstrend (Kurs über steigendem SMA200)")
    elif downtrend:
        add(-2, "Langfristiger Abwärtstrend (Kurs unter fallendem SMA200)")
    else:
        add(0, "Langfristiger Trend unklar (Kurs und SMA200-Richtung widersprüchlich)")

    # Überhitzung (eigene Teilsumme: entscheidet über "NICHT KAUFEN")
    heat = 0
    if stretch50 is not None and stretch50 > 1.5:
        add(-2, f"Kurs stark über SMA50 gestreckt ({dev50:+.1f} %, {stretch50:.1f}x Monatsvola)")
        heat -= 2
    elif stretch50 is not None and stretch50 > 1.0:
        add(-1, f"Kurs deutlich über SMA50 ({dev50:+.1f} %)")
        heat -= 1
    if rsi14 is not None and rsi14 > 75:
        add(-2, f"RSI {rsi14:.0f} – stark überkauft")
        heat -= 2
    elif rsi14 is not None and rsi14 > 68:
        add(-1, f"RSI {rsi14:.0f} – überkauft")
        heat -= 1
    if z1m is not None and z1m > 2.0:
        add(-1, f"Ungewöhnlich steiler Anstieg im letzten Monat ({r1m:+.1f} %, {z1m:.1f} Sigma)")
        heat -= 1
    overheated = heat <= -2

    # Dip
    dip = False
    if stretch50 is not None and stretch50 < -1.0:
        dip = True
        if uptrend:
            add(+2, f"Rücksetzer unter SMA50 ({dev50:+.1f} %) innerhalb eines Aufwärtstrends")
        elif downtrend:
            add(-1, f"Kurs weit unter SMA50 ({dev50:+.1f} %) im Abwärtstrend – Gefahr 'fallendes Messer'")
        else:
            add(+1, f"Kurs deutlich unter SMA50 ({dev50:+.1f} %)")
    elif stretch50 is not None and -1.0 <= stretch50 < -0.3 and uptrend:
        dip = True
        add(+1, f"Rücksetzer im Aufwärtstrend ({dev50:+.1f} % zum SMA50)")
    if rsi14 is not None and rsi14 < 30:
        add(+1 if not downtrend else 0, f"RSI {rsi14:.0f} – überverkauft")
        dip = True
    elif rsi14 is not None and rsi14 < 40 and uptrend:
        add(+1, f"RSI {rsi14:.0f} – abgekühlt im Aufwärtstrend")

    if dip:
        if stabilizing and (bounce_from_10d_low or 0) > 1:
            add(+1, f"Stabilisierung: keine neuen Tiefs in 5 Tagen, {bounce_from_10d_low:+.1f} % über 10-Tage-Tief")
        else:
            add(-1, "Noch keine Stabilisierung – Kurs markiert weiter neue Tiefs")

    # Extreme Einbrüche (möglicherweise fundamentaler Grund)
    if dd_from_hi3m is not None and vol_m and (dd_from_hi3m / 100) / vol_m < -3:
        add(-1, f"Außergewöhnlich starker Einbruch vom 3-Monats-Hoch ({dd_from_hi3m:.1f} %) – Ursache prüfen")

    # Unsicherheit durch Volatilität
    vol_regime = vol_a / vol_a_long if vol_a_long else 1
    if vol_regime > 1.5:
        add(-1, f"Volatilität aktuell {vol_regime:.1f}x über dem Jahresschnitt – erhöhte Unsicherheit")

    # Ereignisrisiko: anstehende Quartalszahlen (nur Aktien, nur Live-Analyse)
    earnings = None
    if meta.get("instrumentType") == "EQUITY" and not as_of:
        earnings = fetch_earnings(meta.get("symbol", symbol))
        if earnings and earnings["tage_bis"] <= 14:
            add(-1, f"Quartalszahlen in {earnings['tage_bis']} Tagen ({earnings['datum']}) – Kurssprung in beide Richtungen möglich")

    score = sum(s["punkte"] for s in signals)
    # NICHT KAUFEN = überhitzt/vermutlich überbewertet.
    # KAUFEN      = Dip mit guter Erholungschance (kein Abwärtstrend).
    # ABWARTEN    = alles Unklare, inkl. fallender Märkte ohne Bodenbildung.
    if overheated:
        verdict = "NICHT KAUFEN"
    elif score >= 3 and dip and not downtrend:
        verdict = "KAUFEN"
    else:
        verdict = "ABWARTEN"

    last_date = datetime.fromtimestamp(rows[-1][0], tz=timezone.utc).date().isoformat()
    market_time = None if as_of else meta.get("regularMarketTime")

    return {
        "symbol": meta.get("symbol", symbol),
        "name": meta.get("longName") or meta.get("shortName"),
        "typ": meta.get("instrumentType"),
        "waehrung": meta.get("currency"),
        "boerse": meta.get("fullExchangeName") or meta.get("exchangeName"),
        "kurs": r1(price, 4 if price < 10 else 2),
        "kurszeit_utc": datetime.fromtimestamp(market_time, tz=timezone.utc).isoformat() if market_time else last_date,
        "performance_pct": {
            "1_tag": r1(ret(closes, 1)),
            "1_woche": r1(ret(closes, 5 if not is_crypto else 7)),
            "1_monat": r1(r1m),
            "3_monate": r1(r3m),
            "6_monate": r1(ret(closes, 6 * days_per_month)),
            "1_jahr": r1(ret(closes, days_per_year)),
        },
        "trend": {
            "sma20": r1(sma20, 2),
            "sma50": r1(sma50, 2),
            "sma200": r1(sma200, 2),
            "abstand_sma50_pct": r1(dev50),
            "abstand_sma200_pct": r1(dev200),
            "sma200_steigung_1m_pct": r1(sma200_slope, 2),
            "stretch_sma50_in_monatsvola": r1(stretch50, 2),
        },
        "momentum": {
            "rsi14": r1(rsi14),
            "anstieg_1m_in_sigma": r1(z1m, 2),
        },
        "spanne": {
            "hoch_52w": r1(hi_52, 2),
            "tief_52w": r1(lo_52, 2),
            "abstand_52w_hoch_pct": r1(dd_from_hi52),
            "abstand_3m_hoch_pct": r1(dd_from_hi3m),
            "abstand_10t_tief_pct": r1(bounce_from_10d_low),
            "stabilisiert_5t": stabilizing,
        },
        "volatilitaet": {
            "annualisiert_60t_pct": r1(vol_a * 100),
            "annualisiert_1j_pct": r1(vol_a_long * 100),
            "monatlich_pct": r1(vol_m * 100),
            "regime_faktor": r1(vol_regime, 2),
        },
        "naechste_quartalszahlen": earnings,
        "vorbewertung": {
            "score": score,
            "empfehlung": verdict,
            "ueberhitzt": overheated,
            "ueberhitzungs_punkte": heat,
            "dip": dip,
            "aufwaertstrend": uptrend,
            "abwaertstrend": downtrend,
            "signale": signals,
        },
        "letzte_30_schlusskurse": [r1(c, 4 if c < 10 else 2) for c in closes[-30:]],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("symbol", nargs="?", help="Yahoo-Finance-Symbol, z. B. AAPL, SAP.DE, EUNL.DE, BTC-EUR")
    p.add_argument("--search", help="Symbol über Namen suchen")
    p.add_argument("--as-of", help="Historische Analyse zum Datum YYYY-MM-DD (zum Testen der Logik)")
    a = p.parse_args()
    try:
        if a.search:
            out = search(a.search)
        elif a.symbol:
            out = analyze(a.symbol, a.as_of)
        else:
            p.error("Symbol oder --search angeben")
    except urllib.error.HTTPError as e:
        out = {"error": f"HTTP {e.code} von Yahoo Finance", "detail": str(e)}
    except urllib.error.URLError as e:
        out = {"error": "Netzwerkfehler", "detail": str(e.reason)}
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
