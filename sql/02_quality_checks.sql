-- Reconcile source, preparation, SQL and exported grains. The runner executes
-- each phase after its dependencies exist and stops before publishing on failure.
-- @phase ingestion
CREATE OR REPLACE TEMP VIEW ingestion_checks AS
WITH actual AS (
 SELECT count(*) AS rows,count(DISTINCT source_row_id) AS ids,
        sum(reported_sales_amount) AS sales,count(*) FILTER(WHERE is_primary_window) AS primary_rows,
        count(DISTINCT customer_code) FILTER(WHERE is_primary_window) AS primary_customers,
        count(DISTINCT item_code) FILTER(WHERE is_primary_window) AS primary_items,
        count(*) FILTER(WHERE date_corrected) AS corrected_dates,
        count(*) FILTER(WHERE customer_code IS NULL OR customer_code='' OR item_code IS NULL OR item_code=''
           OR document_number IS NULL OR document_number='' OR batch_number IS NULL OR batch_number='') AS missing_ids,
        count(*) FILTER(WHERE document_date IS NULL OR date_issue<>'') AS unresolved_dates,
        count(*) FILTER(WHERE document_year<>year(document_date) OR document_month<>month(document_date)
           OR document_day<>day(document_date) OR source_month<>month(document_date)
           OR is_primary_window<>(year(document_date) BETWEEN 2011 AND 2014)) AS calendar_mismatches,
        count(*) FILTER(WHERE abs(reported_sales_amount-sales_price*reported_quantity)>0.01) AS arithmetic_failures,
        count(*) FILTER(WHERE reported_quantity<=0 OR reported_sales_amount<0 OR sales_price<0) AS invalid_business_values,
        count(DISTINCT date_trunc('month',document_date)) FILTER(WHERE is_primary_window) AS primary_months
 FROM sales_lines
), date_rules AS (
 SELECT count(*) AS violations FROM sales_lines
 WHERE CASE
   WHEN source_date_kind='text' THEN
     document_date IS DISTINCT FROM try_strptime(source_document_date,'%d-%m-%Y')::DATE
     OR date_corrected OR date_normalization_rule<>'string_day_first'
   WHEN source_date_kind='excel_datetime' AND month(source_document_date::TIMESTAMP)=source_month THEN
     document_date IS DISTINCT FROM source_document_date::TIMESTAMP::DATE
     OR date_corrected OR date_normalization_rule<>'datetime_month_matches'
   WHEN source_date_kind='excel_datetime' AND day(source_document_date::TIMESTAMP)=source_month THEN
     document_date IS DISTINCT FROM make_date(year(source_document_date::TIMESTAMP)::INTEGER,
       day(source_document_date::TIMESTAMP)::INTEGER,month(source_document_date::TIMESTAMP)::INTEGER)
     OR NOT date_corrected OR date_normalization_rule<>'datetime_day_month_swapped'
   ELSE true END
), lineage AS (
 SELECT count(*) AS violations FROM sales_lines s FULL OUTER JOIN prepared_text p
   ON s.source_row_id=p.source_row_id::INTEGER
 WHERE s.source_row_id IS NULL OR p.source_row_id IS NULL
   OR s.customer_code IS DISTINCT FROM p.customer_code
   OR s.item_code IS DISTINCT FROM p.item_code
   OR s.batch_number IS DISTINCT FROM p.batch_number
   OR s.document_number IS DISTINCT FROM p.document_number
   OR s.thickness_code IS DISTINCT FROM p.thickness_code
   OR s.reported_sales_amount IS DISTINCT FROM p.reported_sales_amount::DECIMAL(38,12)
   OR s.reported_quantity IS DISTINCT FROM p.reported_quantity::DECIMAL(38,12)
   OR s.sales_price IS DISTINCT FROM p.sales_price::DECIMAL(38,12)
   OR s.item_cost IS DISTINCT FROM p.item_cost::DECIMAL(38,12)
   OR s.vat_value IS DISTINCT FROM p.vat_value::DECIMAL(38,12)
   OR s.width IS DISTINCT FROM p.width::DECIMAL(38,12)
)
SELECT 'ingestion' AS phase,v.check_name,v.actual_value,v.expected_rule,
       CASE WHEN v.passed THEN 'PASS' ELSE 'FAIL' END AS status,'critical' AS severity
