-- Establish the calendar-year baseline and identify complete, reconcilable
-- account/item/specification contributions. Every dimension explains the same
-- company change separately. Observed-only contributors are retained.
CREATE OR REPLACE VIEW company_year AS
SELECT document_year AS year, sum(reported_sales_amount) AS company_sales,
       count(*) AS source_lines, count(DISTINCT customer_code) AS observed_customers,
       count(DISTINCT item_code) AS observed_items,
       count(DISTINCT document_month) AS observed_months
FROM analysis_lines GROUP BY document_year;

CREATE OR REPLACE VIEW company_month AS
SELECT date_trunc('month',document_date)::DATE AS month_start,
       document_year AS year, document_month AS month,
       sum(reported_sales_amount) AS reported_sales_amount, count(*) AS source_lines,
       min(document_date) AS first_recorded_date, max(document_date) AS last_recorded_date
FROM analysis_lines GROUP BY ALL;

CREATE OR REPLACE VIEW annual_comparisons AS
SELECT p.year AS prior_year, c.year AS current_year,
       c.year::VARCHAR || ' vs ' || p.year::VARCHAR AS comparison_label,
       p.company_sales AS company_prior_sales, c.company_sales AS company_current_sales,
       c.company_sales-p.company_sales AS company_sales_change,
       (c.company_sales-p.company_sales)/nullif(p.company_sales,0) AS company_change_ratio
FROM company_year c JOIN company_year p ON c.year=p.year+1;

CREATE OR REPLACE VIEW item_metadata AS
SELECT item_code, max(thickness_code) AS thickness_code, max(width) AS width,
       max(colour) AS colour, max(coil_pattern) AS coil_pattern,
       count(DISTINCT item_description) AS description_variants,
       count(DISTINCT thickness_code)=1 AND count(DISTINCT width)=1
       AND count(DISTINCT source_colour)=1 AND count(DISTINCT coil_pattern)=1
           AS structured_specs_consistent,
       item_code || ' | ' || max(thickness_code) || ' x ' ||
           max(width)::INTEGER::VARCHAR || ' | ' || max(colour) || ' | ' ||
           max(coil_pattern) AS item_label
FROM sales_lines GROUP BY item_code;

CREATE OR REPLACE VIEW driver_entity_year AS
SELECT document_year AS year, 'customer' AS contributor_type,
       customer_code AS contributor_key,
       customer_code || ' | ' || max(customer_display_name) AS contributor_label,
       sum(reported_sales_amount) AS sales, count(*) AS source_lines
FROM analysis_lines GROUP BY document_year,customer_code
UNION ALL
SELECT l.document_year, 'item', l.item_code, max(m.item_label),
       sum(l.reported_sales_amount), count(*)
FROM analysis_lines l JOIN item_metadata m USING(item_code)
GROUP BY l.document_year,l.item_code
UNION ALL
SELECT document_year, 'thickness', thickness_code, 'Thickness ' || thickness_code,
       sum(reported_sales_amount), count(*)
FROM analysis_lines GROUP BY document_year,thickness_code
UNION ALL
SELECT document_year, 'colour', colour, colour,
       sum(reported_sales_amount), count(*)
FROM analysis_lines GROUP BY document_year,colour;

CREATE OR REPLACE VIEW revenue_drivers_full AS
WITH period_pairs AS (
    SELECT coalesce(p.year,c.year-1) AS prior_year,
           coalesce(c.year,p.year+1) AS current_year,
           coalesce(p.contributor_type,c.contributor_type) AS contributor_type,
           coalesce(p.contributor_key,c.contributor_key) AS contributor_key,
           coalesce(c.contributor_label,p.contributor_label) AS contributor_label,
           coalesce(p.sales,0) AS prior_sales, coalesce(c.sales,0) AS current_sales,
           p.source_lines IS NOT NULL AS observed_prior,
           c.source_lines IS NOT NULL AS observed_current
    FROM driver_entity_year p FULL OUTER JOIN driver_entity_year c
      ON c.year=p.year+1 AND c.contributor_type=p.contributor_type
      AND c.contributor_key=p.contributor_key
), changes AS (
    SELECT b.*, a.comparison_label, a.company_prior_sales, a.company_current_sales,
           a.company_sales_change, b.current_sales-b.prior_sales AS sales_change,
           (b.current_sales-b.prior_sales)/nullif(b.prior_sales,0) AS sales_change_ratio,
           b.prior_sales/nullif(a.company_prior_sales,0) AS prior_company_share,
           b.current_sales/nullif(a.company_current_sales,0) AS current_company_share
    FROM period_pairs b JOIN annual_comparisons a USING(prior_year,current_year)
)
SELECT *, sales_change/nullif(company_sales_change,0) AS contribution_to_net_change_ratio,
       row_number() OVER(PARTITION BY current_year,contributor_type ORDER BY sales_change,contributor_key) AS loss_rank,
       row_number() OVER(PARTITION BY current_year,contributor_type ORDER BY sales_change DESC,contributor_key) AS gain_rank
FROM changes;

