-- Staging tables for dimension loads.

CREATE TABLE dbo.stg_DimEVBracket (
    ev_bracket NVARCHAR(50) NOT NULL,
    min_ev DECIMAL(18,2) NULL,
    max_ev DECIMAL(18,2) NULL,
    bracket_order INT NOT NULL
);

CREATE TABLE dbo.stg_DimYear (
    [year] INT NOT NULL
);
