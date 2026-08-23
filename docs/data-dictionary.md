# Data Dictionary — M&A Valuation Intelligence Platform

## Bronze Layer

Raw, unmodified source JSON, partitioned by ingestion date.

```
raw/ma_multiples/ingestion_date=YYYY-MM-DD/multiples.json
raw/ma_multiples/ingestion_date=YYYY-MM-DD/multiples-by-year.json
```

### `multiples.json`
Nested structure: `data.<sub_vertical>.<ev_bracket>.<metric_type>.{n,p25,p50,p75}`.
- 46 sub-verticals, no year dimension.
- Metadata fields: `generated_at`, `license`, `methodology`,
  `min_cell_n=10`, `schema_version`, `source_window`.
- Excludes `other` / `other-*` sub-verticals at the source.

### `multiples-by-year.json`
Nested structure: `data.<sub_vertical>.<year>.{ev_ebitda?, ev_revenue?,
median_deal_value_m, n_deals}`.
- No ev_bracket dimension.
- Metadata fields: `generated_at`, `min_n_per_cell`, `schema_version`,
  `source`, `year_range` (array).
- Does not exclude `other` / `other-*` at the source (excluded during
  transformation into Silver — see Business Rules).

---

## Silver Layer

### `silver_valuation_multiple_staging`
Raw flattened union of both source files, before validation. Not queried
downstream directly.

### `silver_valuation_multiple` (canonical)
Unified fact table, populated only via a `MERGE` from validated staging
records (see `docs/business-rules.md`).

| Column | Description |
|---|---|
| `valuation_id` | Surrogate/business key |
| `sub_vertical` | Industry / sub-vertical |
| `ev_bracket` | Enterprise-value bracket **key** (e.g. `under_5m_ev`, `5m_25m_ev`, `25m_100m_ev`, `100m_500m_ev`, `over_500m_ev`) — not the display label. Null for rows sourced from `multiples-by-year.json` |
| `metric_type` | EV/EBITDA or EV/Revenue |
| `p25` | 25th percentile |
| `median_multiple` | Median |
| `p75` | 75th percentile |
| `deal_count` | Number of deals |
| `source_year` | Applicable year. Null for rows sourced from `multiples.json` |
| `ingestion_date` | Load date |
| `source_file` | Discriminator: `ma_multiples` or `ma_multiples_by_year` |

`ev_bracket` and `source_year` are nullable by design — each row
originates from exactly one of the two source files, and the dedup/merge
business key accounts for this.

### `silver_valuation_multiple_validated`
Row-level table carrying the staging data plus per-rule pass/fail flags
and an overall `is_valid` column. Filtered to `is_valid = True` records
feed the merge into the canonical table.

### `silver_industry`

| Column | Description |
|---|---|
| `industry_id` | Surrogate key |
| `sub_vertical` | One of the 46 source sub-verticals |
| `industry_group` | Derived enrichment dimension (7 categories — see Business Rules) |
| `industry_status` | Defaults to `Active` |

### `silver_ev_bracket`

| Column | Description |
|---|---|
| `ev_bracket_id` | Surrogate key |
| `ev_bracket` | Bracket key (e.g. `under_5m_ev`) — matches `silver_valuation_multiple.ev_bracket` for joins |
| `ev_bracket_label` | Human-readable display label (e.g. `<$5M`) — used for Power BI axis/legend text, not for joins |
| `min_ev` / `max_ev` | Numeric range bounds |
| `bracket_order` | 1–5, used to force correct (non-alphabetical) sort order in Power BI |

---

## Gold Layer

### `gold_industry_valuation` (140 rows)
Bracket-based benchmark. Wide format — EBITDA/Revenue as sibling columns.

| Column | Description |
|---|---|
| `sub_vertical` | Industry |
| `ev_bracket` | EV range |
| `median_ev_ebitda` / `median_ev_revenue` | Median multiples |
| `p25_ev_ebitda` / `p75_ev_ebitda` | Percentile bounds |
| `deal_count` | Prefers EBITDA's count, falls back to Revenue's |

### `gold_valuation_trend` (139 rows)
Year-based, wide format.

| Column | Description |
|---|---|
| `year` | Source year |
| `sub_vertical` | Industry |
| `median_ev_ebitda` / `median_ev_revenue` | Median multiples |
| `deal_count` | Number of deals |
| `yoy_change` | Only computed across exact 1-year gaps; null across multi-year gaps |

### `gold_industry_ranking` (59 rows)
Per-year ranking on `median_ev_ebitda`.

| Column | Description |
|---|---|
| `year` | Source year |
| `industry` | Industry |
| `median_ev_ebitda` | Median multiple |
| `rank` | Rank within year |
| `percentile` | Inverted — `100 - percent_rank()*100`, so the top industry shows 100 |
| `deal_count` | Number of deals |

