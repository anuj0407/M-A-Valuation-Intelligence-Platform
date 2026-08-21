-- Staging table for the DimIndustry SCD Type 2 load.

CREATE TABLE dbo.stg_DimIndustry (
    sub_vertical    NVARCHAR(100)  NOT NULL,
    industry_group  NVARCHAR(50)   NOT NULL
);

