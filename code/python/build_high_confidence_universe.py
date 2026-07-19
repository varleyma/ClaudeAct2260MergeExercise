"""
Combine all high-confidence investor-parcel identifications into one dataset
with explicit confidence tiers.

Tiers (a parcel can carry several; the dataset keeps one row per parcel x name):
  crim_unique       name returned exactly 1 parcel in the CRIM name search
  karibe_unique     name returned exactly 1 finca in Karibe (surname-validated,
                    catastro resolved in CRIM)
  crim_validated    name had multiple CRIM matches, but this parcel passed
                    strict validation: full first+last name in buyer or owner
                    field AND sale date not >1yr before decree approval, AND
                    the name validated to at most MAX_VALIDATED parcels

Output: data/cleaned/investor_parcels_high_confidence.csv
  one row per (name, parcel, tier) with parcel attributes joined from the
  respective enriched file.
"""

import csv, os, re
from datetime import datetime

MAX_VALIDATED = 5

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ENR_CRIM = os.path.join(ROOT, "data", "third_party", "crim_parcel_enriched.csv")
ENR_KAR = os.path.join(ROOT, "data", "third_party", "karibe_parcels_uniquematch_enriched.csv")
MATCHES = os.path.join(ROOT, "data", "cleaned", "cadastral_matches_flagged.csv")
NAMES = [(os.path.join(ROOT, "data", "raw", "names_individuos22.csv"), "22"),
         (os.path.join(ROOT, "data", "raw", "names_individuos60.csv"), "60")]
OUT = os.path.join(ROOT, "data", "cleaned", "investor_parcels_high_confidence.csv")

ATTRS = ["MUNICIPIO", "CONTACT", "DIRECCION_FISICA", "CABIDA", "LAND", "STRUCTURE",
         "TOTALVAL", "SALESAMT", "SALESDATE", "SELLERNAME", "BYERNAME",
         "INSIDE_X", "INSIDE_Y"]


def norm(s):
    return re.sub(r"\s+", " ", (s or "").strip()).upper()


def wb(needle, hay):
    return re.search(r"\b" + re.escape(needle) + r"\b", hay) is not None


def parse_sale(s):
    for fmt in ("%b %d, %Y", "%B %d, %Y"):
        try:
            return datetime.strptime(s.strip(), fmt)
        except ValueError:
            pass
    return None


def main():
    csv.field_size_limit(10_000_000)

    appr = {}
    for f, act in NAMES:
        for r in csv.DictReader(open(f, encoding="utf-8", errors="replace")):
            k = (act, norm(r["first_name"]), norm(r["last_name"]))
            try:
                d = datetime.strptime(r["approval_date"].strip(), "%m/%d/%Y")
            except ValueError:
                continue
            if k not in appr or d < appr[k]:
                appr[k] = d

    enr_crim = {r["CATASTRO"].strip(): r for r in csv.DictReader(open(ENR_CRIM, encoding="utf-8"))}
    enr_kar = {r["CATASTRO"].strip(): r for r in csv.DictReader(open(ENR_KAR, encoding="utf-8"))}

    out_rows = []

    def emit(act, fn, ln, catastro, tier, n_validated, src):
        a = src.get(catastro)
        row = {"act": act, "first_name": fn, "last_name": ln, "CATASTRO": catastro,
               "tier": tier, "n_validated_parcels_for_name": n_validated,
               "approval_date": appr.get((act, fn, ln), ""),
               }
        if isinstance(row["approval_date"], datetime):
            row["approval_date"] = row["approval_date"].strftime("%Y-%m-%d")
        for c in ATTRS:
            row[c] = (a or {}).get(c, "")
        out_rows.append(row)

    # --- tier: crim_unique + crim_validated ---
    matches = list(csv.DictReader(open(MATCHES, encoding="utf-8")))
    validated = {}
    for r in matches:
        k = (r["act"], norm(r["searched_first_name"]), norm(r["searched_last_name"]))
        if r["unique_name_match"] == "True":
            validated.setdefault(k, {"tier": "crim_unique", "cats": set()})["cats"].add(r["catastro"])
            continue
        fn, ln = k[1], k[2]
        buyer, owner = norm(r.get("comprador")), norm(r.get("dueño"))
        fb = wb(fn, buyer) and wb(ln, buyer)
        fo = wb(fn, owner) and wb(ln, owner)
        if not (fb or fo):
            continue
        a, s = appr.get(k), parse_sale(r.get("fecha_de_venta") or "")
        if s and a and (s - a).days < -365:
            continue
        if not s and not fo:
            continue
        validated.setdefault(k, {"tier": "crim_validated", "cats": set()})["cats"].add(r["catastro"])

    for k, v in validated.items():
        n = len(v["cats"])
        if v["tier"] == "crim_validated" and n > MAX_VALIDATED:
            continue
        for c in sorted(v["cats"]):
            emit(k[0], k[1], k[2], c, v["tier"], n, enr_crim)

    # --- tier: karibe_unique ---
    for r in enr_kar.values():
        emit(r["act"], norm(r["search_first_name"]), norm(r["search_last_name"]),
             r["CATASTRO"].strip(), "karibe_unique", 1, enr_kar)

    header = ["act", "first_name", "last_name", "approval_date", "CATASTRO", "tier",
              "n_validated_parcels_for_name"] + ATTRS
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=header, extrasaction="ignore")
        w.writeheader()
        w.writerows(out_rows)

    names = {(r["act"], r["first_name"], r["last_name"]) for r in out_rows}
    names_pooled = {(r["first_name"], r["last_name"]) for r in out_rows}
    parcels = {r["CATASTRO"] for r in out_rows}
    from collections import Counter
    tiers = Counter(r["tier"] for r in out_rows)
    print(f"rows: {len(out_rows)}  parcels: {len(parcels)}  names (pooled): {len(names_pooled)}")
    print("tier rows:", dict(tiers))
    print(f"output: {OUT}")


if __name__ == "__main__":
    main()
