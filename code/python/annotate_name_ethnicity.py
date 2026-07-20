"""
Hispanic-name proxy for buyers and sellers (displacement analysis).

Classifies CRIM party names against the Census Bureau 2010 surnames file
(data/reference/Names_2010Census.csv, pcthispanic column). Because CRIM
names are truncated (~20 chars) and inconsistently ordered (surname-first
"SMITH WILLIAM MCVEY" vs given-first "WILLIAM MCVEY SMITH"), we score ALL
tokens of length >=3 against the surname dictionary and take the MAXIMUM
pcthispanic across matched tokens -- under the PR two-surname convention,
any strongly Hispanic name component is strong evidence.

Per name column <col> -> three new columns with prefix <p>:
    <p>_pcthispanic     max pcthispanic across dictionary-matched tokens
                        (kept raw so thresholds can be adjusted later)
    <p>_nonhispanic     "True"  if pcthispanic <= 20
                        "False" if pcthispanic >= 70   (i.e. Hispanic name)
                        ""      ambiguous (20,70), corporate, or unmatched
    <p>_nameclass       "nonhispanic" | "hispanic" | "ambiguous" |
                        "corporate" | "unmatched" | "missing"

Caveats (document in any write-up): proxy for NAME origin, not residency --
stateside Puerto Ricans / Hispanic mainlanders classify as "local"
(understates mainland buying); mixed-name couples follow whichever name
CRIM recorded; suppressed "(S)" dictionary values are skipped.

Applies to (idempotent, streaming; re-run refreshes columns):
    data/design1/design1_sale_event_pairs.csv   BYERNAME->buyer, SELLERNAME->seller
    data/design1/placebo_sale_event_pairs.csv   BYERNAME->buyer, SELLERNAME->seller
    data/design1/design1_events.csv             buyer->buyer
    data/design1/placebo_events.csv             buyer->buyer
"""

import csv, os, re

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
DICT = os.path.join(REPO, "data", "reference", "Names_2010Census.csv")
D1 = os.path.join(REPO, "data", "design1")

TARGETS = [
    (os.path.join(D1, "design1_sale_event_pairs.csv"), [("BYERNAME", "buyer"), ("SELLERNAME", "seller")]),
    (os.path.join(D1, "placebo_sale_event_pairs.csv"), [("BYERNAME", "buyer"), ("SELLERNAME", "seller")]),
    (os.path.join(D1, "design1_events.csv"), [("buyer", "buyer")]),
    (os.path.join(D1, "placebo_events.csv"), [("buyer", "buyer")]),
]

NONHISP_MAX = 20.0   # <=  -> non-Hispanic name
HISP_MIN = 70.0      # >=  -> Hispanic name

CORP_RE = re.compile(
    r"\b(DEVELOP\w*|CONSTRUC\w*|BUILDER\w*|CORP\w*|LLC|INC|CO|COMPANY|SOCIEDAD|"
    r"S\.?E\.?|ASSOCIATES?|PARTNERS?|PROPERTIES|PROPERTY|REALTY|INVESTMENT\w*|"
    r"INVERSION\w*|HOLDINGS?|GROUP|GRUPO|VENTURES?|ENTERPRISES?|"
    r"TRUST|BANK|BANCO|COOPERATIVA|CRUV|AUTORIDAD|MUNICIPIO|ESTADO)\b")

TOKEN_RE = re.compile(r"[A-ZÑ]{3,}")


def load_dict():
    d = {}
    with open(DICT, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            try:
                d[r["name"].strip().upper()] = float(r["pcthispanic"])
            except (ValueError, KeyError):
                continue   # "(S)" suppressed or malformed
    return d


def classify(name, pct_dict, cache):
    key = (name or "").strip().upper()
    if key in cache:
        return cache[key]
    if not key:
        res = ("", "", "missing")
    elif CORP_RE.search(key):
        res = ("", "", "corporate")
    else:
        pcts = [pct_dict[t] for t in TOKEN_RE.findall(key) if t in pct_dict]
        if not pcts:
            res = ("", "", "unmatched")
        else:
            mx = max(pcts)
            if mx <= NONHISP_MAX:
                res = (f"{mx:.2f}", "True", "nonhispanic")
            elif mx >= HISP_MIN:
                res = (f"{mx:.2f}", "False", "hispanic")
            else:
                res = (f"{mx:.2f}", "", "ambiguous")
    cache[key] = res
    return res


def annotate(path, cols, pct_dict):
    cache = {}
    tmp = path + ".tmp"
    counts = {}
    with open(path, newline="", encoding="utf-8") as fin:
        r = csv.DictReader(fin)
        add = []
        for _, p in cols:
            add += [f"{p}_pcthispanic", f"{p}_nonhispanic", f"{p}_nameclass"]
        out_fields = list(r.fieldnames) + [c for c in add if c not in r.fieldnames]
        with open(tmp, "w", newline="", encoding="utf-8") as fout:
            w = csv.DictWriter(fout, fieldnames=out_fields, extrasaction="ignore")
            w.writeheader()
            n = 0
            for row in r:
                for col, p in cols:
                    pct, flag, cls = classify(row.get(col, ""), pct_dict, cache)
                    row[f"{p}_pcthispanic"] = pct
                    row[f"{p}_nonhispanic"] = flag
                    row[f"{p}_nameclass"] = cls
                    counts[(p, cls)] = counts.get((p, cls), 0) + 1
                w.writerow(row)
                n += 1
    os.replace(tmp, path)
    print(f"{os.path.basename(path)}: {n} rows")
    for (p, cls), c in sorted(counts.items()):
        print(f"    {p}_{cls}: {c} ({100*c/n:.1f}%)")


def main():
    csv.field_size_limit(10_000_000)
    pct_dict = load_dict()
    print(f"surname dictionary: {len(pct_dict)} names with pcthispanic")
    for path, cols in TARGETS:
        if os.path.exists(path):
            annotate(path, cols, pct_dict)
        else:
            print(f"[skip] {path} not found")


if __name__ == "__main__":
    main()