FROM actual a CROSS JOIN ingest_controls e CROSS JOIN date_rules d CROSS JOIN lineage l
CROSS JOIN LATERAL (VALUES
 ('source_prepared_sql_rows',a.rows::VARCHAR,e.source_rows::VARCHAR,a.rows=e.source_rows),
 ('prepared_text_sql_rows',(SELECT count(*) FROM prepared_text)::VARCHAR,a.rows::VARCHAR,(SELECT count(*) FROM prepared_text)=a.rows),
 ('source_prepared_sql_sales',a.sales::VARCHAR,e.source_sales::VARCHAR,a.sales=e.source_sales),
 ('unique_source_row_ids',a.ids::VARCHAR,a.rows::VARCHAR,a.ids=a.rows),
 ('primary_rows',a.primary_rows::VARCHAR,e.primary_rows::VARCHAR,a.primary_rows=e.primary_rows),
 ('primary_customer_codes',a.primary_customers::VARCHAR,e.primary_customers::VARCHAR,a.primary_customers=e.primary_customers),
 ('primary_item_codes',a.primary_items::VARCHAR,e.primary_items::VARCHAR,a.primary_items=e.primary_items),
 ('corrected_dates',a.corrected_dates::VARCHAR,e.corrected_dates::VARCHAR,a.corrected_dates=e.corrected_dates),
 ('identifiers_present',a.missing_ids::VARCHAR,'0',a.missing_ids=0),
 ('dates_resolved',a.unresolved_dates::VARCHAR,'0',a.unresolved_dates=0),
 ('calendar_and_scope_fields',a.calendar_mismatches::VARCHAR,'0',a.calendar_mismatches=0),
 ('date_normalization_rules',d.violations::VARCHAR,'0',d.violations=0),
 ('sales_price_quantity_arithmetic',a.arithmetic_failures::VARCHAR,'0 over 0.01 source units',a.arithmetic_failures=0),
 ('positive_quantity_nonnegative_sales_price',a.invalid_business_values::VARCHAR,'0',a.invalid_business_values=0),
 ('primary_observed_months',a.primary_months::VARCHAR,'48; not proof of complete capture',a.primary_months=48),
 ('lineage_and_decimal_scale_preserved',l.violations::VARCHAR,'0',l.violations=0)
) v(check_name,actual_value,expected_rule,passed);

-- @phase analysis
CREATE OR REPLACE VIEW analysis_checks AS
WITH driver_full AS (
 SELECT prior_year,current_year,contributor_type,sum(sales_change) AS change,
        sum(prior_sales) AS prior_sales,sum(current_sales) AS current_sales,
        max(company_sales_change) AS company_change,max(company_prior_sales) AS company_prior,
        max(company_current_sales) AS company_current
 FROM revenue_drivers_full GROUP BY ALL
), driver_ranked AS (
 SELECT prior_year,current_year,contributor_type,sum(sales_change) AS change,
        sum(prior_sales) AS prior_sales,sum(current_sales) AS current_sales,
        max(company_sales_change) AS company_change,max(company_prior_sales) AS company_prior,
        max(company_current_sales) AS company_current
 FROM revenue_drivers GROUP BY ALL
), account AS (
 SELECT year,sum(current_sales) AS sales,max(company_sales) AS company_sales,
        sum(revenue_share) AS shares,
        sum(current_sales) FILTER(WHERE revenue_rank=1) AS top_one,
        sum(current_sales) FILTER(WHERE revenue_rank<=5) AS top_five,
        max(top_one_sales) AS expected_one,max(top_five_sales) AS expected_five
 FROM account_year_summary GROUP BY year
), bridge_components AS (
 SELECT current_year,sum(component_amount) AS effects,max(company_sales_change) AS change
 FROM price_quantity_bridge GROUP BY current_year
)
SELECT 'analysis' AS phase,v.check_name,v.actual_value,v.expected_rule,
       CASE WHEN v.passed THEN 'PASS' ELSE 'FAIL' END AS status,'critical' AS severity
