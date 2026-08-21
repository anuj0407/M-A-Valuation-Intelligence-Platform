-- Which benchmarks are supported by the highest number of disclosed deals?

SELECT * FROM vw_DataReliabilitySummary ORDER BY deal_count DESC;