"""
Build a unique-match investor parcel dataset with census tracts.

Subsets crim_parcel_enriched.csv to is_unique_match == True and appends the
2020 census tract for each parcel centroid via the Census Bureau geocoder
(geographies/coordinates endpoint; Puerto Rico = state FIPS 72).

New columns:
    tract_geoid    11-digit GEOID (state + county + tract), e.g. 72127008602
    county_fips    3-digit county FIPS within PR
    county_name    county (municipio) name per Census
    tract_name     human-readable tract label, e.g. "Census Tract 86.02"

Output: data/cleaned/crim_parcels_uniquematch_tracts.csv
"""

import csv, json, os, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ENRICHED = os.path.join(ROOT, "data", "third_party", "crim_parcel_enriched.csv")
OUT = os.path.join(ROOT, "data", "cleaned", "crim_parcels_uniquematch_tracts.csv")

GEOCODER = "https://geocoding.geo.census.gov/geocoder/geographies/coordinates"


def tract_for(lon, lat, retries=4):
    params = {
        "x": lon, "y": lat,
        "benchmark": "Public_AR_Current",
        "vintage": "Current_Current",
        "layers": "Census Tracts,Counties",
        "format": "json",
    }
    url = GEOCODER + "?" + urllib.parse.urlencode(params)
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "research tract lookup"})
            with urllib.request.urlopen(req, timeout=30) as r:
                d = json.loads(r.read().decode("utf-8"))
            geos = d.get("result", {}).get("geographies", {})
            tracts = geos.get("Census Tracts") or []
            counties = geos.get("Counties") or []
            t = tracts[0] if tracts else {}
            c = counties[0] if counties else {}
            return {
                "tract_geoid": t.get("GEOID", ""),
                "county_fips": t.get("COUNTY", c.get("COUNTY", "")),
                "county_name": c.get("NAME", ""),
                "tract_name": t.get("NAME", ""),
            }
        except Exception as e:  # noqa
            last = str(e)
            time.sleep(1.5 * (attempt + 1))
    print(f"    [WARN] geocode failed ({lon},{lat}): {last}")
    return {"tract_geoid": "", "county_fips": "", "county_name": "", "tract_name": ""}


def main():
    with open(ENRICHED, newline="", encoding="utf-8") as fh:
        r = csv.DictReader(fh)
        fields = list(r.fieldnames)
        rows = [d for d in r if d.get("is_unique_match") == "True"]
    print(f"unique-match parcels: {len(rows)}")

    add = ["tract_geoid", "county_fips", "county_name", "tract_name"]
    cache = {}
    done = 0
    for d in rows:
        x, y = (d.get("INSIDE_X") or "").strip(), (d.get("INSIDE_Y") or "").strip()
        if not x or not y:
            for a in add:
                d[a] = ""
            continue
        key = (round(float(x), 6), round(float(y), 6))
        if key not in cache:
            cache[key] = tract_for(x, y)
            time.sleep(0.2)
        d.update(cache[key])
        done += 1
        if done % 100 == 0:
            print(f"  {done}/{len(rows)} geocoded ({len(cache)} unique points)")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields + add, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    with_tract = sum(1 for d in rows if d.get("tract_geoid"))
    print(f"\nDONE. rows: {len(rows)}  with tract: {with_tract}")
    n_tracts = len({d['tract_geoid'] for d in rows if d.get('tract_geoid')})
    print(f"  distinct tracts: {n_tracts}")
    print(f"  output: {OUT}")


if __name__ == "__main__":
    main()
