--  Merge staged year data into DimYear.

MERGE INTO dbo.DimYear AS target
USING dbo.stg_DimYear AS source
    ON target.[year] = source.[year]
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([year])
    VALUES (source.[year]);
