# The Local Housing-Market Effects of Act 22/60 Investor Purchases

*Dataset and empirical design summary — 2026-07-18*

## 1. Research question

When a tax-incentivized migrant (an Act 22/60 "Individual Investor" decree holder)
buys a residential property in Puerto Rico, what happens to the housing market
immediately around that property — prices, and who transacts?

## 2. Data construction

### 2.1 Identifying investor properties

- **Decree holders.** Government lists of individual grantees: 3,181 (Act 22) +
  2,672 (Act 60) names; 5,770 distinct first–last pairs pooled.
- **CRIM cadastral registry.** Name searches against the CRIM parcel layer
  (queried via its ArcGIS REST service) matched 26,673 unique parcels, each with
  full attributes, centroid coordinates, and the parcel's **most recent sale**
  (price, date, buyer, seller). CRIM stores only the latest transaction per parcel.
- **Karibe property registry.** Registry name-search results; cadastral numbers
  extracted from registral descriptions and resolved in CRIM added a second,
  largely non-overlapping source of investor parcels.
- **Match confidence.** Name→parcel matching is noisy for common names. A name
  that returned **exactly one** property is treated as high-confidence
  ("unique match"): 810 parcels via CRIM, 755 via Karibe (surname-validated,
  geocoded), union **1,306 parcels** (259 cross-validated in both sources).
  The event studies below use this unique-match base.
- **Coverage caveat.** High-confidence identification covers ~22.5% of searched
  names (26.7% including a validated multi-match recovery tier), versus 49–61%
  declared homeownership in the Act 22 annual reports. The gap is dominated by
  LLC/trust purchases (invisible to name search), name-format failures, and
  registry data availability. The identified sample therefore skews toward
  single-property, personal-name buyers — likely conservative for effects driven
  by the wealthiest (entity-buying) investors.

### 2.2 Events

An **event** is a dated investor purchase: unique-match parcels with a valid
CRIM sale date, collapsing same-day/same-location purchases (condo units bought
together) into one event → **1,256 events** (1,200 in the decree era, ≥2012,
used in estimation). Investor purchases cluster heavily: the median event has
**25 other events within 1 km** (only 158 are fully isolated), so contamination
is measured per event (`n_other_events_within_1000m`) and used in robustness.

### 2.3 Outcomes: nearby sales

For each event, every CRIM parcel within 1,000 m with a recorded sale:
**3.47M sale×event pairs** over 328K distinct parcels. Each pair carries
distance, ring, event time (months), sale price/date/parties, property
characteristics (lot size, assessed structure value, condo-unit and vacant-land
flags), and 2020 census tract (validated against the Census geocoder).
**Rings:** 0–250 m = treated, 250–400 m = buffer (dropped), 400–1,000 m = control.
**Filters:** nominal transfers (<$10k), implausible dates, and sales of
investor-matched parcels are excluded from outcome samples.
**Key data caveat:** CRIM keeps only each parcel's last sale, so earlier sales
are censored by later resales; the design's within-window, near-vs-far
comparisons mitigate but do not eliminate this (tested directly, fig. 5).

### 2.4 Placebo events

1,500 purchases by **non-corporate individual buyers** in the investor price
band ($285K–$3.9M = p25–p95 of investor purchases), located within 250 m of a
real event site (where the sales pool has full coverage) but **more than 3
years apart in time** from it. Far rings are truncated at 750 m for both the
placebo run and a matched real-event baseline, so the two are directly comparable.

### 2.5 Buyer/seller origin proxy

Party names are classified against the **Census 2010 surnames file**
(`pcthispanic`), taking the maximum across name tokens (robust to CRIM's
inconsistent name ordering; appropriate under the two-surname convention).
Names with `pcthispanic ≤ 20` are "non-Hispanic-named" (mainland proxy),
`≥ 70` "Hispanic-named" (local proxy); corporate, ambiguous, and unmatched
names are left unclassified. The raw `pcthispanic` is stored for re-thresholding.
**Validity:** 67% of investor purchases have non-Hispanic-named buyers vs. 10%
of surrounding market sales. **Caveat:** this proxies *name* origin — stateside
Puerto Ricans and other Hispanic-named mainlanders classify as "local," so
mainland penetration and displacement effects are understated (conservative).

## 3. Empirical design

**Stacked ring event study.** Because each parcel contributes one (its last)
sale, sales are aggregated into an **event × ring × period panel**: the outcome
is the mean log sale price among a cell's transactions in a period; the near
cell of each event "adopts treatment" in the event period (absorbing), far
cells never do and serve as never-treated controls. Identification: absent the
investor purchase, prices of homes selling 0–250 m away would have trended like
homes 400–1,000 m away — a within-micro-neighborhood parallel-trends assumption
that differences out tract-level shocks (Hurricane María, the 2020–21 migration
wave) by construction.

**Estimators.** Local-projections DiD (`lpdid`, Dube–Girardi–Jordà–Taylor) and
Callaway–Sant'Anna (`csdid`/`csdid2`, with a Wooldridge–Mundlak `jwdid`
cross-check); ±2-year windows; quarterly, half-yearly, and annual aggregation.
Tract fixed effects enter by residualizing sale-level log prices on tract
dummies before aggregation. The robustness suite runs annually with lpdid
(pre-window 4, post-window 3 years).

