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
