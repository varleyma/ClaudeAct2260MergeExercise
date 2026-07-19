"""
Flag investor-name -> property matches by uniqueness (a match-confidence proxy).

For each searched investor name, count how many distinct parcels (catastros) the
CRIM name-search returned. A name that returned exactly one parcel is a much more
confident match than a common name ("William Smith") that returned dozens.

Scope: counts are computed PER ACT LIST (22 vs 60 are separate investor
populations / separate search runs).

Outputs
-------
1. data/cleaned/cadastral_matches_flagged.csv   (match level -- one row per match)
   original columns + :
     act                  '22' | '60'  (from the source filename)
     n_matches_for_name   distinct catastros this searched name returned (within act)
     unique_name_match    True when n_matches_for_name == 1

2. data/third_party/crim_parcel_enriched.csv    (parcel level -- annotated in place)
   adds:
     n_names_matched      # of distinct investor names (across acts) that returned this parcel
     is_unique_match      True if ANY name that returned this parcel returned ONLY this parcel
"""

import csv, glob, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CLEANED = os.path.join(ROOT, "data", "cleaned")
ENRICHED = os.path.join(ROOT, "data", "third_party", "crim_parcel_enriched.csv")
OUT_MATCHES = os.path.join(CLEANED, "cadastral_matches_flagged.csv")


def norm(s):
    return re.sub(r"\s+", " ", (s or "").strip()).upper()


def act_of(path):
    b = os.path.basename(path)
    if "_22_" in b:
        return "22"
    if "_60_" in b:
        return "60"
    return "?"


def main():
    files = sorted(glob.glob(os.path.join(HERE, "cadastral_results_*.csv")))
    rows = []
    header = None
    for f in files:
        act = act_of(f)
        with open(f, newline="", encoding="utf-8") as fh:
            r = csv.DictReader(fh)
            if header is None:
                header = list(r.fieldnames)
            for d in r:
                d["act"] = act
                rows.append(d)
    print(f"read {len(rows)} match rows from {len(files)} files")

    # distinct catastros per (act, name)
    name_catastros = {}   # key -> set(catastro)
    for d in rows:
        key = (d["act"], norm(d["searched_first_name"]), norm(d["searched_last_name"]))
        c = (d.get("catastro") or "").strip()
        if c:
            name_catastros.setdefault(key, set()).add(c)

    name_n = {k: len(v) for k, v in name_catastros.items()}

    # annotate match rows
    for d in rows:
        key = (d["act"], norm(d["searched_first_name"]), norm(d["searched_last_name"]))
        n = name_n.get(key, 0)
        d["n_matches_for_name"] = n
        d["unique_name_match"] = "True" if n == 1 else "False"

    os.makedirs(CLEANED, exist_ok=True)
    out_header = header + ["act", "n_matches_for_name", "unique_name_match"]
    with open(OUT_MATCHES, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=out_header, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    n_unique_rows = sum(1 for d in rows if d["unique_name_match"] == "True")
    n_unique_names = sum(1 for v in name_n.values() if v == 1)
    print(f"wrote {OUT_MATCHES}")
    print(f"  match rows flagged unique: {n_unique_rows}/{len(rows)}")
    print(f"  searched names with a unique match: {n_unique_names}/{len(name_n)}")

    # ---- parcel-level annotation of the enriched file ----
    # For each catastro: which (act,name) keys matched it, and did any of those
    # names match ONLY this parcel (n==1)?
    parcel_names = {}          # catastro -> set of (act,first,last)
    parcel_is_unique = {}      # catastro -> bool
    for key, cats in name_catastros.items():
        unique_name = (len(cats) == 1)
        for c in cats:
            parcel_names.setdefault(c, set()).add(key)
            if unique_name:
                parcel_is_unique[c] = True

    if os.path.exists(ENRICHED):
        with open(ENRICHED, newline="", encoding="utf-8") as fh:
            r = csv.DictReader(fh)
            efields = list(r.fieldnames)
            erows = list(r)
        add = [c for c in ["n_names_matched", "is_unique_match"] if c not in efields]
        for d in erows:
            c = (d.get("CATASTRO") or "").strip()
            d["n_names_matched"] = len(parcel_names.get(c, ()))
            d["is_unique_match"] = "True" if parcel_is_unique.get(c) else "False"
        with open(ENRICHED, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=efields + add, extrasaction="ignore")
            w.writeheader()
            w.writerows(erows)
        n_pu = sum(1 for d in erows if d["is_unique_match"] == "True")
        print(f"annotated {ENRICHED}")
        print(f"  parcels flagged is_unique_match: {n_pu}/{len(erows)}")
    else:
        print(f"(enriched file not found at {ENRICHED}; skipped parcel annotation)")


if __name__ == "__main__":
    main()
