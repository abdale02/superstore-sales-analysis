/* =====================================================================
   Project 1 - Superstore Sales  |  Star Schema in SQL Server
   Steps:
     1) Create database
     2) Staging table + load CSV (BULK INSERT)
     3) Dimension tables
     4) Fact table
     5) Load dimensions and fact from staging
     6) Validation queries
   ===================================================================== */

-- 1) DATABASE ---------------------------------------------------------
IF DB_ID('SuperstoreDW') IS NULL
    CREATE DATABASE SuperstoreDW;
GO
USE SuperstoreDW;
GO

-- 2) STAGING ----------------------------------------------------------
-- Raw copy of the CSV, everything as text (like a landing zone)
DROP TABLE IF EXISTS dbo.stg_Sales;
CREATE TABLE dbo.stg_Sales (
    OrderID       NVARCHAR(20),
    OrderDate     NVARCHAR(20),
    ShipDate      NVARCHAR(20),
    ShipMode      NVARCHAR(30),
    CustomerID    NVARCHAR(20),
    CustomerName  NVARCHAR(100),
    Segment       NVARCHAR(30),
    Country       NVARCHAR(50),
    City          NVARCHAR(50),
    State         NVARCHAR(50),
    Region        NVARCHAR(30),
    ProductID     NVARCHAR(20),
    Category      NVARCHAR(50),
    SubCategory   NVARCHAR(50),
    ProductName   NVARCHAR(200),
    Sales         NVARCHAR(20),
    Quantity      NVARCHAR(20),
    Discount      NVARCHAR(20),
    Profit        NVARCHAR(20)
);
GO

-- !! Change the path to where you saved superstore_sales.csv
BULK INSERT dbo.stg_Sales
FROM 'C:\Data\superstore_sales.csv'
WITH (
    FORMAT          = 'CSV',      -- handles quoted values with commas
    FIRSTROW        = 2,          -- skip header
    FIELDQUOTE      = '"',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0d0a',    -- Windows line ending (CR LF)
    CODEPAGE        = '65001'     -- UTF-8
);
GO
-- Alternative: SSMS > right-click database > Tasks > Import Flat File

-- 3) DIMENSIONS -------------------------------------------------------
DROP TABLE IF EXISTS dbo.Fact_Sales;
DROP TABLE IF EXISTS dbo.Dim_Customer;
DROP TABLE IF EXISTS dbo.Dim_Product;
DROP TABLE IF EXISTS dbo.Dim_Geography;
DROP TABLE IF EXISTS dbo.Dim_ShipMode;
DROP TABLE IF EXISTS dbo.Dim_Date;
GO

CREATE TABLE dbo.Dim_Date (
    DateKey      INT          NOT NULL PRIMARY KEY,   -- 20250131
    [Date]       DATE         NOT NULL,
    [Year]       INT          NOT NULL,
    [Quarter]    TINYINT      NOT NULL,
    QuarterName  CHAR(2)      NOT NULL,               -- Q1
    [Month]      TINYINT      NOT NULL,
    MonthName    NVARCHAR(15) NOT NULL,
    YearMonth    CHAR(7)      NOT NULL,               -- 2025-01
    [Day]        TINYINT      NOT NULL,
    DayOfWeek    TINYINT      NOT NULL,               -- 1 = Monday
    DayName      NVARCHAR(15) NOT NULL,
    IsWeekend    BIT          NOT NULL
);

CREATE TABLE dbo.Dim_Customer (
    CustomerKey   INT IDENTITY(1,1) PRIMARY KEY,      -- surrogate key
    CustomerID    NVARCHAR(20)  NOT NULL UNIQUE,      -- business key
    CustomerName  NVARCHAR(100) NOT NULL,
    Segment       NVARCHAR(30)  NOT NULL
);

CREATE TABLE dbo.Dim_Product (
    ProductKey    INT IDENTITY(1,1) PRIMARY KEY,
    ProductID     NVARCHAR(20)  NOT NULL UNIQUE,
    ProductName   NVARCHAR(200) NOT NULL,
    SubCategory   NVARCHAR(50)  NOT NULL,
    Category      NVARCHAR(50)  NOT NULL
);

CREATE TABLE dbo.Dim_Geography (
    GeographyKey  INT IDENTITY(1,1) PRIMARY KEY,
    City          NVARCHAR(50) NOT NULL,
    State         NVARCHAR(50) NOT NULL,
    Country       NVARCHAR(50) NOT NULL,
    Region        NVARCHAR(30) NOT NULL,
    CONSTRAINT UQ_Geo UNIQUE (City, State, Country)
);

CREATE TABLE dbo.Dim_ShipMode (
    ShipModeKey   INT IDENTITY(1,1) PRIMARY KEY,
    ShipMode      NVARCHAR(30) NOT NULL UNIQUE
);
GO

-- 4) FACT -------------------------------------------------------------
-- Grain: one row = one product line inside one order
CREATE TABLE dbo.Fact_Sales (
    SalesKey       INT IDENTITY(1,1) PRIMARY KEY,
    OrderID        NVARCHAR(20)  NOT NULL,            -- degenerate dimension
    OrderDateKey   INT NOT NULL REFERENCES dbo.Dim_Date(DateKey),
    ShipDateKey    INT NOT NULL REFERENCES dbo.Dim_Date(DateKey),
    CustomerKey    INT NOT NULL REFERENCES dbo.Dim_Customer(CustomerKey),
    ProductKey     INT NOT NULL REFERENCES dbo.Dim_Product(ProductKey),
    GeographyKey   INT NOT NULL REFERENCES dbo.Dim_Geography(GeographyKey),
    ShipModeKey    INT NOT NULL REFERENCES dbo.Dim_ShipMode(ShipModeKey),
    Quantity       INT           NOT NULL,
    Sales          DECIMAL(12,2) NOT NULL,
    Discount       DECIMAL(4,2)  NOT NULL,
    Profit         DECIMAL(12,2) NOT NULL,
    ShipDays       INT           NOT NULL
);
GO

