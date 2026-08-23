# Pipeline Design — M&A Valuation Intelligence Platform

This document covers all four ADF pipelines in the platform: the original
ingestion pipeline, and the three pipelines that load the Azure SQL
serving layer from Gold.

---

# Pipeline 1 — PL_MA_Multiples_Ingestion

## Overview

This pipeline pulls the M&A Multiples Index from its public GitHub source,
lands it in the ADLS Gen2 Bronze layer once a day (keeping a dated
snapshot from every run rather than overwriting the previous one), and
triggers the downstream Databricks transformation job so a single
pipeline run carries data all the way from raw ingestion through Gold.

## Pipeline Flow

```
SCR_AuditStart
      │
      ▼
LKP_GetActiveSources   (reads which sources are active from a control table)
      │
      ▼
FE_ProcessSources       (loops once per active source)
      │
      ├─ GMD_CheckBronzeExists   (has today's file already landed?)
      │
      └─ IF_ShouldCopy
             ├─ Yes → copy the file into Bronze, record it as processed
             └─ No  → skip (already ingested today)
      │
      ▼ on success (all sources processed)
DB_RunValuationPipeline   (Databricks Job activity — runs the 5-notebook
                            transformation chain)
      │
      ▼ on success                    ▼ on failure (from ForEach OR from DB_RunValuationPipeline)
SCR_AuditSuccess                  SCR_AuditFailure
```

## What Each Step Does

- **SCR_AuditStart** — logs that a run has started.
- **LKP_GetActiveSources** — looks up which sources should be ingested this
  run, instead of having source details hard-coded into the pipeline.
- **FE_ProcessSources** — loops through each active source one at a time.
- **GMD_CheckBronzeExists / IF_ShouldCopy** — decides whether a source
  needs copying this run (see FULL vs Incremental below).
- **Copy step** — fetches the file from GitHub and writes it into the
  Bronze layer. Configured with a retry policy of 3 retries at a 30s
  interval to absorb transient failures against the external GitHub
  source.
- **DB_RunValuationPipeline** — a Databricks Job activity that runs after
  the ForEach completes successfully. It triggers
  `job-ma-valuation-pipeline`, a linear chain of five notebooks that
  reads and validates the newly landed Bronze files, flattens and cleans
  them into Silver, runs the data quality checks, merges validated
  records into the canonical Silver table, and produces the curated Gold
  tables. Its parameters are left blank — each notebook defaults
  `ingestion_date` to today via its own widget, matching the ADF run's
  implicit date. This activity has its own failure path, which also
  routes to `SCR_AuditFailure`, so a Databricks-side failure is captured
  with the same audit logging as an ADF-side one.
- **SCR_AuditSuccess / SCR_AuditFailure** — logs how the run ended, and how
  many files were actually copied.

Verified end-to-end: a full pipeline run completed with all 13 ADF
activities green, and the Job activity ran the complete notebook chain in
~4m9s.

## Partitioning

Every run lands its files under a dated folder, so historical snapshots
are always preserved:

```
raw/ma_multiples/ingestion_date=2026-08-13/multiples.json
raw/ma_multiples/ingestion_date=2026-08-13/multiples-by-year.json
```

A pipeline parameter (`run_date`) lets a run be pointed at a specific past
date for backfilling, defaulting to the current date otherwise.

## FULL vs Incremental Loads

Each source is marked as either `FULL` or `INCREMENTAL` in the control
table. A `FULL` source always re-copies on every run. An `INCREMENTAL`
source only copies if today's file hasn't already landed — if it has, that
source is skipped for the rest of the day. This was tested by flipping one
source to `INCREMENTAL` and confirming a same-day rerun correctly skipped
it while the other source copied as normal.

## Retry & Failure Handling

- **Copy activity:** 3 retries / 30s interval, to handle transient
  failures reaching the external GitHub source.
- **Databricks Job activity:** no retry configured at the ADF level — the
  job itself is idempotent (see `docs/business-rules.md`), so a manual or
  scheduled re-run is safe. Any failure routes straight to
  `SCR_AuditFailure`.
- Both the ForEach's failure path and `DB_RunValuationPipeline`'s failure
  path converge on the same `SCR_AuditFailure` step, so the audit log
  captures failures from either stage identically.

## Logging

Every run writes one record covering when it started and ended, how it
finished (succeeded or failed), how many files were actually copied, and
the error message if something went wrong. This gives a simple history of
every ingestion run over time, spanning both the ADF-side copy and the
downstream Databricks transformation.

---

# Pipelines 2–4 — Azure SQL Serving Layer

These three pipelines populate the Azure SQL star schema from the Gold Delta tables. They are separate, standalone pipelines — none of them modify `PL_MA_Multiples_Ingestion` or the Databricks job chain; they read from Gold/Silver as those layers already stand.

