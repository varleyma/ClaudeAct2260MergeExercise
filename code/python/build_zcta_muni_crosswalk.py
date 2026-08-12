"""Dominant-municipio (county) crosswalk for PR ZCTAs.

Intersects the 132 PR ZCTA polygons with tracts72 (2020 TIGER tracts, whose
GEOID digits 1-5 give the county FIPS), assigns each ZCTA the municipio with
the largest overlap area, and records that municipio's area share so the
cleanliness of the mapping is visible (ZCTAs cross municipio lines).

Output: data/experian/pr_zcta_muni_crosswalk.csv
        (zip, muni_fips, muni_area_share, n_munis_overlapped)
"""
import os
import geopandas as gpd

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"

zcta = gpd.read_file(os.path.join(REPO, "data", "third_party", "zcta_pr")).to_crs(3857)
zcta = zcta[["ZCTA5CE20", "geometry"]].rename(columns={"ZCTA5CE20": "zip"})

tr = gpd.read_file(os.path.join(REPO, "data", "third_party", "tracts72")).to_crs(3857)
tr["muni_fips"] = tr["GEOID"].str[:5]
muni = tr.dissolve(by="muni_fips", as_index=False)[["muni_fips", "geometry"]]

ix = gpd.overlay(zcta, muni, how="intersection", keep_geom_type=True)
ix["area"] = ix.geometry.area
tot = ix.groupby("zip")["area"].transform("sum")
ix["share"] = ix["area"] / tot

dom = (ix.sort_values(["zip", "share"], ascending=[True, False])
       .groupby("zip")
       .agg(muni_fips=("muni_fips", "first"),
            muni_area_share=("share", "first"),
            n_munis_overlapped=("muni_fips", "size"))
       .reset_index())

out = os.path.join(REPO, "data", "experian", "pr_zcta_muni_crosswalk.csv")
dom.to_csv(out, index=False)
print(f"{len(dom)} ZCTAs mapped; dominant-share distribution:")
print(dom["muni_area_share"].describe().round(3).to_string())
print(f"share >= 0.8: {(dom['muni_area_share'] >= 0.8).sum()} | "
      f"0.5-0.8: {((dom['muni_area_share'] < 0.8) & (dom['muni_area_share'] >= 0.5)).sum()} | "
      f"< 0.5: {(dom['muni_area_share'] < 0.5).sum()}")
