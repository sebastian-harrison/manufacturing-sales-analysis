-- Conditional arithmetic bridge: quantity basis is assumed constant within an
-- item code, NOT verified from UOM metadata. All lines stay in the base case.
-- Sensitivities test description ambiguity, zero-sales quantity and account mix.
CREATE OR REPLACE VIEW bridge_key_year AS
WITH scenarios AS (
    SELECT 'base_item' AS scenario,l.* FROM analysis_lines l
    UNION ALL SELECT 'exclude_description_variants',l.* FROM analysis_lines l
    UNION ALL SELECT 'positive_sales_lines',l.* FROM analysis_lines l WHERE reported_sales_amount>0
    UNION ALL SELECT 'item_customer_pair',l.* FROM analysis_lines l
)
SELECT s.scenario,s.document_year AS year,
       CASE WHEN scenario='item_customer_pair' THEN s.item_code || ':' || s.customer_code
            ELSE s.item_code END AS bridge_key,
       s.item_code,sum(s.reported_quantity)::DECIMAL(28,4) AS quantity,
       sum(s.reported_sales_amount)::DECIMAL(28,2) AS sales,
       count(*) AS source_lines,
       bool_and(m.structured_specs_consistent) AND
       NOT (scenario='exclude_description_variants' AND max(m.description_variants)>1) AS key_accepted
FROM scenarios s JOIN item_metadata m USING(item_code)
GROUP BY s.scenario,s.document_year,s.item_code,bridge_key;

CREATE OR REPLACE VIEW bridge_item_detail AS
WITH pairs AS (
    SELECT coalesce(p.scenario,c.scenario) AS scenario,
           coalesce(p.year,c.year-1) AS prior_year,coalesce(c.year,p.year+1) AS current_year,
           coalesce(p.bridge_key,c.bridge_key) AS bridge_key,coalesce(p.item_code,c.item_code) AS item_code,
           p.source_lines IS NOT NULL AS observed_prior,c.source_lines IS NOT NULL AS observed_current,
           coalesce(p.sales,0) AS prior_sales,coalesce(c.sales,0) AS current_sales,
           coalesce(p.quantity,0)::DECIMAL(28,4) AS prior_quantity,
           coalesce(c.quantity,0)::DECIMAL(28,4) AS current_quantity,
           coalesce(p.key_accepted,true) AND coalesce(c.key_accepted,true) AS key_accepted
    FROM bridge_key_year p FULL OUTER JOIN bridge_key_year c
      ON c.year=p.year+1 AND c.scenario=p.scenario AND c.bridge_key=p.bridge_key
), prices AS (
    SELECT p.*,a.comparison_label,current_sales-prior_sales AS sales_change,
           prior_sales/nullif(prior_quantity,0) AS prior_realized_price,
           current_sales/nullif(current_quantity,0) AS current_realized_price,
           CASE WHEN NOT observed_prior THEN 'current_only'
                WHEN NOT observed_current THEN 'prior_only'
                WHEN prior_quantity<=0 OR current_quantity<=0 OR NOT key_accepted THEN 'unresolved'
                ELSE 'matched' END AS eligibility
    FROM pairs p JOIN annual_comparisons a USING(prior_year,current_year)
)
SELECT *,
    CASE WHEN eligibility='matched'
         THEN ((current_quantity-prior_quantity)*prior_realized_price)::DECIMAL(28,8)
         ELSE 0::DECIMAL(28,8) END AS quantity_effect,
    CASE WHEN eligibility='matched'
         THEN ((current_realized_price-prior_realized_price)*current_quantity)::DECIMAL(28,8)
         ELSE 0::DECIMAL(28,8) END AS realized_price_effect
FROM prices;

