# Pipeline Design — PL_MA_Multiples_Ingestion

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