-- 5) LOAD -------------------------------------------------------------
-- 5a) Dim_Date: full calendar from first to last date in the data
DECLARE @Start DATE, @End DATE;
SELECT @Start = DATEFROMPARTS(YEAR(MIN(CAST(OrderDate AS DATE))), 1, 1),
       @End   = DATEFROMPARTS(YEAR(MAX(CAST(ShipDate  AS DATE))), 12, 31)
FROM dbo.stg_Sales;

SET DATEFIRST 1;   -- Monday = 1
WITH Calendar AS (
    SELECT @Start AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM Calendar WHERE d < @End
)
INSERT INTO dbo.Dim_Date
SELECT
    CONVERT(INT, FORMAT(d, 'yyyyMMdd')),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    'Q' + CAST(DATEPART(QUARTER, d) AS CHAR(1)),
    MONTH(d),
    DATENAME(MONTH, d),
    FORMAT(d, 'yyyy-MM'),
    DAY(d),
    DATEPART(WEEKDAY, d),
    DATENAME(WEEKDAY, d),
    CASE WHEN DATEPART(WEEKDAY, d) IN (6, 7) THEN 1 ELSE 0 END
FROM Calendar
OPTION (MAXRECURSION 0);
GO

-- 5b) Small dimensions (DISTINCT from staging)
INSERT INTO dbo.Dim_Customer (CustomerID, CustomerName, Segment)
SELECT DISTINCT CustomerID, CustomerName, Segment
FROM dbo.stg_Sales;

INSERT INTO dbo.Dim_Product (ProductID, ProductName, SubCategory, Category)
SELECT DISTINCT ProductID, ProductName, SubCategory, Category
FROM dbo.stg_Sales;

INSERT INTO dbo.Dim_Geography (City, State, Country, Region)
SELECT DISTINCT City, State, Country, Region
FROM dbo.stg_Sales;

INSERT INTO dbo.Dim_ShipMode (ShipMode)
SELECT DISTINCT ShipMode
FROM dbo.stg_Sales;
GO

-- 5c) Fact: look up surrogate keys from each dimension
INSERT INTO dbo.Fact_Sales
    (OrderID, OrderDateKey, ShipDateKey, CustomerKey, ProductKey,
     GeographyKey, ShipModeKey, Quantity, Sales, Discount, Profit, ShipDays)
SELECT
    s.OrderID,
    CONVERT(INT, FORMAT(CAST(s.OrderDate AS DATE), 'yyyyMMdd')),
    CONVERT(INT, FORMAT(CAST(s.ShipDate  AS DATE), 'yyyyMMdd')),
    c.CustomerKey,
    p.ProductKey,
    g.GeographyKey,
    m.ShipModeKey,
    CAST(s.Quantity AS INT),
    CAST(s.Sales    AS DECIMAL(12,2)),
    CAST(s.Discount AS DECIMAL(4,2)),
    CAST(s.Profit   AS DECIMAL(12,2)),
    DATEDIFF(DAY, CAST(s.OrderDate AS DATE), CAST(s.ShipDate AS DATE))
FROM dbo.stg_Sales s
JOIN dbo.Dim_Customer  c ON c.CustomerID = s.CustomerID
JOIN dbo.Dim_Product   p ON p.ProductID  = s.ProductID
JOIN dbo.Dim_Geography g ON g.City = s.City AND g.State = s.State AND g.Country = s.Country
JOIN dbo.Dim_ShipMode  m ON m.ShipMode   = s.ShipMode;
GO

-- 6) VALIDATION -------------------------------------------------------
-- Row counts: staging and fact must match (expected 3737)
SELECT 'stg_Sales'  AS tbl, COUNT(*) AS rows FROM dbo.stg_Sales
UNION ALL SELECT 'Fact_Sales',    COUNT(*) FROM dbo.Fact_Sales
UNION ALL SELECT 'Dim_Customer',  COUNT(*) FROM dbo.Dim_Customer
UNION ALL SELECT 'Dim_Product',   COUNT(*) FROM dbo.Dim_Product
UNION ALL SELECT 'Dim_Geography', COUNT(*) FROM dbo.Dim_Geography
UNION ALL SELECT 'Dim_ShipMode',  COUNT(*) FROM dbo.Dim_ShipMode
UNION ALL SELECT 'Dim_Date',      COUNT(*) FROM dbo.Dim_Date;

-- Totals must match between staging and fact
SELECT SUM(CAST(Sales AS DECIMAL(12,2)))  AS stg_sales,
       SUM(CAST(Profit AS DECIMAL(12,2))) AS stg_profit FROM dbo.stg_Sales;
SELECT SUM(Sales) AS fact_sales, SUM(Profit) AS fact_profit FROM dbo.Fact_Sales;

-- First analysis query: sales and profit by year and category
SELECT d.[Year], p.Category,
       SUM(f.Sales)  AS TotalSales,
       SUM(f.Profit) AS TotalProfit,
       CAST(SUM(f.Profit) * 100.0 / SUM(f.Sales) AS DECIMAL(5,1)) AS ProfitMarginPct
FROM dbo.Fact_Sales f
JOIN dbo.Dim_Date    d ON d.DateKey    = f.OrderDateKey
JOIN dbo.Dim_Product p ON p.ProductKey = f.ProductKey
GROUP BY d.[Year], p.Category
ORDER BY d.[Year], TotalSales DESC;