## Shared Pattern

All three pipelines follow the same two-stage shape: a **Copy activity**
that reads from Databricks and stages the result in Azure SQL, followed
by a **Script activity** that runs the actual load logic (MERGE, SCD2
update+insert, or truncate+insert) against the real target table.

**Source connection:** a dedicated linked service
(`LS_Databricks_DeltaLake`) connects to the Databricks Delta Lake tables
directly, authenticating via a Databricks personal access token stored in
Key Vault. This is a different linked service from the one used to
trigger the Databricks Job in Pipeline 1 — that one authenticates for job
triggering, not for querying individual Delta tables, so a
Delta-Lake-specific connector was needed.

**Staging requirement:** ADF's Databricks Delta Lake connector cannot
write directly into an Azure SQL sink — Copy activities from this source
type require an intermediate staging hop through Blob/ADLS storage. Each
Copy activity in these three pipelines has "Enable staging" turned on,
pointed at a dedicated `adf-staging` container (kept separate from
`raw`/`silver`/`gold` to avoid mixing serving-layer plumbing into the
medallion layers).

**Sink connection:** the same `LS_AzureSqlDatabase_MI` linked service used
throughout the project, authenticating via ADF's managed identity.

## Pipeline 2 — PL_Load_Dim_EVBracket_Year

Loads `DimEVBracket` and `DimYear`, the two static/simple dimensions.

```
CPY_EVBracket_ToStaging → CPY_Year_ToStaging → SCR_Merge_Dimensions
```

- **CPY_EVBracket_ToStaging** — reads `silver_ev_bracket`, stages into
  `dbo.stg_DimEVBracket` (pre-copy script truncates the staging table
  first).
- **CPY_Year_ToStaging** — reads a `UNION ALL DISTINCT` of the `year`
  column across `gold_valuation_trend` and `gold_industry_ranking`,
  stages into `dbo.stg_DimYear`.
- **SCR_Merge_Dimensions** — runs two `MERGE` statements (NonQuery),
  matching on each table's natural key (`ev_bracket`, `year`), so the
  pipeline is safe to re-run without duplicating rows or disturbing
  surrogate keys already referenced by `FactValuation`.

## Pipeline 3 — PL_Load_Dim_Industry

Loads `DimIndustry`, implementing SCD Type 2. See
`docs/business-rules.md` for the change-detection logic itself.

```
CPY_Industry_ToStaging → SCR_SCD2_DimIndustry
```

- **CPY_Industry_ToStaging** — reads `sub_vertical, industry_group` from
  `silver_industry`, stages into `dbo.stg_DimIndustry`.
- **SCR_SCD2_DimIndustry** — runs two SQL statements **in order** (not a
  single MERGE — SCD2 genuinely needs a close-out step followed by a
  separate insert step): first an `UPDATE` that closes out any current
  row whose `industry_group` no longer matches staging, then an `INSERT`
  that adds a fresh current row for anything with no matching current
  row — which correctly covers both brand-new sub-verticals and
  sub-verticals whose classification just changed.

## Pipeline 4 — PL_Load_FactValuation

Loads `FactValuation`, unpivoting all four Gold tables into the fact
table's narrow grain and resolving surrogate keys against all four
dimensions.

```
CPY_FactValuation_ToStaging → SCR_Load_FactValuation
```

- **CPY_FactValuation_ToStaging** — the source query is a 7-branch
  `UNION ALL` across the four Gold tables (`gold_industry_valuation` and
  `gold_ev_bracket_analysis` each contribute two branches — one per
  metric; `gold_valuation_trend` the same; `gold_industry_ranking`
  contributes one, since it only carries EV/EBITDA). Each branch is
  filtered to exclude rows where that branch's metric value is null.
  Stages into `dbo.stg_FactValuation`.
- **SCR_Load_FactValuation** — first `TRUNCATE TABLE dbo.FactValuation`
  (safe here, since nothing downstream has an FK into `FactValuation`),
  then a single `INSERT ... SELECT` joining staging against all four
  dimensions to resolve surrogate keys (`DimIndustry` filtered to
  `is_current = 1`; `DimEVBracket`/`DimYear` as `LEFT JOIN`s, since a
  given staging row only ever has one of the two populated).

Verified: 671 staging rows in, 671 `FactValuation` rows out — every row
resolved cleanly against all four dimensions with none dropped by the
joins.

## Run Order

These three pipelines have a dependency order: Pipeline 2 and Pipeline 3
must both complete before Pipeline 4 runs, since `FactValuation`'s load
looks up surrogate keys from all four dimension tables. They are
currently run manually in sequence; they are not yet wired into a single
parent pipeline or trigger.
