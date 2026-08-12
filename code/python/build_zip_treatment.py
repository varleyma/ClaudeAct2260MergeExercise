"""Zip-level treatment measure: investor-purchase events per ZCTA x year.

Mirrors the tract DiD (design2) treatment construction but at zip level:
spatially joins the 1,256 dated design1 events (lon/lat) to Census ZCTA
polygons for PR, then aggregates to zcta x year with the same dose framing
(first_event_year, n_events, 1-4 vs 5+ groups).

Requires: PR ZCTA polygons at data/third_party/zcta_pr/ (TIGER/cartographic).
Run after that shapefile is in place.

Outputs:
  data/experian/zip_treatment_events.csv   - event-level with joined zcta
  data/experian/zip_treatment.csv          - zcta-level treatment (design2 format + dose)
  data/experian/zip_treatment_zcta_compare.txt - spatial join vs legacy dominant-ZCTA col
"""
import os
import geopandas as gpd
import pandas as pd

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
EVENTS = os.path.join(REPO, "data", "design1", "design1_events.csv")
ZCTA_DIR = os.path.join(REPO, "data", "third_party", "zcta_pr")
OUT = os.path.join(REPO, "data", "experian")

ev = pd.read_csv(EVENTS, dtype={"zcta": "Int64"})
ev["event_year"] = pd.to_datetime(ev["event_date"]).dt.year

zcta = gpd.read_file(ZCTA_DIR).to_crs(4326)
zcol = [c for c in zcta.columns if c.upper().startswith(("ZCTA5", "GEOID"))][0]
zcta = zcta[[zcol, "geometry"]].rename(columns={zcol: "zcta5"})
# keep PR prefixes only in case the file is national
zcta = zcta[zcta["zcta5"].astype(str).str.startswith(("006", "007", "009"))]
print(f"ZCTA polygons (PR): {len(zcta)}")

g = gpd.GeoDataFrame(ev, geometry=gpd.points_from_xy(ev["lon"], ev["lat"]), crs=4326)
j = gpd.sjoin(g, zcta, how="left", predicate="within")
unmatched = j["zcta5"].isna()
if unmatched.any():
    # nearest-polygon fallback for coastal points just outside boundaries
    miss = j[unmatched].drop(columns=["zcta5", "index_right"], errors="ignore")
    near = gpd.sjoin_nearest(miss.to_crs(3857), zcta.to_crs(3857), how="left",
                             distance_col="dist_m")[["zcta5", "dist_m"]]
    j.loc[unmatched, "zcta5"] = near["zcta5"].values
    print(f"Nearest-fallback for {int(unmatched.sum())} events "
          f"(max dist {near['dist_m'].max():,.0f} m)")

evz = pd.DataFrame(j.drop(columns=["geometry", "index_right"], errors="ignore"))
evz.to_csv(os.path.join(OUT, "zip_treatment_events.csv"), index=False)

# legacy dominant-ZCTA column comparison
legacy = evz["zcta"].astype("Int64").astype(str).str.zfill(5)
agree = (legacy == evz["zcta5"].astype(str)).mean()

# treatment file, design2 format (decree-era events, >=2012, matching tract DiD)
dec = evz[evz["event_year"] >= 2012]
trt = (dec.groupby("zcta5")
       .agg(first_event_year=("event_year", "min"), n_events=("event_id", "count"))
       .reset_index().rename(columns={"zcta5": "zcta"}))
trt["dose_group"] = pd.cut(trt["n_events"], [0, 4, 10_000], labels=["1-4", "5+"])
trt.to_csv(os.path.join(OUT, "zip_treatment.csv"), index=False)

lines = [
    f"Events: {len(evz)} total, {len(dec)} decree-era (>=2012)",
    f"Treated ZCTAs (>=2012): {len(trt)}  (1-4: {(trt['dose_group']=='1-4').sum()}, "
    f"5+: {(trt['dose_group']=='5+').sum()})",
    f"Spatial-join ZCTA vs legacy dominant-ZCTA column agreement: {agree:.1%}",
    "",
    "Top 15 treated zips:",
    trt.sort_values("n_events", ascending=False).head(15).to_string(index=False),
]
with open(os.path.join(OUT, "zip_treatment_zcta_compare.txt"), "w") as f:
    f.write("\n".join(lines))
print("\n".join(lines))
