-- Exactly four stable Tableau sources. Keep differing grains separate.
-- Every company total, share, coverage and count repeated across rows is
-- non-additive: use MIN/MAX at its period/comparison grain, never SUM.
COPY (SELECT * FROM sales_lines ORDER BY source_row_id)
TO {{sales_lines_path}} (HEADER, DELIMITER ',', DATEFORMAT '%Y-%m-%d');
COPY (SELECT * FROM revenue_drivers ORDER BY current_year,contributor_type,display_order)
TO {{revenue_drivers_path}} (HEADER, DELIMITER ',');
COPY (SELECT * FROM price_quantity_bridge ORDER BY current_year,component_order)
TO {{price_quantity_bridge_path}} (HEADER, DELIMITER ',');
COPY (SELECT * FROM account_year_summary ORDER BY year,customer_code)
TO {{account_year_summary_path}} (HEADER, DELIMITER ',', DATEFORMAT '%Y-%m-%d');
