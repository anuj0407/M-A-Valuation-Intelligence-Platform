-- view for data reliability

CREATE VIEW dbo.vw_DataReliabilitySummary AS
SELECT
    di.sub_vertical,
    di.industry_group,
    eb.ev_bracket,
    yr.[year],
    m.metric_name,
    fv.deal_count,
    fv.p25,
    fv.median_value,
    fv.p75,
    fv.source_gold_table
FROM dbo.FactValuation fv
INNER JOIN dbo.DimIndustry di ON di.industry_key = fv.industry_key AND di.is_current = 1
LEFT JOIN dbo.DimEVBracket eb  ON eb.ev_bracket_key = fv.ev_bracket_key
LEFT JOIN dbo.DimYear yr       ON yr.year_key = fv.year_key
INNER JOIN dbo.DimMetric m     ON m.metric_key = fv.metric_key
WHERE fv.deal_count IS NOT NULL;
