# Data Dictionary

The Tableau workbook uses four independent CSV sources. Their grains differ;
joining line data to summaries can multiply totals. Monetary fields retain the
source amounts, naira. Dashboard presentation uses the fixed
conversion to USD.

## Sources and aggregation

| Source | Rows | Unique key | Use |
| --- | ---: | --- | --- |
| [sales_lines.csv](../data/exports/sales_lines.csv) | 77,895 | `source_row_id` | Monthly sales and compatible line-level selections. Filter `is_primary_window=true` for 2011–2014. |
| [revenue_drivers.csv](../data/exports/revenue_drivers.csv) | 192 | `current_year`, `contributor_type`, `contributor_key` | One comparison and breakdown at a time; ten losses, five gains and Other. |
| [price_quantity_bridge.csv](../data/exports/price_quantity_bridge.csv) | 15 | `current_year`, `component_code` | One comparison and five signed sales-change components. |
| [account_year_summary.csv](../data/exports/account_year_summary.csv) | 336 | `year`, `customer_code` | Four years × 84 accounts; review rankings, concentration and account history. |

Sales amounts for distinct lines, accounts, contributors or components can be
summed within their stated scope. Company totals, concentration shares,
coverage, item counts and other repeated controls require MAX or MIN at the
year/comparison grain. Percentage ratios are non-additive; 0.25 means 25%.
Account shares may be summed across distinct accounts in a single year for a
subset share. Blank ranks and comparison ratios mean unavailable.

Account selection updates history only. Company concentration always uses all
accounts. Thickness and colour filters affect monthly detail only. Other is a
computed remainder and may combine sales gains and losses.

## Fields

Identifiers and specification codes are text, including values that look
numeric. Dates use ISO `YYYY-MM-DD`; booleans use `true`/`false`. Types below are
the explicit SQL types used for export and round-trip checks. Monetary fields
use decimal types; ratios use DOUBLE.

### sales_lines.csv

| Field | SQL type | Meaning |
| --- | --- | --- |
| `source_row_id` | `INTEGER` | Physical Excel row, including header offset; unique lineage key |
| `source_line_number` | `VARCHAR` | Source `#`, preserved as identifier text |
| `coil_pattern` | `VARCHAR` | `Coil Pattern` |
| `product_group` | `VARCHAR` | `Group Name1`; constant in this extract |
| `product` | `VARCHAR` | `Product`; constant in this extract |
| `document_number` | `VARCHAR` | `Document Number`; not a certified order key |
| `source_document_date` | `VARCHAR` | Original decoded datetime as ISO timestamp or original date string |
| `source_date_kind` | `VARCHAR` | `excel_datetime` or `text` |
| `source_date_number_format` | `VARCHAR` | Original Excel date-cell number format |
| `source_week_label` | `VARCHAR` | Source `Week`; not ISO week or CSV weekday |
| `source_month` | `INTEGER` | Source `Month`, used to interpret date |
| `customer_group` | `VARCHAR` | `Group Name2`; no inferred legal relationship |
| `customer_code` | `VARCHAR` | Account grouping key, preserved case |
| `customer_name` | `VARCHAR` | Original line's `Customer Name` |
| `item_code` | `VARCHAR` | Comparable-item grouping key, preserved case |
| `item_description` | `VARCHAR` | Original description; variants retained |
| `thickness_code` | `VARCHAR` | Source `Thickness`, including letter suffixes |
| `width` | `DECIMAL(18,4)` | Source `Width`; units unconfirmed |
| `source_colour` | `VARCHAR` | Original `Colour` |
| `batch_number` | `VARCHAR` | Source `Batch Number`; case and text zeroes retained |
| `item_cost` | `DECIMAL(18,4)` | `ItemCost`; meaning/unit basis unconfirmed |
| `sales_price` | `DECIMAL(18,4)` | Source `Sales Price`; retained, not an aggregate KPI |
| `reported_quantity` | `DECIMAL(18,4)` | Source `Batch Quantity`; positive, units unconfirmed |
| `vat_value` | `DECIMAL(18,4)` | Source `Vat Value`; preserved without reinterpretation |
| `reported_sales_amount` | `DECIMAL(20,2)` | Source `Sales Amount`; authoritative monetary measure |
| `document_date` | `DATE` | Documented normalization rule; no unresolved values in this run |
| `document_year` | `INTEGER` | Normalized date year |
| `document_month` | `INTEGER` | Normalized date month |
| `document_day` | `INTEGER` | Normalized date day |
| `is_primary_window` | `BOOLEAN` | Normalized year is 2011–2014 |
| `date_corrected` | `BOOLEAN` | True only for the recorded datetime day/month swap |
| `date_normalization_rule` | `VARCHAR` | `datetime_month_matches`, `datetime_day_month_swapped`, `string_day_first`, or `unresolved` |
| `date_issue` | `VARCHAR` | Unresolved reason; empty for every line in this run |
| `colour` | `VARCHAR` | Source colour with two documented case-only display aliases |
| `customer_display_name` | `VARCHAR` | Latest observed name per code, display-only |

