# Business Rules & Logic — M&A Valuation Intelligence Platform

## Ingestion Load Type (FULL vs INCREMENTAL)

Each source in `control.etl_metadata` is marked `FULL` or `INCREMENTAL`:
- **FULL** sources re-copy from GitHub on every run, regardless of whether
  today's file already landed.
- **INCREMENTAL** sources only copy if today's dated Bronze folder doesn't
  already exist; if it does, the source is skipped for the rest of the
  day. Verified by flipping one source to `INCREMENTAL` and confirming a
  same-day rerun correctly skipped it while the other source (left
  `FULL`) copied as normal.

## Source File Scope Differences

- `multiples.json` excludes `other` / `other-*` sub-verticals at the
  source.
- `multiples-by-year.json` does not exclude them at the source — the
  Bronze-to-Silver transformation now explicitly excludes `other` /
  `other-*` from both source files before they reach Silver, so the two
  source populations stay consistent downstream.

## Minimum Sample Size

The source only publishes a cell (a given sub-vertical × EV-bracket ×
metric combination) if it's backed by at least 10 disclosed deals
(`min_cell_n = 10` in the source's own metadata). This is enforced
downstream as Data Quality Rule 4 (`deal_count >= 10`).

## Outlier / Range Rules

Per the source's own documented methodology (confirmed by direct
inspection, not assumed):
- `EV/EBITDA`: valid range 0.5 – 60.0
- `EV/Revenue`: valid range 0.05 – 25.0

Values outside these ranges are flagged by Data Quality Rule 6.

## EV Bracket Ordering

The five EV brackets do not sort correctly alphabetically (e.g.
`$100M–$500M` would sort before `$25M–$100M`). `silver_ev_bracket` carries
an explicit `bracket_order` (1–5) so Power BI and any ranking logic sort
by enterprise-value size, not by label text:

| Bracket | Order |
|---|---|
| `<$5M` | 1 |
| `$5M–$25M` | 2 |
| `$25M–$100M` | 3 |
| `$100M–$500M` | 4 |
| `>$500M` | 5 |

## Industry Grouping

The 46 source sub-verticals are classified into 7 `industry_group`
categories via keyword-matching rules implemented in the
Bronze-to-Silver transformation. A sub-vertical is checked against each
group's keyword list in order, and assigned to the first group where any
keyword appears as a substring of its name. A sub-vertical matching none
of the keyword lists falls into `Other`.

| Group | Keywords (substring match) |
|---|---|
| Technology | `saas`, `software`, `digital-media`, `gaming`, `ecommerce`, `-it`, `healthtech`, `it-services` |
| Healthcare | `health`, `medical`, `dental`, `pharmacy`, `therapy`, `veterinary`, `mental`, `surgery`, `hospice`, `laboratory` |
| Energy | `oil-gas`, `electrical-utility`, `energy` |
| Industrial | `aerospace`, `industrial`, `metal-fabrication`, `packaging`, `plastics`, `auto-parts`, `specialty-contractor`, `freight`, `trucking`, `wholesale-distribution`, `electronics` |
| Consumer | `apparel`, `consumer-products`, `food`, `beverage`, `restaurant`, `specialty-retail`, `auto-dealership` |
| Professional Services | `consulting`, `advertising-agency`, `radio-television` |
| Financial | `financial`, `bank`, `insurance` |

Group order matters: the groups are evaluated in the sequence above, and a
sub-vertical is assigned to the first matching group. This is relevant for
a sub-vertical whose name could plausibly match more than one list (for
example a `healthtech` sub-vertical matches under Technology's keyword
list before Healthcare is ever checked, since Technology is evaluated
first).

## Canonical Table Write Pattern (Staging → Merge)

The Bronze-to-Silver transformation writes to
`silver_valuation_multiple_staging`, never directly to the canonical
`silver_valuation_multiple` table. Only the Delta merge step touches the
canonical table. This separation exists because writing straight to the
canonical table with an overwrite would wipe the merge-accumulated history
on every re-run of the flattening step. Any Silver table with a
`_staging` suffix follows this same pattern.

## Idempotency (MERGE Business Key)

