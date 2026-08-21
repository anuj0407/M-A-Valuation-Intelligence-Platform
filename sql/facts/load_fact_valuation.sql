-- Load FactValuation from stg_FactValuation.

-- Step 1: full rebuild
TRUNCATE TABLE dbo.FactValuation;

-- Step 2: load with surrogate key resolution
INSERT INTO dbo.FactValuation (industry_key, ev_bracket_key, year_key, metric_key, p25, median_value, p75, deal_count, source_gold_table)
SELECT
    di.industry_key,
    eb.ev_bracket_key,
    yr.year_key,
    m.metric_key,
    s.p25,
    s.median_value,
    s.p75,
    s.deal_count,
    s.source_gold_table
FROM dbo.stg_FactValuation s
INNER JOIN dbo.DimIndustry di
    ON di.sub_vertical = s.sub_vertical AND di.is_current = 1
LEFT JOIN dbo.DimEVBracket eb
    ON eb.ev_bracket = s.ev_bracket
LEFT JOIN dbo.DimYear yr
    ON yr.[year] = s.[year]
INNER JOIN dbo.DimMetric m
    ON m.metric_code = s.metric_code;
