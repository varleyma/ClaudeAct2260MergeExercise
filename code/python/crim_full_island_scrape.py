"""
Island-wide CRIM parcel scrape.

Downloads EVERY parcel record from the CRIM Parcelas layer (attributes +
centroid, no polygon geometry) via keyset pagination on OBJECTID -- roughly
750 pages of 2,000 records. After this exists, nearby-sales datasets for ANY
radius/base are computed locally with build_rings_local.py; no more per-ring
scraping.

Checkpoint/resume: rows are appended to the output CSV as they arrive and a
small .state.json tracks the last OBJECTID; rerunning resumes automatically.
Idle system sleep is suppressed while running (auto-clears on exit).

Output (gitignored, ~500MB): data/third_party/crim_parcels_island.csv
"""

import csv, json, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from crim_rest_enrich import OUT_FIELDS, epoch_ms_to_date  # noqa: E402
from crim_nearby_sales import keep_awake                    # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
STATE = OUT + ".state.json"

PROXY = "https://catastro.crimpr.net/proxy/proxy.ashx?"
LAYER = "https://catastro.crimpr.net/server/rest/services/Parcelario/Parcelas/MapServer/654/query"
REFERER = "https://catastro.crimpr.net/cdprpc/"
PAGE = 2000
SLEEP = 0.3


def post(params, retries=5):
    body = urllib.parse.urlencode(params).encode("utf-8")
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(PROXY + LAYER, data=body, method="POST", headers={
                "Referer": REFERER,
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": "Mozilla/5.0 (research; island parcel scrape)",
            })
            with urllib.request.urlopen(req, timeout=120) as r:
                d = json.loads(r.read().decode("utf-8"))
            if "error" in d:
                last = d["error"]
                time.sleep(3 * (attempt + 1))
                continue
            return d
        except Exception as e:  # noqa
            last = str(e)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"query failed after {retries} tries: {last}")


def main():
    keep_awake()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    total = post({"where": "1=1", "returnCountOnly": "true", "f": "json"}).get("count", 0)
    print(f"total parcels on server: {total:,}")

    last_oid, rows_written = 0, 0
    if os.path.exists(STATE):
        with open(STATE) as fh:
            st = json.load(fh)
        last_oid, rows_written = st["last_oid"], st["rows"]
        print(f"[resume] from OBJECTID {last_oid} ({rows_written:,} rows already written)")

    header = OUT_FIELDS + ["SALESDATE"]
    mode = "a" if (rows_written and os.path.exists(OUT)) else "w"
    with open(OUT, mode, newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=header, extrasaction="ignore")
        if mode == "w":
            w.writeheader()
        t0 = time.time()
        while True:
            d = post({
                "where": f"OBJECTID>{last_oid}",
                "orderByFields": "OBJECTID ASC",
                "outFields": ",".join(OUT_FIELDS),
                "returnGeometry": "false",
                "resultRecordCount": str(PAGE),
                "f": "json",
            })
            feats = d.get("features", [])
            if not feats:
                break
            for f in feats:
                a = f["attributes"]
                a["SALESDATE"] = epoch_ms_to_date(a.get("SALESDTTM"))
                w.writerow(a)
            rows_written += len(feats)
            last_oid = max(f["attributes"]["OBJECTID"] for f in feats)
            fh.flush()
            with open(STATE, "w") as sf:
                json.dump({"last_oid": last_oid, "rows": rows_written}, sf)
            if rows_written % 50000 < PAGE:
                el = time.time() - t0
                pct = 100 * rows_written / max(total, 1)
                print(f"  {rows_written:,}/{total:,} ({pct:.1f}%) | last OID {last_oid} | {el/60:.0f} min elapsed")
            time.sleep(SLEEP)

    print(f"\nDONE. rows written: {rows_written:,} (server count {total:,})")
    print(f"  output: {OUT}")


if __name__ == "__main__":
    main()