### revenue_drivers.csv

| Field | SQL type | Meaning |
| --- | --- | --- |
| `prior_year` | `INTEGER` | Baseline calendar year; unavailable for the 2011 baseline. |
| `current_year` | `INTEGER` | Current calendar year in the comparison. |
| `comparison_label` | `VARCHAR` | Current year versus preceding year. |
| `contributor_type` | `VARCHAR` | Independent breakdown: customer, item, thickness or colour. |
| `contributor_key` | `VARCHAR` | Source code or label; __OTHER__ identifies the combined remainder. |
| `contributor_label` | `VARCHAR` | Display name for the contributor. |
| `is_other` | `BOOLEAN` | True for the combined remainder. |
| `underlying_contributor_count` | `BIGINT` | Number of underlying contributors represented by the row. |
| `prior_sales` | `DECIMAL(38,2)` | Recorded sales for this account or contributor in the prior year. |
| `current_sales` | `DECIMAL(38,2)` | Recorded sales for this account or contributor in the current year. |
| `sales_change` | `DECIMAL(38,2)` | Current sales minus prior sales. |
| `company_prior_sales` | `DECIMAL(38,2)` | Full-company sales in the prior year; repeated control. |
| `company_current_sales` | `DECIMAL(38,2)` | Full-company sales in the current year; repeated control. |
| `company_sales_change` | `DECIMAL(38,2)` | Full-company current minus prior sales; repeated control. |
| `gross_negative_change` | `DECIMAL(38,2)` | Sum of negative underlying contributions, before netting. |
| `gross_positive_change` | `DECIMAL(38,2)` | Sum of positive underlying contributions, before netting. |
| `sales_change_ratio` | `DOUBLE` | Sales change divided by positive prior sales; otherwise unavailable. |
| `prior_company_share` | `DOUBLE` | Contributor prior sales divided by prior company sales. |
| `current_company_share` | `DOUBLE` | Contributor current sales divided by current company sales. |
| `contribution_to_net_change_ratio` | `DOUBLE` | Sales change divided by company net sales change. |
| `display_order` | `BIGINT` | Contributor display position within a year and breakdown. |

### price_quantity_bridge.csv

| Field | SQL type | Meaning |
| --- | --- | --- |
| `prior_year` | `INTEGER` | Baseline calendar year; unavailable for the 2011 baseline. |
| `current_year` | `INTEGER` | Current calendar year in the comparison. |
| `comparison_label` | `VARCHAR` | Current year versus preceding year. |
| `component_order` | `INTEGER` | Display order of the five sales-change components. |
| `component_code` | `VARCHAR` | Stable component identifier. |
| `component_label` | `VARCHAR` | Readable component name. |
| `component_amount` | `DECIMAL(28,8)` | Signed monetary contribution of the component. |
| `company_prior_sales` | `DECIMAL(38,2)` | Full-company sales in the prior year; repeated control. |
| `company_current_sales` | `DECIMAL(38,2)` | Full-company sales in the current year; repeated control. |
| `company_sales_change` | `DECIMAL(38,2)` | Full-company current minus prior sales; repeated control. |
| `matched_item_count` | `BIGINT` | Eligible item codes observed in both years; repeated count. |
| `current_only_item_count` | `BIGINT` | Item codes recorded only in the current year; repeated count. |
| `prior_only_item_count` | `BIGINT` | Item codes recorded only in the prior year; repeated count. |
| `unresolved_item_count` | `BIGINT` | Keys failing matching eligibility; repeated count. |
| `matched_prior_sales` | `DECIMAL(38,2)` | Prior sales for eligible matched items; repeated control. |
| `matched_current_sales` | `DECIMAL(38,2)` | Current sales for eligible matched items; repeated control. |
| `matched_prior_coverage` | `DOUBLE` | Matched prior sales divided by prior company sales. |
| `matched_current_coverage` | `DOUBLE` | Matched current sales divided by current company sales. |
| `unresolved_prior_sales` | `DECIMAL(38,2)` | Prior sales for unresolved keys; repeated control. |
| `unresolved_current_sales` | `DECIMAL(38,2)` | Current sales for unresolved keys; repeated control. |
| `excluded_prior_sales` | `DECIMAL(38,2)` | Prior sales excluded by the scenario; repeated control. |
| `excluded_current_sales` | `DECIMAL(38,2)` | Current sales excluded by the scenario; repeated control. |
| `reconciliation_residual` | `DECIMAL(38,8)` | Component sum minus company sales change; repeated control. |
| `bridge_basis` | `VARCHAR` | Conditional constant within-item quantity-basis assumption. |