-- Ratios/division are DOUBLE in DuckDB. Monetary effects are retained at eight
-- decimal places; any residual is measured and must stay within one cent.
-- No plug/balancing effect is added to force a reconciliation.
CREATE OR REPLACE VIEW bridge_summary AS
WITH components AS (
    SELECT scenario,prior_year,current_year,comparison_label,
       count(*) FILTER(WHERE eligibility='matched') AS matched_key_count,
       count(*) FILTER(WHERE eligibility='current_only') AS current_only_key_count,
       count(*) FILTER(WHERE eligibility='prior_only') AS prior_only_key_count,
       count(*) FILTER(WHERE eligibility='unresolved') AS unresolved_key_count,
       coalesce(sum(prior_sales) FILTER(WHERE eligibility='matched'),0) AS matched_prior_sales,
       coalesce(sum(current_sales) FILTER(WHERE eligibility='matched'),0) AS matched_current_sales,
       sum(quantity_effect) AS quantity_effect,sum(realized_price_effect) AS realized_price_effect,
       coalesce(sum(current_sales) FILTER(WHERE eligibility='current_only'),0) AS current_only_sales,
       -coalesce(sum(prior_sales) FILTER(WHERE eligibility='prior_only'),0) AS prior_only_sales_effect,
       coalesce(sum(current_sales) FILTER(WHERE eligibility='unresolved'),0) AS unresolved_current_sales,
       coalesce(sum(prior_sales) FILTER(WHERE eligibility='unresolved'),0) AS unresolved_prior_sales,
       coalesce(sum(sales_change) FILTER(WHERE eligibility='unresolved'),0) AS unresolved_sales_change,
       sum(prior_sales) AS included_prior_sales,sum(current_sales) AS included_current_sales
    FROM bridge_item_detail GROUP BY ALL
)
SELECT b.*,a.company_prior_sales,a.company_current_sales,a.company_sales_change,
       matched_prior_sales/nullif(a.company_prior_sales,0) AS matched_prior_coverage,
       matched_current_sales/nullif(a.company_current_sales,0) AS matched_current_coverage,
       a.company_prior_sales-included_prior_sales AS excluded_prior_sales,
       a.company_current_sales-included_current_sales AS excluded_current_sales,
       quantity_effect+realized_price_effect+current_only_sales+prior_only_sales_effect+
           unresolved_sales_change AS bridge_component_sum,
       quantity_effect+realized_price_effect+current_only_sales+prior_only_sales_effect+
           unresolved_sales_change-a.company_sales_change AS reconciliation_residual,
       'Conditional: reported quantity basis assumed constant within each item code; source units unverified' AS bridge_basis
FROM components b JOIN annual_comparisons a USING(prior_year,current_year,comparison_label);

CREATE OR REPLACE VIEW price_quantity_bridge AS
SELECT b.prior_year,b.current_year,b.comparison_label,
       c.component_order,c.component_code,c.component_label,c.component_amount,
       b.company_prior_sales,b.company_current_sales,b.company_sales_change,
       b.matched_key_count AS matched_item_count,b.current_only_key_count AS current_only_item_count,
       b.prior_only_key_count AS prior_only_item_count,b.unresolved_key_count AS unresolved_item_count,
       b.matched_prior_sales,b.matched_current_sales,b.matched_prior_coverage,b.matched_current_coverage,
       b.unresolved_prior_sales,b.unresolved_current_sales,b.excluded_prior_sales,b.excluded_current_sales,
       b.reconciliation_residual,b.bridge_basis
FROM bridge_summary b CROSS JOIN LATERAL (
    VALUES
      (1,'matched_quantity','Matched-item quantity effect',b.quantity_effect::DECIMAL(28,8)),
      (2,'matched_realized_price','Matched-item realized-price effect',b.realized_price_effect::DECIMAL(28,8)),
      (3,'current_only','Current-only item sales',b.current_only_sales::DECIMAL(28,8)),
      (4,'prior_only','Prior-only item sales (negative)',b.prior_only_sales_effect::DECIMAL(28,8)),
      (5,'unresolved','Unresolved item sales change',b.unresolved_sales_change::DECIMAL(28,8))
) c(component_order,component_code,component_label,component_amount)
WHERE b.scenario='base_item';
