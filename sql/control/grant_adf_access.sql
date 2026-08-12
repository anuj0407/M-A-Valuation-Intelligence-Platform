-- Query to grant access for reading and writing to Azure data factory

CREATE USER [ADF-name-used] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [ADF-name-used];
ALTER ROLE db_datawriter ADD MEMBER [ADF-name-used];
