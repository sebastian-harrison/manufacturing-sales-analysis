# SQL Analysis

The queries measure annual sales changes, contributions by account and product
specification, comparable-item quantity and price patterns, and customer
concentration over 2011–2014.

[Read the supporting results](../reports/supporting_analysis.md) ·
[Return to the project overview](../README.md)

## Query guide

| File | Purpose |
| --- | --- |
| [01_load.sql](01_load.sql) | Load prepared sales lines with explicit data types and select the reporting window. |
| [02_quality_checks.sql](02_quality_checks.sql) | Check ingestion, analytical totals and exported values at the relevant execution phases. |
| [03_revenue_drivers.sql](03_revenue_drivers.sql) | Compare annual sales; calculate customer, item, thickness and colour contributions; examine account/specification changes and monthly coverage. |
| [04_price_quantity.sql](04_price_quantity.sql) | Separate comparable-item sales change into quantity and realized-price associations, with matching sensitivities. |
| [05_account_performance.sql](05_account_performance.sql) | Rank account losses and calculate annual concentration, account histories and the fixed 2011 customer group. |
| [06_exports.sql](06_exports.sql) | Write the four independent CSV sources used by Tableau. |