### account_year_summary.csv

| Field | SQL type | Meaning |
| --- | --- | --- |
| `year` | `INTEGER` | Primary calendar year, 2011–2014. |
| `prior_year` | `INTEGER` | Baseline calendar year; unavailable for the 2011 baseline. |
| `customer_code` | `VARCHAR` | Account grouping key, preserved case |
| `customer_display_name` | `VARCHAR` | Latest observed name per code, display-only |
| `first_observed_date` | `DATE` | First recorded date for the account in the source. |
| `observed_current` | `BOOLEAN` | Account has at least one source line in this year. |
| `observed_prior` | `BOOLEAN` | Account has at least one source line in the prior year. |
| `current_sales` | `DECIMAL(38,2)` | Recorded sales for this account or contributor in the current year. |
| `prior_sales` | `DECIMAL(38,2)` | Recorded sales for this account or contributor in the prior year. |
| `sales_change` | `DECIMAL(38,2)` | Current sales minus prior sales. |
| `sales_change_ratio` | `DOUBLE` | Sales change divided by positive prior sales; otherwise unavailable. |
| `revenue_rank` | `BIGINT` | Current-year sales rank among observed accounts. |
| `prior_revenue_rank` | `BIGINT` | Prior-year sales rank among observed accounts. |
| `revenue_share` | `DOUBLE` | Current account sales divided by full-company sales. |
| `prior_revenue_share` | `DOUBLE` | Prior account sales divided by prior full-company sales. |
| `company_sales` | `DECIMAL(38,2)` | Full-company sales in this year; repeated control. |
| `top_one_sales` | `DECIMAL(38,2)` | Sales of the largest account in this year; repeated control. |
| `top_five_sales` | `DECIMAL(38,2)` | Sales of the five largest accounts in this year; repeated control. |
| `top_one_share` | `DOUBLE` | Largest-account sales divided by company sales; repeated share. |
| `top_five_share` | `DOUBLE` | Top-five sales divided by company sales; repeated share. |
| `company_prior_sales` | `DECIMAL(38,2)` | Full-company sales in the prior year; repeated control. |
| `company_sales_change` | `DECIMAL(38,2)` | Full-company current minus prior sales; repeated control. |
| `company_change_ratio` | `DOUBLE` | Company sales change divided by prior company sales. |
| `comparison_label` | `VARCHAR` | Current year versus preceding year. |
| `comparison_activity_status` | `VARCHAR` | Recorded presence in the comparison years; not a churn label. |
| `percentage_change_basis` | `VARCHAR` | Availability and baseline status of the percentage comparison. |
| `is_priority_review` | `BOOLEAN` | Prior-year top-ten account with a recorded sales decline. |
| `all_account_loss_rank` | `BIGINT` | Absolute-loss rank across all declining accounts. |
| `contribution_to_net_change_ratio` | `DOUBLE` | Sales change divided by company net sales change. |
| `priority_review_rank` | `BIGINT` | Absolute-loss position within prior-year top-ten losses. |

## Matching and missing activity

Comparable items require activity and positive reported quantity in both years,
with consistent structured specifications. Unit consistency remains assumed.
Both coverage percentages use full-company sales. Current-only and prior-only
items describe recorded presence; they do not establish launches or withdrawals.

The account grid includes unobserved years with zero recorded sales and no rank.
The 2011 baseline has no prior-year comparison. Preserve these distinctions when
filtering or interpreting account losses.
