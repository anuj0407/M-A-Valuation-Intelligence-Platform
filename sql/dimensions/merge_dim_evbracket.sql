-- Merge staged EV bracket data into DimEVBracket.

MERGE INTO dbo.DimEVBracket AS target
USING dbo.stg_DimEVBracket AS source
    ON target.ev_bracket = source.ev_bracket
WHEN MATCHED THEN
    UPDATE SET
        target.min_ev        = source.min_ev,
        target.max_ev        = source.max_ev,
        target.bracket_order = source.bracket_order
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ev_bracket, min_ev, max_ev, bracket_order)
    VALUES (source.ev_bracket, source.min_ev, source.max_ev, source.bracket_order);