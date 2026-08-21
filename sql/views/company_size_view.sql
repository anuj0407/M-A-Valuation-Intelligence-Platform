-- view for company size

CREATE VIEW dbo.vw_CompanySizeValuationSummary AS
WITH bracket_avg AS (
    SELECT
        di.industry_key,
        di.sub_vertical,
        di.industry_group,
        eb.ev_bracket,
        eb.bracket_order,
        AVG(fv.median_value) AS avg_median_ev_ebitda
    FROM dbo.FactValuation fv
    INNER JOIN dbo.DimIndustry di  ON di.industry_key = fv.industry_key AND di.is_current = 1
    INNER JOIN dbo.DimEVBracket eb ON eb.ev_bracket_key = fv.ev_bracket_key
    INNER JOIN dbo.DimMetric m     ON m.metric_key = fv.metric_key
    WHERE m.metric_code = 'ev_ebitda'
      AND fv.median_value IS NOT NULL
    GROUP BY di.industry_key, di.sub_vertical, di.industry_group, eb.ev_bracket, eb.bracket_order
),
industry_avg AS (
    SELECT industry_key, AVG(avg_median_ev_ebitda) AS industry_cross_bracket_avg
    FROM bracket_avg
    GROUP BY industry_key
)
SELECT
    b.sub_vertical,
    b.industry_group,
    b.ev_bracket,
    b.bracket_order,
    b.avg_median_ev_ebitda,
    ia.industry_cross_bracket_avg,
    (b.avg_median_ev_ebitda - ia.industry_cross_bracket_avg) / NULLIF(ia.industry_cross_bracket_avg, 0) * 100 AS valuation_premium_pct
FROM bracket_avg b
INNER JOIN industry_avg ia ON ia.industry_key = b.industry_key;