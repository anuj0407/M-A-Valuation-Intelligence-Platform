-- SCD Type 2 load for DimIndustry.
-- Executed by an ADF Script activity (NonQuery) as two statements IN ORDER
-- Step 1: close out the CURRENT row for any sub_vertical whose industry_group has changed (set effective_to, is_current=0).
-- Step 2: insert a fresh current row for anything that now has no current row with a matching industry_group — this single
-- condition correctly covers BOTH cases: brand-new sub_verticals (never had a row) and just-changed ones (their old row was closed by Step 1 above).

-- Step 1
UPDATE d
SET d.effective_to = CAST(GETDATE() AS DATE),
    d.is_current    = 0
FROM dbo.DimIndustry d
INNER JOIN dbo.stg_DimIndustry s
    ON d.sub_vertical = s.sub_vertical
WHERE d.is_current = 1
  AND d.industry_group <> s.industry_group;

-- Step 2
INSERT INTO dbo.DimIndustry (sub_vertical, industry_group, effective_from, effective_to, is_current)
SELECT s.sub_vertical, s.industry_group, CAST(GETDATE() AS DATE), NULL, 1
FROM dbo.stg_DimIndustry s
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.DimIndustry d
    WHERE d.sub_vertical   = s.sub_vertical
      AND d.industry_group = s.industry_group
      AND d.is_current     = 1
);

