/*==============================================================================
 crim_entity_figs.do

 Two exhibits bounding institutional ("hedge fund") presence in CRIM:
   figE1_entity_share      entity buyers' share of purchases by year
   figE2_cluster_share     purchases by entities at multi-entity mailing
                           addresses (one-LLC-per-property signature),
                           banks/coops excluded, as share of all purchases

 Input: output/crim_entities/entity_fig_year.csv (>$10k sales, 2000-2026;
 2026 partial). Last-sale-only snapshot: resold purchases are overwritten,
 which if anything OVERSTATES early-year entity shares (entities hold
 longer), so the rise is a lower bound.
==============================================================================*/

version 17
clear all
set more off

global OUT "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise/output/crim_entities"

import delimited "$OUT/entity_fig_year.csv", varnames(1) clear
gen sh_core  = 100 * n_core  / n_total
gen sh_broad = 100 * n_broad / n_total
gen sh_c2    = 100 * n_clust2 / n_total
gen sh_c3    = 100 * n_clust3 / n_total
sort year

local STYLE graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal)) yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(2012, lcolor(gs11) lpattern(dash)) ///
    xline(2019.5, lcolor(gs11) lpattern(dot)) ///
    xlabel(2000(5)2025)

twoway ///
    (connected sh_broad year, color(gs10) msymbol(Oh) lwidth(medthin)) ///
    (connected sh_core year, color(navy) msymbol(O) lwidth(medthin)) ///
    , `STYLE' ///
    legend(order(2 "LLC / Corp / LP / Ltd (strict)" 1 "Any entity form (broad)") ///
           rows(1) position(6) region(lstyle(none))) ///
    title("Legal-entity buyers' share of property purchases", size(medium)) ///
    ytitle("Share of purchases (%)") xtitle("Year of purchase") ///
    note("Share of CRIM-recorded sales >$10,000 with a corporate-form buyer name; dashed line = Act 22/60 (2012), dotted = post-2019 boom." ///
         "Last-sale-only snapshot: resold purchases are overwritten. Entities plausibly hold longer than households, which would" ///
         "overstate EARLY-year entity shares -- the rise is if anything understated. 2026 is a partial year.", size(vsmall)) ///
    name(figE1, replace)
graph export "$OUT/figE1_entity_share.png", replace width(2000)

gen sh_p10 = 100 * n_port10 / n_total
gen sh_p25 = 100 * n_port25 / n_total

twoway ///
    (connected sh_p10 year, color(navy) msymbol(O) lwidth(medthin)) ///
    (connected sh_p25 year, color(cranberry) msymbol(O) lwidth(medthin)) ///
    , `STYLE' ///
    legend(order(1 "Cluster holds 10+ properties" 2 "Cluster holds 25+ properties") ///
           rows(1) position(6) region(lstyle(none))) ///
    title("Purchases by portfolio-scale entity buyers", size(medium)) ///
    ytitle("Share of all purchases (%)") xtitle("Year of purchase") ///
    note("A purchase counts if its non-bank entity buyer belongs to a portfolio cluster: the same buyer NAME holds 10+ (25+)" ///
         "parcels, or its owner mailing ADDRESS accumulates 10+ (25+) parcels across distinct entity names (rolling up" ///
         "one-LLC-per-property structures). Banks, coops, and GSEs excluded (foreclosure REO). This is an upper bound on" ///
         "institutional-scale buying: the clusters include local developers, landlords, and law-office-administered LLCs." ///
         "Dashed line = Act 22/60 (2012), dotted = post-2019 boom. 2026 is a partial year.", size(vsmall)) ///
    name(figE2, replace)
graph export "$OUT/figE2_portfolio_share.png", replace width(2000)

di as result "Saved figE1_entity_share.png, figE2_portfolio_share.png"
