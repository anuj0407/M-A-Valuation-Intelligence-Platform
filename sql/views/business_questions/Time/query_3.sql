-- Which industries experienced the largest decline?

SELECT * FROM vw_ValuationTrendSummary
ORDER BY yoy_change_pct ASC;