-- Tableau receives the largest 10 losses, largest 5 gains and one exact Other
-- remainder per dimension/comparison. Full details stay in a reviewable report.
CREATE OR REPLACE VIEW revenue_drivers AS
WITH labelled AS (
    SELECT *, (sales_change<0 AND loss_rank<=10) OR
              (sales_change>0 AND gain_rank<=5) AS selected
    FROM revenue_drivers_full
), grouped AS (
    SELECT prior_year,current_year,comparison_label,contributor_type,
           CASE WHEN selected THEN contributor_key ELSE '__OTHER__' END AS contributor_key,
           CASE WHEN selected THEN contributor_label ELSE 'Other contributors' END AS contributor_label,
           NOT selected AS is_other, count(*) AS underlying_contributor_count,
           sum(prior_sales) AS prior_sales, sum(current_sales) AS current_sales,
           sum(sales_change) AS sales_change,
           max(company_prior_sales) AS company_prior_sales,
           max(company_current_sales) AS company_current_sales,
           max(company_sales_change) AS company_sales_change,
           sum(CASE WHEN sales_change<0 THEN sales_change ELSE 0 END) AS gross_negative_change,
           sum(CASE WHEN sales_change>0 THEN sales_change ELSE 0 END) AS gross_positive_change
    FROM labelled GROUP BY ALL
)
SELECT *, sales_change/nullif(prior_sales,0) AS sales_change_ratio,
       prior_sales/nullif(company_prior_sales,0) AS prior_company_share,
       current_sales/nullif(company_current_sales,0) AS current_company_share,
       sales_change/nullif(company_sales_change,0) AS contribution_to_net_change_ratio,
       row_number() OVER(PARTITION BY current_year,contributor_type ORDER BY is_other,sales_change,contributor_key) AS display_order
FROM grouped;

-- Focused competing explanations: broad activity vs a few large losses;
-- product losses within accounts; and December/quarter reporting context.
CREATE OR REPLACE VIEW decline_distribution AS
SELECT prior_year,current_year,comparison_label,contributor_type,
       count(*) AS contributors_in_either_period,
       count(*) FILTER(WHERE sales_change<0) AS declining_contributors,
       count(*) FILTER(WHERE sales_change>0) AS growing_contributors,
       count(*) FILTER(WHERE NOT observed_current AND observed_prior) AS prior_only_contributors,
       count(*) FILTER(WHERE observed_current AND NOT observed_prior) AS current_only_contributors,
       sum(sales_change) FILTER(WHERE sales_change<0) AS gross_losses,
       sum(sales_change) FILTER(WHERE sales_change>0) AS gross_gains,
       sum(sales_change) FILTER(WHERE sales_change<0 AND loss_rank<=4) AS four_largest_losses,
       max(company_sales_change) AS company_sales_change
FROM revenue_drivers_full GROUP BY ALL;

CREATE OR REPLACE VIEW customer_thickness_changes AS
WITH yearly AS (
    SELECT document_year AS year,customer_code,max(customer_display_name) AS customer_display_name,
           thickness_code,sum(reported_sales_amount) AS sales
    FROM analysis_lines GROUP BY document_year,customer_code,thickness_code
), pairs AS (
    SELECT coalesce(p.year,c.year-1) AS prior_year,coalesce(c.year,p.year+1) AS current_year,
           coalesce(c.customer_code,p.customer_code) AS customer_code,
           coalesce(c.customer_display_name,p.customer_display_name) AS customer_display_name,
           coalesce(c.thickness_code,p.thickness_code) AS thickness_code,
           coalesce(p.sales,0) AS prior_sales,coalesce(c.sales,0) AS current_sales
    FROM yearly p FULL OUTER JOIN yearly c ON c.year=p.year+1
      AND c.customer_code=p.customer_code AND c.thickness_code=p.thickness_code
)
SELECT p.*,current_sales-prior_sales AS sales_change
FROM pairs p JOIN annual_comparisons a USING(prior_year,current_year);

CREATE OR REPLACE VIEW period_coverage_diagnostic AS
WITH yearly AS (
    SELECT document_year AS year,
       sum(reported_sales_amount) FILTER(WHERE document_month<=11) AS jan_nov_sales,
       sum(reported_sales_amount) FILTER(WHERE document_month=12) AS december_sales,
       sum(reported_sales_amount) FILTER(WHERE document_month BETWEEN 1 AND 3) AS q1_sales,
       sum(reported_sales_amount) FILTER(WHERE document_month BETWEEN 4 AND 6) AS q2_sales,
       sum(reported_sales_amount) FILTER(WHERE document_month BETWEEN 7 AND 9) AS q3_sales,
       sum(reported_sales_amount) FILTER(WHERE document_month BETWEEN 10 AND 12) AS q4_sales
    FROM analysis_lines GROUP BY document_year
)
SELECT y.*,c.company_sales,jan_nov_sales/nullif(lag(jan_nov_sales) OVER(ORDER BY year),0)-1 AS jan_nov_change_ratio
FROM yearly y JOIN company_year c USING(year);
