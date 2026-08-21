-- Which industries have the lowest multiples?

SELECT * FROM vw_IndustryValuationSummary ORDER BY avg_median_ev_ebitda ASC;