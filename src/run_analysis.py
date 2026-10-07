"""Execute reviewable DuckDB SQL, gate exports on checks, and save evidence.

Business calculations live in sql/*.sql. Python handles paths, source controls,
ordered execution, typed CSV round trips and publication of checked outputs.
"""
from __future__ import annotations

import argparse
import csv
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import sys
import tempfile

import duckdb

ROOT = Path(__file__).resolve().parents[1]
EXPORT_VIEWS = {
    "sales_lines": "source_row_id",
    "revenue_drivers": "current_year,contributor_type,display_order",
    "price_quantity_bridge": "current_year,component_order",
    "account_year_summary": "year,customer_code",
}
REPORT_QUERIES = {
    "company_year": "SELECT * FROM company_year ORDER BY year",
    "company_month": "SELECT * FROM company_month ORDER BY month_start",
    "annual_comparisons": "SELECT * FROM annual_comparisons ORDER BY current_year",
    "revenue_driver_details": "SELECT * FROM revenue_drivers_full ORDER BY current_year,contributor_type,loss_rank",
    "decline_distribution": "SELECT * FROM decline_distribution ORDER BY current_year,contributor_type",
    "customer_thickness_changes": "SELECT * FROM customer_thickness_changes ORDER BY current_year,thickness_code,sales_change,customer_code",
    "period_coverage_diagnostic": "SELECT * FROM period_coverage_diagnostic ORDER BY year",
    "bridge_item_details": "SELECT * FROM bridge_item_detail WHERE scenario='base_item' ORDER BY current_year,bridge_key",
    "bridge_sensitivity": "SELECT * FROM bridge_summary ORDER BY current_year,scenario",
    "concentration_year": "SELECT * FROM concentration_year ORDER BY year",
    "concentration_fixed_cohort": "SELECT * FROM concentration_fixed_cohort ORDER BY year",
    "account_review_priorities": "SELECT year,prior_year,comparison_label,priority_review_rank,customer_code,customer_display_name,prior_sales,current_sales,sales_change,sales_change_ratio,prior_revenue_rank,revenue_rank,prior_revenue_share,revenue_share,contribution_to_net_change_ratio,comparison_activity_status FROM account_review_priorities ORDER BY year,priority_review_rank",
    "largest_account_losses": "SELECT year,prior_year,comparison_label,all_account_loss_rank,customer_code,customer_display_name,prior_sales,current_sales,sales_change,sales_change_ratio,prior_revenue_rank,is_priority_review,contribution_to_net_change_ratio,comparison_activity_status FROM account_year_summary WHERE sales_change<0 AND all_account_loss_rank<=15 ORDER BY year,all_account_loss_rank",
    "item_bridge_review": "SELECT * FROM item_metadata WHERE description_variants>1 OR NOT structured_specs_consistent ORDER BY item_code",
}


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def render_sql(path, substitutions):
    text = path.read_text()
    for key,value in substitutions.items():
        text = text.replace("{{"+key+"}}", literal(value))
    if re.search(r"\{\{\w+\}\}", text):
        raise ValueError(f"Unresolved SQL path in {path.name}")
    return text


def query_rows(connection, query):
    result = connection.execute(query)
    fields = [v[0] for v in result.description]
    return [dict(zip(fields,row)) for row in result.fetchall()]


def write_checks(path, checks):
    with path.open("w",newline="") as stream:
        writer = csv.DictWriter(stream,fieldnames=["phase","check_name","actual_value","expected_rule","status","severity"],lineterminator="\n")
        writer.writeheader()
        writer.writerows(checks)