FROM (SELECT count(*) AS rows,sum(reported_sales_amount) AS sales FROM analysis_lines) l
CROSS JOIN (SELECT count(*) AS rows,sum(l.reported_sales_amount) AS sales
            FROM analysis_lines l JOIN item_metadata m USING(item_code)) j
CROSS JOIN LATERAL (VALUES
 ('metadata_join_rows',j.rows::VARCHAR,l.rows::VARCHAR,j.rows=l.rows),
 ('metadata_join_sales',j.sales::VARCHAR,l.sales::VARCHAR,j.sales=l.sales),
 ('company_year_totals',(SELECT sum(company_sales) FROM company_year)::VARCHAR,l.sales::VARCHAR,(SELECT sum(company_sales) FROM company_year)=l.sales),
 ('company_month_totals',(SELECT sum(reported_sales_amount) FROM company_month)::VARCHAR,l.sales::VARCHAR,(SELECT sum(reported_sales_amount) FROM company_month)=l.sales),
 ('full_contribution_reconciliation',(SELECT count(*) FROM driver_full WHERE change<>company_change OR prior_sales<>company_prior OR current_sales<>company_current)::VARCHAR,'0 failed dimension/comparison totals',NOT EXISTS(SELECT 1 FROM driver_full WHERE change<>company_change OR prior_sales<>company_prior OR current_sales<>company_current)),
 ('full_contribution_comparisons',(SELECT count(*) FROM driver_full)::VARCHAR,'12 (4 dimensions x 3 comparisons)',(SELECT count(*) FROM driver_full)=12),
 ('ranked_other_reconciliation',(SELECT count(*) FROM driver_ranked WHERE change<>company_change OR prior_sales<>company_prior OR current_sales<>company_current)::VARCHAR,'0 failed dimension/comparison totals',NOT EXISTS(SELECT 1 FROM driver_ranked WHERE change<>company_change OR prior_sales<>company_prior OR current_sales<>company_current)),
 ('ranked_comparison_count',(SELECT count(*) FROM driver_ranked)::VARCHAR,'12',(SELECT count(*) FROM driver_ranked)=12),
 ('customer_thickness_changes_reconcile',(SELECT count(*) FROM (SELECT current_year,sum(sales_change) AS change FROM customer_thickness_changes GROUP BY current_year) t JOIN annual_comparisons a USING(current_year) WHERE t.change<>a.company_sales_change)::VARCHAR,'0 failed annual joint-breakdown totals',NOT EXISTS(SELECT 1 FROM (SELECT current_year,sum(sales_change) AS change FROM customer_thickness_changes GROUP BY current_year) t JOIN annual_comparisons a USING(current_year) WHERE t.change<>a.company_sales_change)),
 ('customer_thickness_keys_unique',(SELECT count(*)-count(DISTINCT (current_year,customer_code,thickness_code)) FROM customer_thickness_changes)::VARCHAR,'0',(SELECT count(*)=count(DISTINCT (current_year,customer_code,thickness_code)) FROM customer_thickness_changes)),
 ('full_driver_keys_unique',(SELECT count(*)-count(DISTINCT (current_year,contributor_type,contributor_key)) FROM revenue_drivers_full)::VARCHAR,'0',(SELECT count(*)=count(DISTINCT (current_year,contributor_type,contributor_key)) FROM revenue_drivers_full)),
 ('ranked_driver_keys_unique',(SELECT count(*)-count(DISTINCT (current_year,contributor_type,contributor_key)) FROM revenue_drivers)::VARCHAR,'0',(SELECT count(*)=count(DISTINCT (current_year,contributor_type,contributor_key)) FROM revenue_drivers)),
 ('matched_item_effects',(SELECT max(abs(quantity_effect+realized_price_effect-sales_change)) FROM bridge_item_detail WHERE eligibility='matched')::VARCHAR,'<= 0.01 per matched key',(SELECT max(abs(quantity_effect+realized_price_effect-sales_change))<=0.01 FROM bridge_item_detail WHERE eligibility='matched')),
 ('full_bridge_all_scenarios',(SELECT max(abs(reconciliation_residual)) FROM bridge_summary)::VARCHAR,'<= 0.01 per comparison/scenario',(SELECT max(abs(reconciliation_residual))<=0.01 FROM bridge_summary)),
 ('bridge_prior_current_coverage',(SELECT count(*) FROM bridge_summary WHERE matched_prior_coverage NOT BETWEEN 0 AND 1 OR matched_current_coverage NOT BETWEEN 0 AND 1)::VARCHAR,'0 invalid coverage values',NOT EXISTS(SELECT 1 FROM bridge_summary WHERE matched_prior_coverage NOT BETWEEN 0 AND 1 OR matched_current_coverage NOT BETWEEN 0 AND 1)),
 ('bridge_included_sales',(SELECT count(*) FROM bridge_summary WHERE included_prior_sales<>company_prior_sales OR included_current_sales<>company_current_sales)::VARCHAR,'0 differences; omitted zero-sales lines carry zero sales',NOT EXISTS(SELECT 1 FROM bridge_summary WHERE included_prior_sales<>company_prior_sales OR included_current_sales<>company_current_sales)),
 ('bridge_item_keys_unique',(SELECT count(*)-count(DISTINCT (scenario,current_year,bridge_key)) FROM bridge_item_detail)::VARCHAR,'0',(SELECT count(*)=count(DISTINCT (scenario,current_year,bridge_key)) FROM bridge_item_detail)),
 ('tableau_bridge_component_sum',(SELECT max(abs(effects-change)) FROM bridge_components)::VARCHAR,'<= 0.01',(SELECT max(abs(effects-change))<=0.01 FROM bridge_components)),
 ('tableau_bridge_grain',(SELECT count(*) FROM price_quantity_bridge)::VARCHAR,'15 (5 components x 3 comparisons)',(SELECT count(*) FROM price_quantity_bridge)=15),
 ('account_summary_keys',(SELECT count(*)-count(DISTINCT (year,customer_code)) FROM account_year_summary)::VARCHAR,'0',(SELECT count(*)=count(DISTINCT (year,customer_code)) FROM account_year_summary)),
 ('account_grid_rows',(SELECT count(*) FROM account_year_summary)::VARCHAR,((SELECT count(*) FROM company_year)*(SELECT count(DISTINCT customer_code) FROM analysis_lines))::VARCHAR,(SELECT count(*) FROM account_year_summary)=(SELECT count(*) FROM company_year)*(SELECT count(DISTINCT customer_code) FROM analysis_lines)),
 ('account_sales_and_shares',(SELECT count(*) FROM account WHERE sales<>company_sales OR abs(shares-1)>0.000000001)::VARCHAR,'0',NOT EXISTS(SELECT 1 FROM account WHERE sales<>company_sales OR abs(shares-1)>0.000000001)),
 ('concentration_numerators',(SELECT count(*) FROM account WHERE top_one<>expected_one OR top_five<>expected_five)::VARCHAR,'0',NOT EXISTS(SELECT 1 FROM account WHERE top_one<>expected_one OR top_five<>expected_five)),
 ('priority_rule',(SELECT count(*) FROM account_year_summary WHERE is_priority_review IS DISTINCT FROM coalesce(sales_change<0 AND prior_revenue_rank<=10,false))::VARCHAR,'0',NOT EXISTS(SELECT 1 FROM account_year_summary WHERE is_priority_review IS DISTINCT FROM coalesce(sales_change<0 AND prior_revenue_rank<=10,false))),
 ('percentage_zero_missing_baseline',(SELECT count(*) FROM account_year_summary WHERE (prior_sales IS NULL OR prior_sales=0) AND sales_change_ratio IS NOT NULL)::VARCHAR,'0',NOT EXISTS(SELECT 1 FROM account_year_summary WHERE (prior_sales IS NULL OR prior_sales=0) AND sales_change_ratio IS NOT NULL))
) v(check_name,actual_value,expected_rule,passed)
UNION ALL
SELECT 'interpretation','quantity_units_unverified','No source unit-of-measure field',
       'Conditional within-item bridge; no cross-item quantity or blended-price KPI',
       'LIMITATION','interpretation';

