-- Which industries have the strongest size-related valuation premium?

SELECT * FROM vw_CompanySizeValuationSummary
ORDER BY valuation_premium_pct DESC;