The Delta merge step upserts into `silver_valuation_multiple` on the
business key `sub_vertical + metric_type + ev_bracket + source_year`, with
an explicit `OR (...IS NULL AND ...IS NULL)` fallback per nullable key
column (same NULL-matching handling as Data Quality Rule 5). Verified via
`DESCRIBE HISTORY`: repeated same-day runs show
`numTargetRowsInserted = 0`, confirming no duplicate inserts on re-run.

## Ranking Percentile Convention

`gold_industry_ranking.percentile` is deliberately inverted:
`100 - percent_rank() * 100`, so the top-valued industry shows 100 rather
than 0. This matches how a business audience reads "94th percentile ≈
near the top," and lets a Power BI chart with the leader at the top sort
naturally on the raw percentile value.

## Year-over-Year Change

`gold_valuation_trend.yoy_change` is only computed where consecutive years
are exactly 1 year apart; it's left null across any multi-year gap in the
source data, since "year-over-year" only has meaning for adjacent years.

## Valuation Premium

`gold_ev_bracket_analysis.valuation_premium` = this EV bracket's median
EV/EBITDA multiple, expressed as a percentage difference against that same
industry's average median EV/EBITDA across all of its brackets.

---

## Dimension Reference Data: Silver, Not Gold

The Azure SQL dimension tables (`DimIndustry`, `DimEVBracket`) are sourced
from Silver's purpose-built reference tables (`silver_industry`,
`silver_ev_bracket`), not from scanning distinct values out of Gold. Two
reasons:

- **Gold is fact-shaped, not reference-shaped.** No Gold table is a clean,
  standalone master list — bracket and industry appear in Gold only as
  labels sitting next to measures. `silver_ev_bracket` carries attributes
  (`min_ev`, `max_ev`, `bracket_order`) that no Gold table has at all.
- **Completeness.** Building a dimension from `DISTINCT` values in Gold
  would only capture industries/brackets that happen to have a
  qualifying row somewhere in Gold after all upstream filtering — any
  sub-vertical that exists in the source classification but had no
  qualifying deals would silently vanish from the dimension. Sourcing
  from Silver's reference tables guarantees the dimension is always
  complete, independent of what Gold's filtering produced.

`DimYear` is the one exception — year only exists as a fact-grain
attribute, so there's no separate year reference table in Silver to draw
from; it's built from the distinct years present in Gold instead.

## SCD Type 2 — DimIndustry Change Detection

`DimIndustry` implements SCD Type 2 in two sequential SQL statements, not
a single `MERGE` — genuinely two separate actions, not one:

1. **Close out.** Any current row (`is_current = 1`) whose `industry_group`
   no longer matches the incoming `silver_industry` value has its
   `effective_to` set to the load date and `is_current` set to 0.
2. **Insert current.** A fresh row is inserted for anything with no
   current row matching both `sub_vertical` AND `industry_group` —
   which correctly covers two distinct cases in one condition: a
   brand-new `sub_vertical` that's never had a row, and a `sub_vertical`
   whose row was just closed out in step 1 because its classification
   changed.

On a first load, every `sub_vertical` is new, so only step 2 does
anything — step 1 correctly finds nothing to close, since there's no
existing current row yet to compare against.

## FactValuation Grain and Unpivot

`FactValuation`'s grain is one row per industry × EV bracket **or**
year × metric — `ev_bracket_key` and `year_key` are mutually exclusive
on any given row (see `docs/data-dictionary.md` for the full column
breakdown). This mirrors the same nullable-key pattern already used in
`silver_valuation_multiple` (`ev_bracket` / `source_year`), which exists
because the two upstream source files never share both dimensions on the
same record.

Each Gold table's wide columns (`median_ev_ebitda`, `median_ev_revenue`)
are unpivoted into separate rows during the load, one per metric, only
where that metric's value is non-null in the source row — a Gold row
with only an EBITDA value does not produce an empty Revenue row.

## Metrics Excluded from FactValuation

`yoy_change`, `rank`, `percentile`, and `valuation_premium` all exist in
their respective Gold tables but are deliberately not carried into
`FactValuation`. Per the star schema's minimal fact design, these are
report-time calculations — recomputed as Power BI DAX measures over the
fact table rather than stored, since they're derived values, not raw
facts.
