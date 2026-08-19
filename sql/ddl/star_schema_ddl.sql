-- ---------------------------------------------------------------------
-- DimEVBracket
-- Source: silver_ev_bracket (5 known bracket values, static)
-- ---------------------------------------------------------------------
CREATE TABLE dbo.DimEVBracket (
    ev_bracket_key INT IDENTITY(1,1) NOT NULL,
    ev_bracket NVARCHAR(50) NOT NULL,   
    min_ev DECIMAL(18,2) NULL,
    max_ev DECIMAL(18,2) NULL,
    bracket_order INT NOT NULL,   
    CONSTRAINT PK_DimEVBracket PRIMARY KEY CLUSTERED (ev_bracket_key),
    CONSTRAINT UQ_DimEVBracket_bracket UNIQUE (ev_bracket)
);

-- ---------------------------------------------------------------------
-- DimYear
-- Source: distinct years across gold_valuation_trend / gold_industry_ranking
-- ---------------------------------------------------------------------
CREATE TABLE dbo.DimYear (
    year_key INT IDENTITY(1,1) NOT NULL,
    [year] INT NOT NULL,
    CONSTRAINT PK_DimYear PRIMARY KEY CLUSTERED (year_key),
    CONSTRAINT UQ_DimYear_year UNIQUE ([year])
);

-- ---------------------------------------------------------------------
-- DimMetric
-- Static dimension, 2 rows 
-- metric_code matches the source column suffix (ev_ebitda / ev_revenue)
-- so the load script can map Gold's wide columns onto it directly.
-- ---------------------------------------------------------------------
CREATE TABLE dbo.DimMetric (
    metric_key INT IDENTITY(1,1) NOT NULL,
    metric_name NVARCHAR(50) NOT NULL,   -- 'EV/EBITDA', 'EV/Revenue'
    metric_code NVARCHAR(20) NOT NULL,   -- 'ev_ebitda', 'ev_revenue'
    CONSTRAINT PK_DimMetric PRIMARY KEY CLUSTERED (metric_key),
    CONSTRAINT UQ_DimMetric_name UNIQUE (metric_name),
    CONSTRAINT UQ_DimMetric_code UNIQUE (metric_code)
);

-- ---------------------------------------------------------------------
-- DimIndustry (SCD Type 2)
-- Source: silver_industry 
-- First load: effective_from = load date, effective_to = NULL, is_current = 1 for every row. A later load only inserts a new version when industry_group
-- for an existing sub_vertical has changed; the prior row is then closed out (effective_to set, is_current = 0) rather than updated in place.
-- ---------------------------------------------------------------------
CREATE TABLE dbo.DimIndustry (
    industry_key INT IDENTITY(1,1) NOT NULL,
    sub_vertical NVARCHAR(100) NOT NULL,
    industry_group NVARCHAR(50) NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    is_current BIT NOT NULL CONSTRAINT DF_DimIndustry_current DEFAULT (1),
    CONSTRAINT PK_DimIndustry PRIMARY KEY CLUSTERED (industry_key)
);

-- Only one current row per sub_vertical at a time
CREATE UNIQUE INDEX UQ_DimIndustry_current ON dbo.DimIndustry (sub_vertical)
WHERE is_current = 1;

-- ---------------------------------------------------------------------
-- FactValuation
-- Source: unpivoted gold_industry_valuation / gold_valuation_trend /
--         gold_industry_ranking / gold_ev_bracket_analysis
--
-- p25 / p75 are NULL for rows sourced from any Gold table other than
-- gold_industry_valuation, which is the only one that carries them.
-- ---------------------------------------------------------------------
CREATE TABLE dbo.FactValuation (
    valuation_key BIGINT IDENTITY(1,1) NOT NULL,
    industry_key INT NOT NULL,
    ev_bracket_key INT NULL,
    year_key INT NULL,
    metric_key INT NOT NULL,
    p25 DECIMAL(10,4) NULL,
    median_value DECIMAL(10,4) NULL,
    p75 DECIMAL(10,4) NULL,
    deal_count INT NULL,
    source_gold_table NVARCHAR(50) NOT NULL, 
    load_date DATE NOT NULL CONSTRAINT DF_FactValuation_loaddate DEFAULT (CAST(GETDATE() AS DATE)),
    CONSTRAINT PK_FactValuation PRIMARY KEY CLUSTERED (valuation_key),
    CONSTRAINT FK_FactValuation_Industry FOREIGN KEY (industry_key) REFERENCES dbo.DimIndustry (industry_key),
    CONSTRAINT FK_FactValuation_EVBracket FOREIGN KEY (ev_bracket_key) REFERENCES dbo.DimEVBracket (ev_bracket_key),
    CONSTRAINT FK_FactValuation_Year FOREIGN KEY (year_key) REFERENCES dbo.DimYear (year_key),
    CONSTRAINT FK_FactValuation_Metric FOREIGN KEY (metric_key) REFERENCES dbo.DimMetric (metric_key)
);

CREATE INDEX IX_FactValuation_Industry_Bracket_Year_Metric
    ON dbo.FactValuation (industry_key, ev_bracket_key, year_key, metric_key);