def run(args):
    root=args.project_root.resolve()
    reports=root/"reports"
    local=root/"data/local"
    exports=root/"data/exports"
    for path in [reports,local,exports]: path.mkdir(parents=True,exist_ok=True)
    audit_path=root/"data/processed/ingest_audit.json"
    prepared=root/"data/processed/sales_lines.csv"
    audit=json.loads(audit_path.read_text())
    checks=[]
    status={"stage":2,"status":"RUNNING","runtime":{"python":platform.python_version(),"duckdb":duckdb.__version__},
            "prepared_sha256":sha256(prepared),"sql_sha256":{p.name:sha256(p) for p in sorted((root/"sql").glob('*.sql'))}}
    try:
        checks.append(dict(phase='ingestion',check_name='stage1_preparation_passed',actual_value=audit['pipeline_status'],
            expected_rule='PASS',status='PASS' if audit['pipeline_status']=='PASS' else 'FAIL',severity='critical'))
        checks.append(dict(phase='ingestion',check_name='validated_prepared_checksum',actual_value=status['prepared_sha256'],
            expected_rule=audit['outputs']['prepared_csv_sha256'],
            status='PASS' if status['prepared_sha256']==audit['outputs']['prepared_csv_sha256'] else 'FAIL',severity='critical'))
        write_checks(reports/'quality_checks.csv',checks)
        if any(c['status']=='FAIL' for c in checks):
            raise ValueError("Prepared bytes or Stage 1 status do not match the validated audit")
        phases=re.split(r"(?m)^-- @phase (\w+)\s*$",(root/'sql/02_quality_checks.sql').read_text())
        phase_sql=dict(zip(phases[1::2],phases[2::2]))
        with tempfile.TemporaryDirectory(prefix='analysis-',dir=local) as temporary:
            temp=Path(temporary)
            database=temp/'manufacturing.duckdb'
            with duckdb.connect(str(database),config={'threads':1}) as connection:
                connection.execute("CREATE TABLE ingest_controls(source_rows BIGINT,source_sales DECIMAL(20,2),primary_rows BIGINT,primary_customers INTEGER,primary_items INTEGER,corrected_dates BIGINT)")
                counts=audit['counts']
                connection.execute("INSERT INTO ingest_controls VALUES (?,?,?,?,?,?)",[
                    audit['source']['data_rows'],Decimal(audit['reconciliation']['source_sales']),counts['primary_rows'],
                    counts['primary_customer_codes'],counts['primary_item_codes'],audit['dates']['correction_count']])
                substitutions={'prepared_path':prepared}
                connection.execute(render_sql(root/'sql/01_load.sql',substitutions))
                def quality_phase(name,view):
                    connection.execute(phase_sql[name])
                    new=query_rows(connection,f"SELECT * FROM {view} ORDER BY check_name")
                    checks.extend(new)
                    write_checks(reports/'quality_checks.csv',checks)
                    if any(v['status']=='FAIL' and v['severity']=='critical' for v in new):
                        raise ValueError(f"Critical {name} checks failed; final exports not published")
                quality_phase('ingestion','ingestion_checks')
                for name in ['03_revenue_drivers.sql','04_price_quantity.sql','05_account_performance.sql']:
                    connection.execute((root/'sql'/name).read_text())
                quality_phase('analysis','analysis_checks')
                for view in EXPORT_VIEWS:
                    substitutions[view+'_path']=temp/(view+'.csv')
                connection.execute(render_sql(root/'sql/06_exports.sql',substitutions))
                schemas={}
                for view in EXPORT_VIEWS:
                    columns=connection.execute(f'DESCRIBE SELECT * FROM {view}').fetchall()
                    schemas[view]=[{"name":c[0],"type":c[1]} for c in columns]
                    # Read exported bytes with the exact owning schema. This tests
                    # serialized dates, identifiers, decimals, ratios and blanks.
                    column_map='{'+','.join(literal(c[0])+': '+literal(c[1]) for c in columns)+'}'
                    connection.execute(f"CREATE TEMP TABLE exported_{view} AS SELECT * FROM read_csv({literal(temp/(view+'.csv'))},header=true,columns={column_map},force_not_null=['date_issue'])" if view=='sales_lines' else
                        f"CREATE TEMP TABLE exported_{view} AS SELECT * FROM read_csv({literal(temp/(view+'.csv'))},header=true,columns={column_map})")
                quality_phase('exports','export_checks')
                for name,query in REPORT_QUERIES.items():
                    connection.execute(f"COPY ({query}) TO {literal(temp/(name+'.csv'))} (HEADER,DELIMITER ',',DATEFORMAT '%Y-%m-%d')")
                status['export_schemas']=schemas
                status['exports']={view:dict(rows=connection.execute(f'SELECT count(*) FROM {view}').fetchone()[0],
                    sha256=sha256(temp/(view+'.csv'))) for view in EXPORT_VIEWS}
            # Publish only after SQL and typed round-trip checks have passed.
            os.replace(database,local/'manufacturing.duckdb')
            for view in EXPORT_VIEWS: os.replace(temp/(view+'.csv'),exports/(view+'.csv'))
            for name in REPORT_QUERIES: os.replace(temp/(name+'.csv'),reports/(name+'.csv'))
        status.update(status='PASS',critical_checks=sum(v['severity']=='critical' for v in checks),
            critical_failures=sum(v['status']=='FAIL' and v['severity']=='critical' for v in checks),
            interpretation_limits=sum(v['status']=='LIMITATION' for v in checks))
        (reports/'analysis_run.json').write_text(json.dumps(status,indent=2,sort_keys=True)+'\n')
        print(json.dumps({'stage':2,'status':'PASS','duckdb':duckdb.__version__,
            'critical_checks':status['critical_checks'],'interpretation_limits':status['interpretation_limits'],
            'export_rows':{k:v['rows'] for k,v in status['exports'].items()}},indent=2))
        return 0
    except Exception as error:
        status.update(status='FAIL',error=str(error))
        (reports/'analysis_run.json').write_text(json.dumps(status,indent=2,sort_keys=True)+'\n')
        if checks:write_checks(reports/'quality_checks.csv',checks)
        print(f'Stage 2 FAILED: {error}',file=sys.stderr)
        return 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-root',type=Path,default=ROOT)
    sys.exit(run(parser.parse_args()))
