-- Preserve source-line grain and exact reported amounts; use explicit types,
-- not CSV inference. Ingest controls are supplied from the validated Stage 1 audit.
CREATE OR REPLACE TEMP VIEW prepared_text AS
SELECT * FROM read_csv({{prepared_path}}, header=true, all_varchar=true);

CREATE OR REPLACE TABLE sales_lines AS
SELECT
    source_row_id::INTEGER AS source_row_id,
    source_line_number, coil_pattern, product_group, product, document_number,
    source_document_date, source_date_kind, source_date_number_format,
    source_week_label, source_month::INTEGER AS source_month,
    customer_group, customer_code, customer_name, item_code, item_description,
    thickness_code, width::DECIMAL(18,4) AS width, source_colour, batch_number,
    item_cost::DECIMAL(18,4) AS item_cost,
    sales_price::DECIMAL(18,4) AS sales_price,
    reported_quantity::DECIMAL(18,4) AS reported_quantity,
    vat_value::DECIMAL(18,4) AS vat_value,
    reported_sales_amount::DECIMAL(20,2) AS reported_sales_amount,
    document_date::DATE AS document_date,
    document_year::INTEGER AS document_year,
    document_month::INTEGER AS document_month,
    document_day::INTEGER AS document_day,
    is_primary_window::BOOLEAN AS is_primary_window,
    date_corrected::BOOLEAN AS date_corrected,
    date_normalization_rule, coalesce(date_issue,'') AS date_issue,
    colour, customer_display_name
FROM prepared_text;

CREATE OR REPLACE VIEW analysis_lines AS
SELECT * FROM sales_lines WHERE is_primary_window;