**Headline finding so far** (from the baseline runs): sale prices in the near
ring rise after the investor purchase relative to the far ring — a "near-ring
price bump" that is similar across quarterly and annual resolutions, across
estimators, and identical with and without tract fixed effects. Pre-trends look
clean at quarterly and annual resolution (a half-year anomaly is consistent
with the low power and binning mechanics of that aggregation).

## 4. The eight figures

**Fig 1 — Baseline event study** (`fig1_baseline`). Near-ring vs far-ring log
price coefficients by year relative to purchase. *What it shows:* the headline
price bump; flat pre-period coefficients are the design's core credibility
check, and the post-period path shows how quickly the premium appears and
whether it grows or fades.

**Fig 2 — Investor vs placebo purchases** (`fig2_real_vs_placebo`). The real
event study overlaid with the placebo (non-investor luxury purchases, matched
rings). *What it shows:* whether the bump is specific to decree investors. A
flat placebo series says nearby prices respond to *the investor*, not to any
high-value transaction (anchoring/comps mechanics); a placebo bump would imply
a generic luxury-sale effect — with the caveat that unmatched investors
contaminate the placebo toward finding an effect, making a null conservative.

**Fig 3 — Spatial gradient** (`fig3_gradient`). Near ring (0–250 m) and gap
ring (250–400 m) series, each against the same far control. *What it shows:*
whether the effect decays with distance. A genuine hyper-local spillover should
be strongest in the near ring, intermediate in the gap ring, and (by
assumption) zero in the far ring; near ≈ gap would instead suggest a
neighborhood-wide shock the far ring happens to share less of.

**Fig 4 — Dose response** (`fig4_dose`). Separate event studies for events with
0–2, 3–25, and >25 other investor events within 1 km. *What it shows:* the
per-event effect by treatment density. Larger effects for isolated events (where
one purchase is the full "dose") and attenuated effects in saturated areas is
the pattern a causal per-event effect predicts; it also bounds how much the
full-sample estimate is diluted by overlapping treatments.

**Fig 5 — Censoring robustness** (`fig5_late`). Baseline overlaid with events
from 2018 onward. *What it shows:* whether CRIM's last-sale-only censoring
drives the result. Late events leave little time for post-period sales to be
overwritten by resales; if their event study matches the full sample, the
censoring mechanics are not manufacturing the bump.

**Fig 6 — Composition checks** (`fig6_comp_*`, four panels). The identical
event study with property *characteristics* as outcomes: log assessed structure
value, log lot size, condo-unit share, vacant-land share. *What it shows:*
whether the price bump reflects a change in *what sells* rather than
appreciation. Flat lines mean the bump is a price effect on a stable mix;
significant movements (e.g., rising structure values) would indicate the
stock-upgrading margin of gentrification — a finding in itself, but one that
changes the interpretation of fig 1.

**Fig 7 — Who transacts: buyers vs sellers** (`fig7_parties`). Effect on the
share of nearby sales with non-Hispanic-named buyers, overlaid with the same
for sellers. *What it shows:* the migration margin. Buyer share rising faster
than seller share means the area is *net-importing* mainland owners after an
investor arrives — the composition shift that price indices cannot see.

**Fig 8 — Transition types** (`fig8_transitions`). Effects on the share of
transactions that are Hispanic-seller→non-Hispanic-buyer versus
non-Hispanic-seller→non-Hispanic-buyer. *What it shows:* the displacement
question directly. Rising islander→mainlander transitions indicate turnover of
locally-held housing to incomers (displacement margin); rising
mainlander→mainlander indicates churn within an already-converted segment
(sorting without further displacement). The two series distinguish "investors
lead conversion of local housing" from "investors cluster where conversion
already happened."

## 5. Standing caveats

1. **Last-sale censoring** (CRIM): pre-period sales are survivors; addressed by
   design and fig 5, but worth stating in any write-up.
2. **Selection into location**: investors choose appreciating micro-areas;
   estimates are spillovers *conditional on* site choice. Pre-trends and timing
   variation are the defense; effects should not be read as "the effect of the
   Act."
3. **Match selection**: identified investors skew single-property,
   personal-name buyers; entity purchases are missing.
4. **Name proxy**: understates mainland presence (Hispanic-named mainlanders
   count as local); corporate/ambiguous names excluded from shares.
5. **Assessed values** (structure/lot controls) are on CRIM's 1957 basis —
   valid as cross-sectional controls and composition outcomes, never as market
   values.

## 6. Reproducibility

Pipeline (all in `code/`): CRIM/Karibe scrapes and universe construction
(`crim_rest_enrich.py`, `build_karibe_uniquematch_base.py`,
`build_high_confidence_universe.py`), event-panel builds
(`build_design1_event_panel.py`, `build_placebo_event_panel.py`), name proxy
(`annotate_name_ethnicity.py`); estimation
(`design1_eventstudy_lpdid_csdid.do` for the baseline;
`design1_robustness_results.do` → `output/design1/robustness_coefs.dta` →
`design1_robustness_plots.do` for figures 1–8). Large pairs files are
gitignored and regenerable from the scripts.
