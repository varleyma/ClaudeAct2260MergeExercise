"""
Add "is this a new property?"-proxy flags to the CRIM datasets.

CRIM publishes no construction year, so these are indirect signals:

    is_subunit            CATASTRO's last block != '000'  -> unit within a parent
                          parcel (condo / horizontal-property regime)
    oldpid_differs        OLDPID ('parcela de procedencia') differs from the
                          parcel's own number -> parcel was created by
                          segregation/re-parceling (enriched file only; the
                          nearby CSVs don't carry OLDPID)
    seller_is_corporate   SELLERNAME matches developer/corporate keywords ->
                          sale was likely a first sale from a developer
                          ("bought new" at SALESDATE). Keyword heuristic on
                          CRIM's truncated 20-char names; imperfect by design.
    vacant_land           STRUCTURE == 0 and LAND > 0 -> no assessed structure
                          today (vacant lot).

Idempotent: re-running refreshes the columns in place.

Usage:
    flag_property_age_signals.py <csv> [<csv> ...]
"""

import csv, os, re, sys

CORP_PAT = re.compile(
    r"\b(DEVELOP\w*|CONSTRUC\w*|BUILDER\w*|CORP\w*|LLC|INC|CO|COMPANY|"
    r"SOCIEDAD|S\.?E\.?|ASSOCIATES?|PARTNERS?|PROPERTIES|PROPERTY|REALTY|"
    r"INVESTMENT\w*|INVERSION\w*|HOLDINGS?|GROUP|GRUPO|HOMES?|HOM|VENTURES?|"
    r"ENTERPRISES?|TRUST|BANK|BANCO|COOPERATIVA|CRUV|AUTORIDAD|MUNICIPIO|ESTADO)\b"
)


def last_block(catastro):
    parts = (catastro or "").strip().split("-")
    return parts[-1] if len(parts) >= 5 else None


def flag_file(path):
    with open(path, newline="", encoding="utf-8") as fh:
        r = csv.DictReader(fh)
        fields = list(r.fieldnames)
        rows = list(r)

    has_oldpid = "OLDPID" in fields and "NUM_CATASTRO" in fields
    add = ["is_subunit", "seller_is_corporate", "vacant_land"] + (
        ["oldpid_differs"] if has_oldpid else []
    )
    out_fields = fields + [c for c in add if c not in fields]

    counts = dict.fromkeys(add, 0)
    for d in rows:
        lb = last_block(d.get("CATASTRO", ""))
        v = "True" if (lb is not None and lb != "000") else "False"
        d["is_subunit"] = v

        seller = (d.get("SELLERNAME") or "").upper()
        d["seller_is_corporate"] = "True" if (seller.strip() and CORP_PAT.search(seller)) else "False"

        def num(x):
            try:
                return float(x)
            except (TypeError, ValueError):
                return None
        s, l = num(d.get("STRUCTURE")), num(d.get("LAND"))
        d["vacant_land"] = "True" if (s == 0 and l is not None and l > 0) else "False"

        if has_oldpid:
            op = (d.get("OLDPID") or "").strip()
            np_ = (d.get("NUM_CATASTRO") or "").strip()
            d["oldpid_differs"] = "True" if (op and np_ and op != np_) else "False"

        for c in add:
            if d[c] == "True":
                counts[c] += 1

    tmp = path + ".tmp"
    with open(tmp, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=out_fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)

    print(f"annotated {os.path.basename(path)}  ({len(rows)} rows)")
    for c in add:
        print(f"  {c}: {counts[c]} ({100*counts[c]/max(len(rows),1):.1f}%)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: flag_property_age_signals.py <csv> [<csv> ...]")
    for p in sys.argv[1:]:
        flag_file(p)
