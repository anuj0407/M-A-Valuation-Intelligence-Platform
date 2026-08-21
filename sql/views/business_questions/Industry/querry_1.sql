-- Which industries have the highest median EV/EBITDA?

SELECT * FROM vw_IndustryValuationSummary ORDER BY avg_median_ev_ebitda DESC;