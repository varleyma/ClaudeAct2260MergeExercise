"""
Build the Karibe unique-match investor parcel base, enriched via CRIM REST.

Steps:
  1. Load Karibe search results (act 22 + 60). Per (act, searched name), count
     distinct fincas returned. Keep names with EXACTLY ONE finca (the Karibe
     analogue of the CRIM unique_name_match confidence flag).
  2. Validate the match: the searched last name must appear as a word in the
     titular string (guards against Karibe's partial-name false positives,
     e.g. "Ben Le" -> "Ben Legend").
  3. Extract the catastro number from desc_registral ("Número de Catastro: ...").
     Names whose single match has no catastro are dropped (can't geocode).
  4. Query CRIM REST for those catastros -> full parcel attributes + coordinates.
  5. Write data/third_party/karibe_parcels_uniquematch_enriched.csv with the
     same core structure as crim_parcel_enriched.csv (is_unique_match=True for
     all rows) plus karibe traceability columns.
"""

import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from crim_rest_enrich import query_chunk, epoch_ms_to_date, OUT_FIELDS  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KARIBE_FILES = [
    (os.path.join(ROOT, "webscraping", "KaribeSearch", "individuos22_karibe_search_results.csv"), "22"),
    (os.path.join(ROOT, "webscraping", "KaribeSearch", "individuos60_karibe_search_results.csv"), "60"),
]
OUT = os.path.join(ROOT, "data", "third_party", "karibe_parcels_uniquematch_enriched.csv")

CAT_PAT = re.compile(r"\b(\d{3}-\d{3}-\d{3}-\d{2}(?:-\d{3})?)\b")


def norm(s):
    return re.sub(r"\s+", " ", (s or "").strip()).upper()


def main():
    csv.field_size_limit(10_000_000)

    # -- 1. group Karibe matches per (act, name) --
    by_name = {}
    for path, act in KARIBE_FILES:
        with open(path, newline="", encoding="utf-8", errors="replace") as fh:
            for r in csv.DictReader(fh):
                key = (act, norm(r["search_first_name"]), norm(r["search_last_name"]))
                finca = (norm(r.get("demarcacion")), norm(r.get("num_finca")))
                by_name.setdefault(key, {}).setdefault(finca, r)

    total_names = len(by_name)
    unique = {k: list(v.values())[0] for k, v in by_name.items() if len(v) == 1}
    print(f"names with >=1 karibe match: {total_names}")
    print(f"names with exactly 1 finca:  {len(unique)}")

    # -- 2. titular surname validation + 3. catastro extraction --
    kept, no_cat, bad_titular = [], 0, 0
    for (act, fn, ln), r in unique.items():
        titular = norm(r.get("titular"))
        if not re.search(r"\b" + re.escape(ln) + r"\b", titular):
            bad_titular += 1
            continue
        m = CAT_PAT.search(r.get("desc_registral") or "")
        if not m:
            no_cat += 1
            continue
        kept.append({
            "act": act, "search_first_name": fn, "search_last_name": ln,
            "titular": r.get("titular", "").strip(),
            "demarcacion": r.get("demarcacion", "").strip(),
            "num_finca": r.get("num_finca", "").strip(),
            "karibe_catastro": m.group(1),
        })
    print(f"dropped (surname not in titular): {bad_titular}")
    print(f"dropped (no catastro in desc):    {no_cat}")
    print(f"kept for CRIM enrichment:         {len(kept)}")

    # -- 4. enrich via CRIM REST --
    cats = sorted({k["karibe_catastro"] for k in kept})
    found = {}
    for i in range(0, len(cats), 200):
        chunk = cats[i:i+200]
        for a in query_chunk(chunk):
            a["SALESDATE"] = epoch_ms_to_date(a.get("SALESDTTM"))
            found[a["CATASTRO"]] = a
        print(f"  enriched {min(i+200, len(cats))}/{len(cats)} -> matched {len(found)}")

    # -- 5. write --
    kar_cols = ["act", "search_first_name", "search_last_name", "titular",
                "demarcacion", "num_finca", "karibe_catastro"]
    header = OUT_FIELDS + ["SALESDATE", "n_names_matched", "is_unique_match"] + kar_cols
    n_rows = n_unresolved = 0
    seen = set()
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=header, extrasaction="ignore")
        w.writeheader()
        for k in kept:
            a = found.get(k["karibe_catastro"])
            if a is None:
                n_unresolved += 1
                continue
            if k["karibe_catastro"] in seen:   # two unique names -> same parcel: keep first
                continue
            seen.add(k["karibe_catastro"])
            row = dict(a)
            row["n_names_matched"] = 1
            row["is_unique_match"] = "True"
            row.update({c: k[c] for c in kar_cols})
            w.writerow(row)
            n_rows += 1

    print(f"\nDONE. rows written: {n_rows}  (unresolved in CRIM: {n_unresolved})")
    print(f"  output: {OUT}")


if __name__ == "__main__":
    main()
