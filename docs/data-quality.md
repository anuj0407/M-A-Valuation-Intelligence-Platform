# Data Quality Framework — M&A Valuation Intelligence Platform

Implemented in the `03_data_quality` notebook. Validation is a mandatory
pipeline stage, not an optional cleanup step — every row is scored before
it's eligible to reach the canonical Silver table.

## Rules

| # | Rule | Check | Implementation flag |
|---|---|---|---|
| 1 | Null validation | `sub_vertical IS NOT NULL`; `ev_bracket IS NOT NULL` only where `source_file = 'ma_multiples'`; `source_year IS NOT NULL` only where `source_file = 'ma_multiples_by_year'` | `is_null_valid` |
| 2 | Multiple validation | `EV/EBITDA > 0`, `EV/Revenue > 0` | `is_positive_valid` |
| 3 | Percentile consistency | `P25 <= P50 <= P75` | `is_percentile_valid` |
| 4 | Deal-count validation | `deal_count >= 10` (source publishes no cell below this threshold) | `is_deal_count_valid` |
| 5 | Duplicate validation | Uniqueness on `sub_vertical + ev_bracket + metric_type + source_year` | `is_unique_valid` |
| 6 | Range validation | `EV/EBITDA` within 0.5–60.0; `EV/Revenue` within 0.05–25.0 (matches the source's own documented outlier methodology) | `is_range_valid` |

**Rule 1 nuance:** applied per-subset by `source_file`, since the two
source populations legitimately have different null columns —
`multiples.json` rows never have a `source_year`, `multiples-by-year.json`
rows never have an `ev_bracket`. Checking both columns against both
populations would falsely flag every row.

**Rule 5 nuance:** duplicate detection uses `Window.partitionBy().over()`,
not `groupBy` + `join`. A join on nullable key columns (`ev_bracket`,
`source_year` are both legitimately null depending on source) silently
fails, because `NULL = NULL` evaluates to unknown rather than true in SQL
join semantics. The same fix pattern is applied in the Delta merge step
that loads the canonical Silver table (explicit
`OR (...IS NULL AND ...IS NULL)` per nullable key column).

## Outputs

- **`silver_valuation_multiple_validated`** — row-level output with all
  six flags plus an overall `is_valid`. Serves as the input to the
  canonical Silver merge (filtered to `is_valid = True`).
- **`gold_data_quality`** — one summary record per run, `mode=append` to
  preserve full run history.

| Column | Description |
|---|---|
| `run_id` | Pipeline run identifier |
| `dataset_name` | Dataset validated |
| `execution_timestamp` | When validation ran |
| `total_records` | Total rows evaluated |
| `valid_records` | Rows passing all six rules |
| `invalid_records` | Rows failing one or more rules |
| `duplicate_records` | Rows failing Rule 5 |
| `null_records` | Rows failing Rule 1 |
| `quality_score` | `round((valid_records / total_records) * 100, 2)` |
| `pipeline_status` | `PASSED` if `quality_score >= 95.0`, else `FAILED` |

## Last Verified Run

404 / 404 valid, 0 invalid, 0 duplicate, 0 null records — quality score
100%, status `PASSED`.

## Serving Layer Load Verification

The `FactValuation` load (Azure SQL serving layer) is checked with a
simpler row-count reconciliation rather than the six-rule framework above,
since by the time data reaches this stage it has already passed Silver
validation — the risk here is a dimension lookup silently dropping rows,
not a data quality defect in the values themselves. Staged row count is
compared against loaded row count after the surrogate-key-resolving
`INSERT`; a shortfall would indicate a `sub_vertical`, `ev_bracket`,
`year`, or `metric_code` value in Gold that doesn't match any dimension
row. Last verified: 671 staged, 671 loaded — no rows dropped.
