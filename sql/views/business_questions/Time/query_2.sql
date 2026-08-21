-- Which industries experienced the largest YoY increase?

SELECT * FROM vw_ValuationTrendSummary
ORDER BY yoy_change_pct DESC;