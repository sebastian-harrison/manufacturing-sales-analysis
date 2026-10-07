-- Rank observed customers each year against the full company. A complete
-- year/code grid retains accounts absent in a period without calling it churn.
-- Review prior-year top-ten declining accounts; also inspect all-account losses.
CREATE OR REPLACE VIEW account_observed_year AS
WITH totals AS (
    SELECT document_year AS year,customer_code,max(customer_display_name) AS customer_display_name,
           sum(reported_sales_amount) AS sales,count(*) AS source_lines
    FROM analysis_lines GROUP BY document_year,customer_code
)
SELECT *,row_number() OVER(PARTITION BY year ORDER BY sales DESC,customer_code) AS revenue_rank
FROM totals;

CREATE OR REPLACE VIEW concentration_year AS
SELECT a.year,max(c.company_sales) AS company_sales,
       sum(a.sales) FILTER(WHERE a.revenue_rank=1) AS top_one_sales,
       sum(a.sales) FILTER(WHERE a.revenue_rank<=5) AS top_five_sales,
       sum(a.sales) FILTER(WHERE a.revenue_rank=1)/nullif(max(c.company_sales),0) AS top_one_share,
       sum(a.sales) FILTER(WHERE a.revenue_rank<=5)/nullif(max(c.company_sales),0) AS top_five_share,
       string_agg(a.customer_code,', ' ORDER BY a.revenue_rank) FILTER(WHERE a.revenue_rank<=5) AS top_five_codes
FROM account_observed_year a JOIN company_year c USING(year) GROUP BY a.year;

CREATE OR REPLACE VIEW account_year_base AS
WITH customers AS (
    SELECT customer_code,max(customer_display_name) AS customer_display_name,
           min(document_date) AS first_observed_date
    FROM sales_lines WHERE customer_code IN(SELECT DISTINCT customer_code FROM analysis_lines)
    GROUP BY customer_code
), grid AS (
    SELECT y.year,c.* FROM company_year y CROSS JOIN customers c
)
SELECT g.year,a.prior_year,g.customer_code,g.customer_display_name,g.first_observed_date,
       c.source_lines IS NOT NULL AS observed_current,
       p.source_lines IS NOT NULL AS observed_prior,
       coalesce(c.sales,0) AS current_sales,
       CASE WHEN a.prior_year IS NOT NULL THEN coalesce(p.sales,0) END AS prior_sales,
       CASE WHEN a.prior_year IS NOT NULL THEN coalesce(c.sales,0)-coalesce(p.sales,0) END AS sales_change,
       CASE WHEN a.prior_year IS NOT NULL AND p.sales>0
            THEN (coalesce(c.sales,0)-p.sales)/p.sales END AS sales_change_ratio,
       c.revenue_rank,p.revenue_rank AS prior_revenue_rank,
       coalesce(c.sales,0)/nullif(k.company_sales,0) AS revenue_share,
       CASE WHEN a.prior_year IS NOT NULL THEN coalesce(p.sales,0)/nullif(a.company_prior_sales,0) END AS prior_revenue_share,
       k.company_sales,k.top_one_sales,k.top_five_sales,k.top_one_share,k.top_five_share,
       a.company_prior_sales,a.company_sales_change,a.company_change_ratio,a.comparison_label,
       CASE WHEN a.prior_year IS NULL THEN 'baseline_year'
            WHEN c.source_lines IS NOT NULL AND p.source_lines IS NOT NULL THEN 'observed_both_periods'
            WHEN c.source_lines IS NOT NULL THEN 'observed_current_only'
            WHEN p.source_lines IS NOT NULL THEN 'not_observed_current'
            ELSE 'not_observed_either_period' END AS comparison_activity_status,
       CASE WHEN a.prior_year IS NULL THEN 'baseline_unavailable'
            WHEN p.source_lines IS NULL THEN 'prior_not_observed'
            WHEN p.sales=0 THEN 'prior_zero_sales'
            ELSE 'positive_prior_baseline' END AS percentage_change_basis
FROM grid g LEFT JOIN account_observed_year c ON c.year=g.year AND c.customer_code=g.customer_code
LEFT JOIN account_observed_year p ON p.year=g.year-1 AND p.customer_code=g.customer_code
JOIN concentration_year k ON k.year=g.year
LEFT JOIN annual_comparisons a ON a.current_year=g.year;

CREATE OR REPLACE VIEW account_year_ranked AS
SELECT *,coalesce(sales_change<0 AND prior_revenue_rank<=10,false) AS is_priority_review,
       CASE WHEN sales_change<0 THEN row_number() OVER(PARTITION BY year ORDER BY sales_change NULLS LAST,customer_code) END AS all_account_loss_rank,
       sales_change/nullif(company_sales_change,0) AS contribution_to_net_change_ratio
FROM account_year_base;

CREATE OR REPLACE VIEW account_review_priorities AS
SELECT *,row_number() OVER(PARTITION BY year ORDER BY sales_change,customer_code) AS priority_review_rank
FROM account_year_ranked WHERE is_priority_review;

CREATE OR REPLACE VIEW account_year_summary AS
SELECT a.*,p.priority_review_rank
FROM account_year_ranked a LEFT JOIN account_review_priorities p USING(year,customer_code);

-- A fixed 2011 top-five cohort checks whether annually re-ranked concentration
-- could be mistaken for growth of the original largest accounts.
CREATE OR REPLACE VIEW concentration_fixed_cohort AS
SELECT y.year,
       sum(coalesce(a.sales,0)) AS fixed_2011_top_five_sales,
       sum(coalesce(a.sales,0))/nullif(max(y.company_sales),0) AS fixed_2011_top_five_share,
       max(y.company_sales) AS company_sales
FROM company_year y CROSS JOIN (SELECT customer_code FROM account_observed_year WHERE year=2011 AND revenue_rank<=5) cohort
LEFT JOIN account_observed_year a ON a.year=y.year AND a.customer_code=cohort.customer_code
GROUP BY y.year;
