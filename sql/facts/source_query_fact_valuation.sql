-- Source query for CPY_FactValuation_ToStaging (ADF Copy activity).
-- gold_industry_valuation -> 2 branches (ev_ebitda has p25/p75; ev_revenue does not)
-- gold_valuation_trend    -> 2 branches (no p25/p75 on either metric)
-- gold_industry_ranking   -> 1 branch (ev_ebitda only; "industry" column mapped to sub_vertical)
-- gold_ev_bracket_analysis -> 2 branches (no p25/p75 on either metric)

SELECT sub_vertical, ev_bracket, CAST(NULL AS INT) AS year, 'ev_ebitda' AS metric_code,
       p25_ev_ebitda AS p25, median_ev_ebitda AS median_value, p75_ev_ebitda AS p75, deal_count,
       'gold_industry_valuation' AS source_gold_table
FROM gold_industry_valuation
WHERE median_ev_ebitda IS NOT NULL

UNION ALL

SELECT sub_vertical, ev_bracket, CAST(NULL AS INT) AS year, 'ev_revenue' AS metric_code,
       CAST(NULL AS DOUBLE) AS p25, median_ev_revenue AS median_value, CAST(NULL AS DOUBLE) AS p75, deal_count,
       'gold_industry_valuation' AS source_gold_table
FROM gold_industry_valuation
WHERE median_ev_revenue IS NOT NULL

UNION ALL

SELECT sub_vertical, CAST(NULL AS STRING) AS ev_bracket, year, 'ev_ebitda' AS metric_code,
       CAST(NULL AS DOUBLE) AS p25, median_ev_ebitda AS median_value, CAST(NULL AS DOUBLE) AS p75, deal_count,
       'gold_valuation_trend' AS source_gold_table
FROM gold_valuation_trend
WHERE median_ev_ebitda IS NOT NULL

UNION ALL

SELECT sub_vertical, CAST(NULL AS STRING) AS ev_bracket, year, 'ev_revenue' AS metric_code,
       CAST(NULL AS DOUBLE) AS p25, median_ev_revenue AS median_value, CAST(NULL AS DOUBLE) AS p75, deal_count,
       'gold_valuation_trend' AS source_gold_table
FROM gold_valuation_trend
WHERE median_ev_revenue IS NOT NULL

UNION ALL

SELECT industry AS sub_vertical, CAST(NULL AS STRING) AS ev_bracket, year, 'ev_ebitda' AS metric_code,
       CAST(NULL AS DOUBLE) AS p25, median_ev_ebitda AS median_value, CAST(NULL AS DOUBLE) AS p75, deal_count,
       'gold_industry_ranking' AS source_gold_table
FROM gold_industry_ranking
WHERE median_ev_ebitda IS NOT NULL

UNION ALL

SELECT sub_vertical, ev_bracket, CAST(NULL AS INT) AS year, 'ev_ebitda' AS metric_code,
       CAST(NULL AS DOUBLE) AS p25, median_ev_ebitda AS median_value, CAST(NULL AS DOUBLE) AS p75, deal_count,
       'gold_ev_bracket_analysis' AS source_gold_table
FROM gold_ev_bracket_analysis
WHERE median_ev_ebitda IS NOT NULL

UNION ALL

SELECT sub_vertical, ev_bracket, CAST(NULL AS INT) AS year, 'ev_revenue' AS metric_code,
       CAST(NULL AS DOUBLE) AS p25, median_ev_revenue AS median_value, CAST(NULL AS DOUBLE) AS p75, deal_count,
       'gold_ev_bracket_analysis' AS source_gold_table
FROM gold_ev_bracket_analysis
WHERE median_ev_revenue IS NOT NULL
