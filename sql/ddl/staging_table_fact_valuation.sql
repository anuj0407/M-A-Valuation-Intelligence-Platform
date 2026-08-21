--  Staging table for FactValuation

CREATE TABLE dbo.stg_FactValuation (
    sub_vertical NVARCHAR(100) NOT NULL,
    ev_bracket NVARCHAR(50) NULL,
    [year] INT NULL,
    metric_code NVARCHAR(20) NOT NULL,
    p25 DECIMAL(10,4) NULL,
    median_value DECIMAL(10,4) NULL,
    p75 DECIMAL(10,4) NULL,
    deal_count INT NULL,
    source_gold_table NVARCHAR(50) NOT NULL
);