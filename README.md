# M&A Valuation Intelligence Platform

An end-to-end Azure data engineering and analytics platform that ingests a public M&A valuation multiples dataset, processes it through a Medallion (Bronze → Silver → Gold) architecture on Databricks and Delta Lake, loads it into a relational star schema in Azure SQL, and serves it through a 4-page executive Power BI dashboard. Ingestion and transformation (GitHub → Bronze → Silver → Gold) are automated end to end on a daily schedule; the Azure SQL serving layer is currently loaded by running its three pipelines in sequence.

---

## 1. Summary

Investment firms, M&A advisory teams, and corporate development analysts need to understand how companies are valued across industries and enterprise-value (EV) ranges — but valuation data is usually scattered across raw files and requires manual processing before it can answer even basic questions ("What's the typical EV/EBITDA multiple for a given industry and deal size?").

This project builds a production-style data platform that automatically **ingests → validates → stores → transforms → curates → serves → visualizes** the M&A Multiples Index dataset on Microsoft Azure, so that answering those questions becomes a matter of opening a dashboard rather than wrangling spreadsheets.

Ingestion and transformation run on a daily schedule: a new snapshot lands in the data lake and automatically triggers the Databricks transformation job, carrying data through to the curated Gold layer with no manual steps. The Azure SQL star schema load and the Power BI dashboard refresh are currently run on demand.

## 2. Tech Stack

| Layer | Technology |
|---|---|
| Orchestration | Azure Data Factory (ADF) |
| Storage | Azure Data Lake Storage (ADLS) Gen2 |
| Transformation Engine | Azure Databricks (PySpark) |
| Table Format | Delta Lake |
| Serving / Relational Layer | Azure SQL Database |
| Visualization | Power BI |
| Secrets & Identity | Azure Key Vault, Managed Identity, Microsoft Entra ID |

## 3. Dataset Overview

**Source:** M&A Multiples Index — `github.com/nickcals/multiples` (public, continuously updated; source window 2018–2026).

The source publishes two structured JSON resources:

| File | Grain | Key fields |
|---|---|---|
| `multiples.json` | Industry sub-vertical × EV bracket | EV/EBITDA, EV/Revenue, P25 / Median (P50) / P75, number of disclosed deals |
| `multiples-by-year.json` | Industry sub-vertical × year | EV/EBITDA, EV/Revenue, median deal value, number of deals (time-series view) |

- **Industries:** 46 sub-verticals, grouped into 7 higher-level `industry_group` categories (Healthcare, Technology, Industrial, Consumer, Energy, Professional Services, Financial) via a documented keyword-matching rule, since the source does not provide this grouping itself.
- **EV brackets (5, ordered):** `<$5M`, `$5M–$25M`, `$25M–$100M`, `$100M–$500M`, `>$500M`.
- **Reliability rule:** the source itself requires at least 10 disclosed deals for a published cell to be considered reliable; the platform enforces this as a data-quality rule.
- **Outlier bounds (per source methodology):** EV/EBITDA 0.5–60.0, EV/Revenue 0.05–25.0.
- The dataset is treated as an **external, mutable source** — every ingestion is stored as its own dated snapshot rather than overwriting the previous load, so any past state of the dataset can be reproduced.

## 4. Architecture

![Architecture Design](architecture/architecture-diagram.png)

The platform follows a **Medallion Architecture**: Bronze preserves the data exactly as received (with full ingestion metadata and dated snapshots for historical reproducibility), Silver applies schema enforcement, flattening, cleansing and deduplication, and Gold produces curated, business-ready aggregates. From Gold, a relational star schema in Azure SQL supports fast, familiar BI querying, and Power BI provides the executive-facing layer.

