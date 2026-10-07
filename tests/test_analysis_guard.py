"""Fail-closed integration tests on disposable copies, never analytical inputs."""
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
EXPORTS=['sales_lines','revenue_drivers','price_quantity_bridge','account_year_summary']


class AnalysisGuard(unittest.TestCase):
    def scenario(self, corruption):
        with tempfile.TemporaryDirectory(prefix='analysis-guard-') as temporary:
            root=Path(temporary)
            shutil.copytree(ROOT/'sql',root/'sql')
            shutil.copytree(ROOT/'data/processed',root/'data/processed')
            exports=root/'data/exports'
            exports.mkdir()
            for name in EXPORTS:(exports/(name+'.csv')).write_text('previous checked output\n')
            prepared=root/'data/processed/sales_lines.csv'
            if corruption=='checksum':
                with prepared.open('a') as stream:stream.write('\n')
            else:
                # Keep sales, counts and IDs unchanged; change one line price.
                # Re-sign only the disposable preparation audit to reach the
                # SQL arithmetic gate instead of failing the byte guard first.
                with prepared.open(newline='') as stream:
                    reader=csv.DictReader(stream);fields=reader.fieldnames;rows=list(reader)
                rows[0]['sales_price']=str(float(rows[0]['sales_price'])+1)
                with prepared.open('w',newline='') as stream:
                    writer=csv.DictWriter(stream,fieldnames=fields,lineterminator='\n');writer.writeheader();writer.writerows(rows)
                audit_path=root/'data/processed/ingest_audit.json'
                audit=json.loads(audit_path.read_text())
                audit['outputs']['prepared_csv_sha256']=hashlib.sha256(prepared.read_bytes()).hexdigest()
                audit_path.write_text(json.dumps(audit))
            result=subprocess.run([sys.executable,str(ROOT/'src/run_analysis.py'),'--project-root',str(root)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(json.loads((root/'reports/analysis_run.json').read_text())['status'],'FAIL')
            with (root/'reports/quality_checks.csv').open(newline='') as stream:checks=list(csv.DictReader(stream))
            expected='validated_prepared_checksum' if corruption=='checksum' else 'sales_price_quantity_arithmetic'
            self.assertEqual(next(c['status'] for c in checks if c['check_name']==expected),'FAIL')
            for name in EXPORTS:self.assertEqual((exports/(name+'.csv')).read_text(),'previous checked output\n')
            self.assertFalse((root/'data/local/manufacturing.duckdb').exists())

    def test_changed_prepared_bytes_block_publication(self):
        self.scenario('checksum')

    def test_sql_arithmetic_failure_blocks_publication(self):
        self.scenario('arithmetic')


if __name__=='__main__':unittest.main()
