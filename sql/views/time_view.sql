-- view for time/valuation trend

CREATE VIEW dbo.vw_ValuationTrendSummary AS
WITH yearly AS (
    SELECT
        di.sub_vertical,
        di.industry_group,
        yr.[year],
        fv.median_value AS median_ev_ebitda
    FROM dbo.FactValuation fv
    INNER JOIN dbo.DimIndustry di ON di.industry_key = fv.industry_key AND di.is_current = 1
    INNER JOIN dbo.DimYear yr     ON yr.year_key = fv.year_key
    INNER JOIN dbo.DimMetric m    ON m.metric_key = fv.metric_key
    WHERE m.metric_code = 'ev_ebitda'
      AND fv.median_value IS NOT NULL
)
SELECT
    sub_vertical,
    industry_group,
    [year],
    median_ev_ebitda,
    LAG(median_ev_ebitda) OVER (PARTITION BY sub_vertical ORDER BY [year]) AS prior_year_median,
    CASE
        WHEN [year] - LAG([year]) OVER (PARTITION BY sub_vertical ORDER BY [year]) = 1
        THEN (median_ev_ebitda - LAG(median_ev_ebitda) OVER (PARTITION BY sub_vertical ORDER BY [year]))
             / NULLIF(LAG(median_ev_ebitda) OVER (PARTITION BY sub_vertical ORDER BY [year]), 0) * 100
        ELSE NULL
    END AS yoy_change_pct
FROM yearly;

