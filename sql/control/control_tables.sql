-- Control & Audit Schema — M&A Valuation Intelligence Platform Built ahead of the ADF pipeline because the pipeline depends on both
-- tables from its very first run (metadata-driven ingestion + audit logging). Full serving-layer star schema is built separately in

CREATE SCHEMA control;

-- ---------------------------------------------------------------------
-- control.etl_metadata : Drives what ADF ingests. 
-- The pipeline reads active rows here instead of having source/target paths hard-coded, so a new source can be
-- onboarded by inserting a row, not editing pipeline JSON.
-- ---------------------------------------------------------------------
CREATE TABLE control.etl_metadata (
    metadata_id INT IDENTITY(1,1) PRIMARY KEY,
    source_name NVARCHAR(100) NOT NULL,
    source_url NVARCHAR(500) NOT NULL,
    target_path NVARCHAR(500) NOT NULL,  
    file_type NVARCHAR(20) NOT NULL,   
    load_type NVARCHAR(20) NOT NULL DEFAULT 'FULL',  
    is_active BIT NOT NULL DEFAULT 1,
    created_date DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_date DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_etl_metadata_load_type CHECK (load_type IN ('FULL','INCREMENTAL'))
);

-- Seed the two known sources from the spec
INSERT INTO control.etl_metadata (source_name, source_url, target_path, file_type, load_type, is_active)
VALUES
    ('ma_multiples',
     'https://raw.githubusercontent.com/nickcals/multiples/main/multiples.json',
     'bronze/ma_multiples/multiples',
     'JSON', 'FULL', 1),
    ('ma_multiples_by_year',
     'https://raw.githubusercontent.com/nickcals/multiples/main/multiples-by-year.json',
     'bronze/ma_multiples/multiples_by_year',
     'JSON', 'FULL', 1);

-- ---------------------------------------------------------------------
-- control.pipeline_audit
-- Every ADF run — success or failure — writes exactly one row here.(success rate, records processed/rejected, latest successful load).
-- ---------------------------------------------------------------------
CREATE TABLE control.pipeline_audit (
    audit_id            INT IDENTITY(1,1) PRIMARY KEY,
    run_id               NVARCHAR(50)    NOT NULL,   
    pipeline_name         NVARCHAR(100)   NOT NULL,
    start_time            DATETIME2       NOT NULL,
    end_time              DATETIME2       NULL,
    records_read          INT             NULL,
    records_written        INT             NULL,
    records_rejected       INT             NULL,
    status                NVARCHAR(20)    NOT NULL,  
    error_message          NVARCHAR(MAX)   NULL,
    CONSTRAINT CK_pipeline_audit_status CHECK (status IN ('RUNNING','SUCCEEDED','FAILED'))
);

CREATE INDEX IX_pipeline_audit_pipeline_name_start_time
    ON control.pipeline_audit (pipeline_name, start_time DESC);