Authentication throughout uses **Managed Identity / Microsoft Entra auth** — no passwords or storage keys are stored in pipelines or notebooks, with one deliberate, documented exception (a Databricks personal access token held in Key Vault, required for one specific ADF connector type that doesn't support Managed Identity).

## 5. Azure Resources

| Resource | Name |
|---|---|
| Resource Group | `rg-ma-valuation-intelligence-platform` |
| Storage Account (ADLS Gen2) | `stmavaluationplatform` — containers `raw`, `silver`, `gold`, `adf-staging` |
| Key Vault | `kv-ma-valuation-platform` (RBAC permission model) |
| Data Factory | `adf-ma-valuation-intelligence-platform` |
| Azure SQL Server / Database | `sql-ma-valuation-platform` / `ma-valuation-db` (Entra-only auth) |
| Databricks Workspace | `dbw-ma-valuation-platform` (Unity Catalog enabled) |
| Databricks Cluster | `cluster-ma-valuation` (single node, 20-min auto-terminate) |
| Databricks Job | `job-ma-valuation-pipeline` |

## 6. Ingestion Layer (Azure Data Factory)

Pipeline **`PL_MA_Multiples_Ingestion`**:

1. `SCR_AuditStart` logs the run start to `control.pipeline_audit`.
2. `LKP_GetActiveSources` reads the active sources, URLs, and load type (`FULL` / `INCREMENTAL`) from a metadata-driven table, `control.etl_metadata` — nothing is hard-coded.
3. `FE_ProcessSources` loops per source: a `FULL` source always re-copies; an `INCREMENTAL` source only copies if today's dated Bronze folder doesn't already exist.
4. Files land at `raw/ma_multiples/ingestion_date=YYYY-MM-DD/`, preserving a full dated history instead of overwriting.
5. On success, a Databricks Job activity automatically triggers the full transformation pipeline — ingestion and transformation run end to end with zero manual steps.
6. `SCR_AuditSuccess` / `SCR_AuditFailure` closes out the audit log.

A daily schedule trigger automates the run; the Copy activity retries transient failures (3 retries / 30s); a `run_date` parameter supports backfilling a specific past date.

## 7. Transformation Layer (Databricks / PySpark / Delta Lake)

Five notebooks, chained with linear dependencies in `job-ma-valuation-pipeline`:

1. **`01_ingestion_validation`** — confirms Bronze files landed, checks structure, captures row/column counts and source metadata.
2. **`02_bronze_to_silver`** — recursively flattens the nested JSON (dynamic field names, not `explode`) into `silver_valuation_multiple_staging`, `silver_ev_bracket` (5 brackets with sort order), and `silver_industry` (46 sub-verticals classified into 7 industry groups).
3. **`03_data_quality`** — applies 6 validation rules (see below) and writes both a row-level validated table and an append-only `gold_data_quality` report table.
4. **`04_delta_merge`** — an idempotent `MERGE` from the validated staging table into the canonical `silver_valuation_multiple` table, keyed on `sub_vertical + metric_type + ev_bracket + source_year`, so re-running the pipeline never creates duplicates.
5. **`05_silver_to_gold`** — builds four curated Gold tables: `gold_industry_valuation`, `gold_valuation_trend`, `gold_industry_ranking`, `gold_ev_bracket_analysis`.

### Data Quality Rules

| Rule | Description |
|---|---|
| Null validation | `sub_vertical`, `ev_bracket` must not be null |
| Multiple validation | EV/EBITDA and EV/Revenue must be > 0 |
| Percentile consistency | P25 ≤ Median ≤ P75 |
| Deal-count validation | `deal_count` ≥ 10 (per source methodology) |
| Duplicate validation | Uniqueness on `sub_vertical + ev_bracket + metric_type + year` |
| Range / outlier validation | EV/EBITDA within 0.5–60.0; EV/Revenue within 0.05–25.0 |

Results are written to `gold_data_quality`, tracking total, valid, invalid, duplicate, and null record counts plus an overall quality score per run.

## 8. Serving Layer (Azure SQL Star Schema)

Gold Delta tables are loaded into Azure SQL by three dedicated ADF pipelines (Copy → ADLS staging hop → Script activity), kept separate from the ingestion pipeline:

- **`PL_Load_Dim_EVBracket_Year`** — loads `DimEVBracket` and `DimYear`.
- **`PL_Load_Dim_Industry`** — loads `DimIndustry` with full **SCD Type 2** logic (UPDATE to close changed rows, then INSERT for new/current rows), tracking `effective_from`, `effective_to`, `is_current`.
- **`PL_Load_FactValuation`** — unpivots the wide Gold tables into narrow fact rows and resolves surrogate keys against all four dimensions.

**Star schema:**

```
        DimIndustry (SCD Type 2)
              │
DimEVBracket ─┼─ FactValuation ─┼─ DimYear
              │
          DimMetric
```

`FactValuation` grain: industry × (EV bracket **or** year) × metric, with `p25`, `median_value`, `p75`, and `deal_count`.

Four SQL views (`vw_IndustryValuationSummary`, `vw_CompanySizeValuationSummary`, `vw_ValuationTrendSummary`, `vw_DataReliabilitySummary`) answer the project's target business questions directly against the star schema.

## 9. Power BI Dashboard

Connected in **Import mode** against the Azure SQL star schema, with an 11-measure table driving dynamic metric selection (EV/EBITDA vs. EV/Revenue) via a `DimMetric` slicer. Four pages:

1. **Executive Overview** — 6 KPI cards (total industries, total deals, average multiples, highest-valuation industry, latest data year) plus industry ranking, EV bracket distribution, EV/EBITDA vs. EV/Revenue, and deal count by industry.
2. **Industry Benchmark** — filterable by industry, EV bracket, year, and metric; a benchmark table and a percentile-range (P25/Median/P75) chart per industry.
3. **Valuation Trend** — median multiple over time and year-over-year change.
4. **Deal Market Intelligence** — deal volume by industry, an industry × EV-bracket valuation heatmap, and a Top-10 industries ranking with minimum-deal-count filtering.

## 10. Security

- All pipeline and notebook authentication uses **Managed Identity** or Microsoft Entra auth.
- No passwords or storage account keys are stored in ADF pipelines or Databricks notebooks.
- Secrets (the one Databricks PAT required for a connector type that doesn't support Managed Identity) are stored in **Azure Key Vault**, referenced at runtime — never hard-coded.
- Azure SQL uses Entra-only authentication (no SQL logins); a dedicated native Entra user with `db_datareader` access is used for Power BI, kept separate from the tenant's owner account.
- Access to storage is governed by Azure RBAC and Unity Catalog external locations / storage credentials, not shared account keys.

## 11. Prerequisites

To deploy or reproduce this platform, you will need:

- An active **Azure subscription** with permissions to create resource groups and the resources listed in Section 5.
- **Azure CLI** (or Azure Portal access) for provisioning and role assignments.
- An **Azure Databricks** workspace with Unity Catalog enabled.
- **Power BI Desktop** (a native Microsoft Entra user, not a personal/MSA-type account, is required to authenticate against Azure SQL).
- Network/outbound access from Azure Data Factory to the public GitHub source.
- Familiarity with PySpark, T-SQL, and Power BI/DAX for maintaining or extending the pipeline.

## 12. Business Questions the Platform Answers

As of now, based on the current data load, the dashboard can answer questions such as:

- **Which industries have the highest / lowest median EV/EBITDA, and the largest valuation spread?** — e.g. Healthtech currently ranks as the highest-valuation industry on the Executive Overview page.
- **How does EV bracket (company size) affect valuation multiples?** — visible directly on the Industry Benchmark page's percentile-range (P25/Median/P75) chart, filterable by bracket.
- **How have valuation multiples changed since 2018, and which industries moved the most year-over-year?** — the Valuation Trend page plots median multiple over time alongside YoY % change (46 industries, latest data year 2025).
- **Which benchmarks are backed by the strongest sample sizes, and which are lower-confidence?** — the Deal Market Intelligence page's deal-volume and Top-10 views, combined with the platform's minimum-deal-count (≥10) quality rule.

Current headline KPIs on the dashboard: 46 total industries, ~5K total deals, average EV/EBITDA of 12.19×, average EV/Revenue of 2.04×.