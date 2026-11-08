# Superstore Sales: Star Schema, SQL ETL and Power BI

An end-to-end analytics project: raw CSV sales data is loaded into a SQL Server data warehouse modelled as a star schema, then analysed in a two-page Power BI dashboard.

**Tools:** SQL Server · T-SQL · Power BI Desktop · DAX

![Sales Overview](images/page1_sales_overview.png)

---

## Business questions

1. Which product categories drive sales and profit?
2. How did sales develop from 2023 to 2025?
3. **How do discounts affect profitability?**
4. Which regions and countries perform best?
5. Who are the most valuable customers?

## Dataset

| | |
|---|---|
| Period | Jan 2023 – Dec 2025 |
| Rows (order lines) | 3,737 |
| Orders | 1,500 |
| Customers | 200 |
| Products | 49 (3 categories, 10 sub-categories) |
| Markets | 10 countries across the Gulf, North Africa and the Levant |

---

## Data model (star schema)

![Data Model](images/model_view.png)

**Grain of the fact table:** one row = one product line within one order.

| Table | Type | Key columns |
|---|---|---|
| `Fact_Sales` | Fact | Sales, Profit, Quantity, Discount, ShipDays |
| `Dim_Date` | Dimension (role-playing) | DateKey (yyyymmdd), Year, Quarter, Month |
| `Dim_Customer` | Dimension | CustomerKey, CustomerName, Segment |
| `Dim_Product` | Dimension | ProductKey, ProductName, SubCategory, Category |
| `Dim_Geography` | Dimension | GeographyKey, City, Country, Region |
| `Dim_ShipMode` | Dimension | ShipModeKey, ShipMode |

**Relationships:** 6 one-to-many relationships, all single-direction.
`Dim_Date` is a role-playing dimension with two relationships to the fact table:
- `OrderDateKey` is **active** (the default for analysis)
- `ShipDateKey` is **inactive** and is used through `USERELATIONSHIP()` in DAX

---

## ETL process (SQL Server)

```
CSV  →  stg_Sales (raw text)  →  Dimensions (DISTINCT + surrogate keys)  →  Fact_Sales (key lookups)
```

1. **Extract:** `BULK INSERT` loads the CSV into a staging table where every column is `NVARCHAR`, so no row is rejected at load time.
2. **Transform:**
   - `Dim_Date` is generated as a full calendar with a recursive CTE
   - dimensions are loaded with `SELECT DISTINCT` and given `IDENTITY` surrogate keys
   - the fact load converts types (`CAST` to `INT`/`DECIMAL`/`DATE`), looks up surrogate keys through joins and derives `ShipDays`
3. **Validate:** row counts and the Sales and Profit totals in staging and in the fact table are checked against each other.

**Issue solved:** the first fact load failed with *"Error converting data type nvarchar to numeric"*. The cause was the Windows line ending (`CR LF`): with `ROWTERMINATOR = '0x0a'` a hidden carriage return (`CHAR(13)`) stayed attached to the last column (`Profit`). I fixed it by cleaning the column with `REPLACE(Profit, CHAR(13), '')` and changing the terminator to `0x0d0a`. Keeping staging as raw text is what made the problem easy to find and fix inside SQL.

Script: [`sql/superstore_star_schema.sql`](sql/superstore_star_schema.sql)

---

## DAX measures

```dax
Total Sales      = SUM(Fact_Sales[Sales])
Total Profit     = SUM(Fact_Sales[Profit])
Orders           = DISTINCTCOUNT(Fact_Sales[OrderID])
Profit Margin %  = DIVIDE([Total Profit], [Total Sales])
Avg Ship Days    = AVERAGE(Fact_Sales[ShipDays])
Sales LY         = CALCULATE([Total Sales], SAMEPERIODLASTYEAR(Dim_Date[Date]))
Sales YoY %      = DIVIDE([Total Sales] - [Sales LY], [Sales LY])
Sales YTD        = TOTALYTD([Total Sales], Dim_Date[Date])
Sales by Ship Date =
    CALCULATE([Total Sales], USERELATIONSHIP(Dim_Date[DateKey], Fact_Sales[ShipDateKey]))
```

---

## Dashboard

**Page 1: Sales Overview.** KPI cards, monthly sales trend against last year, sales by category and sub-category, and slicers for Year, Region and Segment.

**Page 2: Profitability and Shipping.** Profit and margin matrix by sub-category and year, profit margin by discount level, average shipping days by ship mode, and the top 10 customers.

![Profitability](images/page2_profitability.png)

---

## Key findings

| Metric | Value |
|---|---|
| Total Sales | **4.87M** |
| Total Profit | **1.01M** |
| Profit Margin | **20.8%** |

### 1. Discounts above 20% destroy profit (main finding)

| Discount | Sales | Profit | Margin |
|---|---|---|---|
| 0% | 3.01M | 829K | 27.5% |
| 10% | 879K | 173K | 19.7% |
| 20% | 584K | 59K | 10.1% |
| 30% | 312K | ‑8K | **‑2.7%** |
| 50% | 85K | ‑39K | **‑45.2%** |

Every additional 10% of discount costs about 8–9 margin points. At 30% the business starts losing money, and at 50% it loses 45 cents on every unit of currency sold.
**Recommendation:** cap discounts at 20%.

### 2. Technology drives the business
Technology accounts for **61%** of sales (2.96M) at a 21.4% margin. **Machines** is the most profitable sub-category in absolute terms (460K profit). **Art** (25.6%) and **Phones** (24.2%) have the highest margins, and **Storage** (18.0%) and **Bookcases** (18.5%) the lowest.

### 3. Sales are flat
Sales stayed stable at about 1.6M per year (2023: 1.64M, 2024: 1.63M, 2025: 1.61M), which is a slight decline of about 1% per year. The business is not growing.

### 4. Gulf leads, Levant lags
| Region | Sales | Margin |
|---|---|---|
| Gulf | 2.13M | 21.7% |
| North Africa | 1.74M | 21.2% |
| Levant | 1.01M | **18.4%** |

Saudi Arabia is the largest market (789K, 23.2% margin). Lebanon has the weakest margin (16.3%).

### 5. Customers and shipping
- **Consumer** is the largest segment (52% of sales).
- The top customer, Khaled Mansour, generated 204K in sales.
- Standard Class takes an average of **5.1 days**, compared with 1.4 days for First Class.

---

## Repository structure

```
├── data/
│   └── superstore_sales.csv
├── sql/
│   └── superstore_star_schema.sql
├── powerbi/
│   └── Superstore_Sales.pbix
├── images/
│   ├── page1_sales_overview.png
│   ├── page2_profitability.png
│   └── model_view.png
└── README.md
```

## How to run

1. Copy `data/superstore_sales.csv` to `C:\Data\` (or change the path in the script).
2. Run `sql/superstore_star_schema.sql` in SSMS.
3. Open `powerbi/Superstore_Sales.pbix` and update the SQL Server connection under *Transform data → Data source settings*.

---

*Project 1 of a data analytics portfolio series: Star Schema → Power BI → SQL ETL.*