-- @phase exports
CREATE OR REPLACE TEMP VIEW export_checks AS
WITH line_diff AS (
 SELECT count(*) AS differences FROM (
   (SELECT * FROM sales_lines EXCEPT ALL SELECT * FROM exported_sales_lines)
   UNION ALL
   (SELECT * FROM exported_sales_lines EXCEPT ALL SELECT * FROM sales_lines)
 ) d
)
SELECT 'exports' AS phase,v.check_name,v.actual_value,v.expected_rule,
       CASE WHEN v.passed THEN 'PASS' ELSE 'FAIL' END AS status,'critical' AS severity
FROM line_diff l CROSS JOIN LATERAL (VALUES
 ('sales_lines_export_exact',l.differences::VARCHAR,'0 row/value differences after typed round trip',l.differences=0),
 ('revenue_driver_export_exact',(SELECT count(*) FROM ((SELECT * FROM revenue_drivers EXCEPT ALL SELECT * FROM exported_revenue_drivers) UNION ALL (SELECT * FROM exported_revenue_drivers EXCEPT ALL SELECT * FROM revenue_drivers)) d)::VARCHAR,'0 typed row/value differences',(SELECT count(*)=0 FROM ((SELECT * FROM revenue_drivers EXCEPT ALL SELECT * FROM exported_revenue_drivers) UNION ALL (SELECT * FROM exported_revenue_drivers EXCEPT ALL SELECT * FROM revenue_drivers)) d)),
 ('price_quantity_export_exact',(SELECT count(*) FROM ((SELECT * FROM price_quantity_bridge EXCEPT ALL SELECT * FROM exported_price_quantity_bridge) UNION ALL (SELECT * FROM exported_price_quantity_bridge EXCEPT ALL SELECT * FROM price_quantity_bridge)) d)::VARCHAR,'0 typed row/value differences',(SELECT count(*)=0 FROM ((SELECT * FROM price_quantity_bridge EXCEPT ALL SELECT * FROM exported_price_quantity_bridge) UNION ALL (SELECT * FROM exported_price_quantity_bridge EXCEPT ALL SELECT * FROM price_quantity_bridge)) d)),
 ('account_summary_export_exact',(SELECT count(*) FROM ((SELECT * FROM account_year_summary EXCEPT ALL SELECT * FROM exported_account_year_summary) UNION ALL (SELECT * FROM exported_account_year_summary EXCEPT ALL SELECT * FROM account_year_summary)) d)::VARCHAR,'0 typed row/value differences',(SELECT count(*)=0 FROM ((SELECT * FROM account_year_summary EXCEPT ALL SELECT * FROM exported_account_year_summary) UNION ALL (SELECT * FROM exported_account_year_summary EXCEPT ALL SELECT * FROM account_year_summary)) d))
) v(check_name,actual_value,expected_rule,passed);
