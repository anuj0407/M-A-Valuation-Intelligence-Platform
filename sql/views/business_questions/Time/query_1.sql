-- How have valuation multiples changed since 2018?

SELECT * FROM vw_ValuationTrendSummary
WHERE [year] >= 2018
ORDER BY sub_vertical, [year];