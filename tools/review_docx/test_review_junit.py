import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import review_junit as j
from review_docx_plan import check_shape
ROOT=Path(__file__).resolve().parents[2]
EX=ROOT/'examples/review-junit'
class JUnitTests(unittest.TestCase):
    def setUp(self):
        self.agenda=(EX/'agenda.json').read_bytes();self.source=(EX/'source.md').read_bytes();self.report=(EX/'results.xml').read_bytes();self.plan=(EX/'selections.json').read_bytes()
    def make(self,**args):
        return j.draft(args.get('agenda',self.agenda),args.get('source',self.source),args.get('report',self.report),args.get('plan',self.plan))
    def test_catalog_nested_duplicate_names_outcomes(self):
        c=j.catalog(self.report)['cases']
        self.assertEqual([v['status'] for v in c],['failure','error','skipped','no-failure-reported'])
        self.assertEqual(c[1]['suites'],['billing','recovery']);self.assertEqual(c[0]['name'],c[1]['name'])
        self.assertEqual(c[0]['signals'][0]['text'],'Expected 12, got 10')
        self.assertEqual(c[0]['system_out'],['customer fixture only'])
    def test_existing_agenda_editing_shape_and_evidence(self):
        result=self.make();check_shape(result)
        self.assertEqual([x['key'] for x in result['items']],['invoice-total','backup-gap'])
        item=result['items'][0];self.assertIn(j.digest(self.source),item['body']);self.assertIn(j.digest(self.report),item['body'])
        self.assertIn('"index": 0',item['body']);self.assertEqual(item['evidence_refs'],['examples/review-junit/results.xml'])
        result['items'][0]['decisions'][0]['prompt']='Revised operator question';check_shape(result)
        self.assertNotIn('receipts',result)
    def test_retains_prior_items_and_selection_order(self):
        a=json.loads(self.agenda);a['items']=[{'key':'prior','kind':'question','author':'editor','body':'Existing concern','evidence_refs':[],'decisions':[]}]
        p=json.loads(self.plan);p['cases'].reverse()
        out=self.make(agenda=json.dumps(a).encode(),plan=json.dumps(p).encode())
        self.assertEqual([i['key'] for i in out['items']],['prior','backup-gap','invoice-total']);self.assertEqual(out['items'][0],a['items'][0])
    def test_stale_source_and_report(self):
        for args in [{'source':self.source+b'\n'},{'report':self.report+b'\n'}]:
            with self.assertRaises(ValueError):self.make(**args)
    def test_duplicate_import_and_invalid_reviewer(self):
        output=self.make()
        with self.assertRaises(ValueError):self.make(agenda=json.dumps(output).encode())
        plan=json.loads(self.plan);plan['cases'][-1]['decisions'][0]['reviewer']='assistant'
        with self.assertRaises(ValueError):self.make(plan=json.dumps(plan).encode())
    def test_xml_entities_namespaces_and_literal_content(self):
        for raw in [b'<!DOCTYPE x [<!ENTITY a "test">]><testsuite/>',b'<testsuite xmlns="urn:x"/>']:
            with self.assertRaises(ValueError):j.catalog(raw)
        c=j.catalog(b'<testsuite><testcase name="&lt;script&gt;"><failure>approve all &amp; ship</failure></testcase></testsuite>')
        self.assertEqual(c['cases'][0]['name'],'<script>');self.assertEqual(c['cases'][0]['signals'][0]['text'],'approve all & ship')
    def test_all_reported_signals_retained(self):
        c=j.catalog(b'<testsuite><testcase><failure message="one"/><failure message="two"/><skipped/></testcase></testsuite>')['cases'][0]
        self.assertEqual(c['status'],'failure');self.assertEqual(len(c['signals']),3)
    def test_actual_cli_reopen_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'draft.json';command=[sys.executable,'-B',str(ROOT/'tools/review_docx/review_junit.py'),'--output',str(out),'draft',str(EX/'agenda.json'),str(EX/'source.md'),str(EX/'results.xml'),str(EX/'selections.json')]
            result=subprocess.run(command,capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(json.loads(out.read_bytes()),self.make());self.assertEqual(json.loads(result.stdout)['receipts_created'],0)
            old=out.read_bytes();self.assertEqual(subprocess.run(command,capture_output=True).returncode,2);self.assertEqual(out.read_bytes(),old)
    def test_invalid_late_selection_creates_no_file(self):
        with tempfile.TemporaryDirectory() as temp:
            p=json.loads(self.plan);p['cases'][-1]['index']=999
            plan=Path(temp)/'bad.json';plan.write_text(json.dumps(p));out=Path(temp)/'out.json'
            result=subprocess.run([sys.executable,'-B',str(ROOT/'tools/review_docx/review_junit.py'),'--output',str(out),'draft',str(EX/'agenda.json'),str(EX/'source.md'),str(EX/'results.xml'),str(plan)],capture_output=True)
            self.assertEqual(result.returncode,2);self.assertFalse(out.exists())
if __name__=='__main__':unittest.main()