### `gold_ev_bracket_analysis` (140 rows)

| Column | Description |
|---|---|
| `ev_bracket` | EV range |
| `sub_vertical` | Industry |
| `median_ev_ebitda` / `median_ev_revenue` | Median multiples |
| `deal_count` | Number of deals |
| `valuation_premium` | This bracket's median EBITDA multiple vs. that industry's average median across all its brackets, as a percentage |

### `gold_data_quality`
Append-only run history table — see `docs/data-quality.md` for schema and
rules.

---

## Serving Layer — Azure SQL Star Schema

Loaded from Gold/Silver into `ma-valuation-db` by three ADF pipelines —
see `docs/pipeline-design.md`. Sourced entirely from Silver's reference
tables (for dimension attributes) and Gold (for fact data); see
`docs/business-rules.md` for why Silver, not Gold, is the source for
dimension reference data.

### `DimIndustry` — SCD Type 2

| Column | Description |
|---|---|
| `industry_key` | Surrogate key, `IDENTITY` |
| `sub_vertical` | One of the 46 source sub-verticals |
| `industry_group` | Derived enrichment dimension (7 categories) |
| `effective_from` | Date this version became current |
| `effective_to` | Date this version was superseded; `NULL` while current |
| `is_current` | `1` for the current version of a `sub_vertical`, `0` for superseded ones |

Sourced from `silver_industry`. A new load only inserts a fresh row when a
`sub_vertical`'s `industry_group` differs from its current row — see
`docs/business-rules.md` for the exact change-detection logic.

### `DimEVBracket`

| Column | Description |
|---|---|
| `ev_bracket_key` | Surrogate key, `IDENTITY` |
| `ev_bracket` | Bracket key (e.g. `under_5m_ev`) |
| `min_ev` / `max_ev` | Numeric range bounds |
| `bracket_order` | 1–5, forces correct non-alphabetical sort |

Sourced from `silver_ev_bracket`, 5 rows.

### `DimYear`

| Column | Description |
|---|---|
| `year_key` | Surrogate key, `IDENTITY` |
| `year` | Calendar year |

Sourced from the distinct set of years across `gold_valuation_trend` and
`gold_industry_ranking` — unlike the other dimensions, this one has no
purpose-built reference table in Silver, since year only exists as a
fact-grain attribute in the source data.

### `DimMetric`

| Column | Description |
|---|---|
| `metric_key` | Surrogate key, `IDENTITY` |
| `metric_name` | Display label — `EV/EBITDA` or `EV/Revenue` |
| `metric_code` | Join/filter key — `ev_ebitda` or `ev_revenue` |

Static, 2 rows, seeded directly (no source pipeline).

### `FactValuation`

| Column | Description |
|---|---|
| `valuation_key` | Surrogate key, `IDENTITY` |
| `industry_key` | FK to `DimIndustry`, always populated |
| `ev_bracket_key` | FK to `DimEVBracket` — `NULL` for rows sourced from year-grain Gold tables |
| `year_key` | FK to `DimYear` — `NULL` for rows sourced from bracket-grain Gold tables |
| `metric_key` | FK to `DimMetric`, always populated |
| `p25` | 25th percentile — only populated for rows sourced from `gold_industry_valuation`; `NULL` elsewhere |
| `median_value` | Median multiple |
| `p75` | 75th percentile — same nullability as `p25` |
| `deal_count` | Number of deals — see caveat below |
| `source_gold_table` | Lineage: which Gold table this row was unpivoted from |
| `load_date` | Date this row was loaded (defaults to the load's run date) |

**Grain:** one row per industry × EV bracket **or** year × metric.
`ev_bracket_key` and `year_key` are mutually exclusive on any given
row — never both populated, never both null. Each Gold table's wide
columns (`median_ev_ebitda`, `median_ev_revenue`) are unpivoted into
separate rows here, one per metric, keyed by `metric_key`.

**`deal_count` duplication caveat:** `gold_industry_valuation` already
merges EBITDA and Revenue deal counts into one fallback value (EBITDA
preferred, Revenue as fallback) before the unpivot happens — so the
EV/EBITDA row and EV/Revenue row for the same industry/bracket carry the
*same* `deal_count` value. This is a byproduct of not modifying the
already-verified Gold layer, not a defect. A measure or query that sums
`deal_count` across both metrics for the same industry/bracket will
double-count; filtering to a single `metric_code` first avoids this (see
the Power BI `_Measures` table, where fixed-metric KPIs explicitly filter
to one metric for exactly this reason).

**Not carried into `FactValuation`:** `yoy_change`, `rank`, `percentile`,
and `valuation_premium` all exist in their respective Gold tables but are
deliberately excluded from the star schema's minimal fact design — these
are report-time calculations, recomputed as Power BI DAX measures rather
than stored.
