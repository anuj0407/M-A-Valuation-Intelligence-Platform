-- How does EV bracket affect valuation?

SELECT ev_bracket, bracket_order, AVG(avg_median_ev_ebitda) AS overall_avg
FROM vw_CompanySizeValuationSummary 
GROUP BY ev_bracket, bracket_order
ORDER BY bracket_order;