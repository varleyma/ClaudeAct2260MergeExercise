"""
CRIM cadastral REST enrichment.

Instead of driving the ArcGIS Web AppBuilder UI once per name (as
pr_cadastral_scraper.py does), this queries the underlying ArcGIS REST
FeatureServer directly, by CATASTRO number, in batches.

Service:  Parcelario/Parcelas/MapServer  layer 654 ("Parcelas")
Access:   the /server REST endpoint requires a token, but the site's own
          proxy (/proxy/proxy.ashx?<url>) injects it, so we go through the proxy.

Adds vs. the UI scrape:
  * INSIDE_X / INSIDE_Y  -> parcel centroid lon/lat (WGS84)
  * authoritative, de-duplicated current attributes for every parcel
  * fills sale/deed fields the name search failed to capture

NOTE: layer 654 has NO related tables / relationships, so CRIM holds exactly
one sale per parcel. This does not (and cannot) reconstruct a multi-event
transaction history -- that only exists in the Registro (Karibe), which is
login-gated.
"""

import time
import json
import argparse
import urllib.parse
import urllib.request
import glob
import os
import csv
from datetime import datetime, timezone

PROXY = "https://catastro.crimpr.net/proxy/proxy.ashx?"
LAYER = "https://catastro.crimpr.net/server/rest/services/Parcelario/Parcelas/MapServer/654/query"
REFERER = "https://catastro.crimpr.net/cdprpc/"

# Fields to request (everything except the heavy Shape geometry blob).
OUT_FIELDS = [
    "OLDPID", "NUM_CATASTRO", "TIPO", "CATASTRO", "MUNICIPIO", "CONTACT",
    "DIRECCION_FISICA", "DIRECCION_POSTAL", "CABIDA", "LAND", "STRUCTURE",
    "MACHINERY", "TOTALVAL", "EXEMP", "EXON", "TAXABLE", "DEEDBOOK",
    "DEEDPAGE", "ESTATE", "DEEDNUM", "SALESAMT", "SALESDTTM", "SELLERNAME",
    "BYERNAME", "INSIDE_X", "INSIDE_Y", "OBJECTID",
]

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.abspath(
    os.path.join(HERE, "..", "..", "data", "third_party", "crim_parcel_enriched.csv")
)


def load_unique_catastros():
    """Collect unique, non-empty CATASTRO values from the UI-scrape outputs."""
    seen = []
    seen_set = set()
    for f in sorted(glob.glob(os.path.join(HERE, "cadastral_results_*.csv"))):
        with open(f, newline="", encoding="utf-8") as fh:
            r = csv.DictReader(fh)
            for row in r:
                c = (row.get("catastro") or "").strip()
                if c and c not in seen_set:
                    seen_set.add(c)
                    seen.append(c)
    return seen


def esc(v):
    return "'" + v.replace("'", "''") + "'"


def query_chunk(catastros, retries=4):
    """Query CRIM REST for a list of CATASTRO values; return list of attribute dicts."""
    where = "CATASTRO IN (" + ",".join(esc(c) for c in catastros) + ")"
    params = {
        "where": where,
        "outFields": ",".join(OUT_FIELDS),
        "returnGeometry": "false",
        "f": "json",
    }
    # The batched IN-list makes a GET URL too long for the proxy (404), so POST:
    # target service URL stays in the query string, params go in the body.
    body = urllib.parse.urlencode(params).encode("utf-8")
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(PROXY + LAYER, data=body, method="POST", headers={
                "Referer": REFERER,
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": "Mozilla/5.0 (research; CRIM parcel enrichment)",
            })
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            if "error" in data:
                last_err = data["error"]
                time.sleep(2 * (attempt + 1))
                continue
            return [f["attributes"] for f in data.get("features", [])]
        except Exception as e:  # noqa
            last_err = str(e)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"chunk failed after {retries} tries: {last_err}")


def epoch_ms_to_date(v):
    if v in (None, ""):
        return ""
    try:
        return datetime.fromtimestamp(int(v) / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="only process first N unique catastros (0 = all)")
    ap.add_argument("--chunk", type=int, default=200, help="catastros per REST request")
    ap.add_argument("--sleep", type=float, default=0.4, help="seconds between requests")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    catastros = load_unique_catastros()
    if args.limit:
        catastros = catastros[: args.limit]
    total = len(catastros)
    print(f"unique catastros to query: {total}")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    found = {}
    n_chunks = (total + args.chunk - 1) // args.chunk
    for i in range(0, total, args.chunk):
        chunk = catastros[i : i + args.chunk]
        rows = query_chunk(chunk)
        for a in rows:
            a["SALESDATE"] = epoch_ms_to_date(a.get("SALESDTTM"))
            found[a["CATASTRO"]] = a
        ci = i // args.chunk + 1
        print(f"  chunk {ci}/{n_chunks}: requested {len(chunk)}, matched {len(rows)}, total matched {len(found)}")
        time.sleep(args.sleep)

    # Write output preserving the requested-catastro order.
    header = OUT_FIELDS + ["SALESDATE"]
    matched = 0
    with open(args.out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=header, extrasaction="ignore")
        w.writeheader()
        for c in catastros:
            if c in found:
                w.writerow(found[c])
                matched += 1

    unmatched = total - matched
    print(f"\nDONE. matched {matched}/{total} (unmatched {unmatched})")
    with_coords = sum(1 for a in found.values() if a.get("INSIDE_X") not in (None, ""))
    with_sale = sum(1 for a in found.values() if a.get("SALESDATE"))
    print(f"  with coordinates: {with_coords}")
    print(f"  with sale date:   {with_sale}")
    print(f"  output: {args.out}")


if __name__ == "__main__":
    main()
