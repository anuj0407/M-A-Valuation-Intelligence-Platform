-- view for industry

CREATE VIEW dbo.vw_IndustryValuationSummary AS
SELECT di.sub_vertical, di.industry_group,
    AVG(fv.median_value) AS avg_median_ev_ebitda,
    MIN(fv.median_value) AS min_median_ev_ebitda,
    MAX(fv.median_value) AS max_median_ev_ebitda,
    MAX(fv.median_value) - MIN(fv.median_value) AS valuation_spread,
    SUM(fv.deal_count) AS total_deal_count
FROM dbo.FactValuation fv
INNER JOIN dbo.DimIndustry di ON di.industry_key = fv.industry_key AND di.is_current = 1
INNER JOIN dbo.DimMetric m  ON m.metric_key = fv.metric_key
WHERE m.metric_code = 'ev_ebitda'
AND fv.median_value IS NOT NULL
GROUP BY di.sub_vertical, di.industry_group;
