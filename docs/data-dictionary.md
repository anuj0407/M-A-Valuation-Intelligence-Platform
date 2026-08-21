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

### `FactValuation`
`valuation_key, industry_key, ev_bracket_key, year_key, metric_key, p25,
median_value, p75, deal_count`

### Dimensions
- `DimIndustry` — SCD Type 2: `industry_key, sub_vertical, industry_group,
  effective_from, effective_to, is_current`
- `DimEVBracket`
- `DimYear`
- `DimMetric`
