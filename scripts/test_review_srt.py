"""Original SubRip intake, explicit selection and retained native workflow."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import review_srt as s
ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT/'examples/review-srt'
RAW = (EXAMPLE/'meeting.srt').read_bytes()
AGENDA = json.loads((EXAMPLE/'agenda.json').read_bytes())
PLAN = json.loads((EXAMPLE/'selection.json').read_bytes())
COMPOSER = os.environ.get('MOONCHAT_REVIEW_COMPOSER')

class SrtTests(unittest.TestCase):
    def test_original_crlf_bom_spans_duplicate_identifiers(self):
        c = s.parse_srt(RAW)
        self.assertEqual(c['source_digest'], s.common.digest(RAW))
        self.assertEqual(c['cue_count'], 3)
        self.assertEqual([v['identifier'] for v in c['cues']], ['7','7','9'])
        self.assertEqual(c['cues'][0]['source_start_byte'], 3)
        self.assertEqual(c['cues'][1]['cue_locator'], 'srt/cue/2')
        for cue in c['cues']:
            self.assertEqual(cue['cue_digest'], s.common.digest(RAW[cue['source_start_byte']:cue['source_end_byte']]))
        self.assertEqual(c['cues'][0]['text'], 'Who owns rollback?\nPlease name the owner.')
        self.assertEqual(c['cues'][1]['end_ms'], 5500)

    def test_lf_utf8_overlap_and_last_cue_without_newline(self):
        raw = '1\n00:00:01,000 --> 00:00:03,000\ncafé\n\n2\n00:00:02,000 --> 00:00:04,000\ntext'.encode()
        c = s.parse_srt(raw)
        self.assertEqual(c['cues'][0]['text'], 'café')
        self.assertEqual(c['cues'][-1]['source_end_byte'], len(raw))

    def test_explicit_selection_and_immutable_inputs(self):
        a,p=copy.deepcopy(AGENDA),copy.deepcopy(PLAN)
        c=s.import_cues(a,p,s.parse_srt(RAW))
        self.assertEqual(a,AGENDA);self.assertEqual(p,PLAN)
        self.assertEqual(c['source_digest_constraint'],s.common.digest(RAW))
        body=c['items'][0]['body']
        self.assertIn('srt/cue/2',body);self.assertNotIn('Unselected closing note',body)
        self.assertEqual(c['items'][0]['author'],'curator')

    def test_bad_selection_and_changed_source(self):
        catalog=s.parse_srt(RAW)
        for value in ([], [True], [0], [4], [1,1], '1'):
            p=copy.deepcopy(PLAN);p['items'][0]['cues']=value
            with self.assertRaises(s.common.IntakeError):s.import_cues(AGENDA,p,catalog)
        for key,value in [('author','speaker'),('kind','approval'),('note',''),('decisions',[])]:
            p=copy.deepcopy(PLAN);p['items'][0][key]=value
            with self.assertRaises(s.common.IntakeError):s.import_cues(AGENDA,p,catalog)
        with self.assertRaises(s.common.IntakeError):s.import_cues(AGENDA,PLAN,s.parse_srt(RAW+b'\r\n'))
        with self.assertRaises(s.common.IntakeError):s.import_cues({**AGENDA,'source_digest_constraint':'sha256:wrong'},PLAN,catalog)
        p=copy.deepcopy(PLAN);p['items']*=2
        with self.assertRaises(s.common.IntakeError):s.import_cues(AGENDA,p,catalog)

    def test_reject_bad_framing_timing_and_encoding(self):
        good=b'1\n00:00:01,000 --> 00:00:02,000\ntext'
        for raw in (b'',b'WEBVTT\n\n'+good,good+b'\x00',good+b'\xff',good.replace(b'\n',b'\r'),
                    good.replace(b'02,000',b'01,000'),good.replace(b'00:00:01',b'00:60:01'),
                    good.replace(b'1\n',b'word\n'),good.replace(b'\ntext',b'\n'),
                    good.replace(b' --> ',b'-->'),good.replace(b',000',b'.000'),
                    good+b'\n\n'+good.replace(b'01,000',b'00,000')):
            with self.subTest(raw=raw[:50]):
                with self.assertRaises((s.common.IntakeError,UnicodeError)):s.parse_srt(raw)

    def test_resource_bounds(self):
        for name,value in [('MAX_BYTES',1),('MAX_CUES',1)]:
            with patch.object(s,name,value):
                with self.assertRaises(s.common.IntakeError):s.parse_srt(RAW)
        with patch.object(s,'MAX_IMPORTED',1):
            with self.assertRaises(s.common.IntakeError):s.import_cues(AGENDA,PLAN,s.parse_srt(RAW))

    def test_cli_catalog_and_no_partial_failure(self):
        cmd=[sys.executable,'-B',str(ROOT/'scripts/review_srt.py'),'catalog']
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'s.srt';p.write_bytes(RAW)
            r=subprocess.run(cmd+[str(p)],capture_output=True)
            self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(r.stdout)['source_digest'],s.common.digest(RAW))
            p.write_bytes(b'bad');r=subprocess.run(cmd+[str(p)],capture_output=True)
            self.assertEqual(r.returncode,2);self.assertEqual(r.stdout,b'')

@unittest.skipUnless(COMPOSER,'set verified MOONCHAT_REVIEW_COMPOSER')
class NativeSrtTests(unittest.TestCase):
    def test_actual_preview_bundle_and_direct_stale_source_rejection(self):
        with tempfile.TemporaryDirectory() as folder:
            d=Path(folder);src=d/'original.srt';src.write_bytes(RAW)
            a=d/'agenda.json';a.write_text(json.dumps(AGENDA));p=d/'selection.json';p.write_text(json.dumps(PLAN))
            command=[sys.executable,'-B',str(ROOT/'scripts/review_srt.py')]
            outputs={}
            for mode in ('agenda','preview','bundle'):
                result=subprocess.run(command+[mode,str(a),str(src),str(p),'--composer',COMPOSER],capture_output=True)
                self.assertEqual(result.returncode,0,result.stderr);outputs[mode]=result.stdout
            bundle=json.loads(outputs['bundle'])
            self.assertEqual(bundle['source_digest'],s.common.digest(RAW))
            self.assertEqual(bundle['decision_receipts'],[])
            self.assertEqual(bundle['required_decisions'][0]['reviewer_participant_id'],'ops')
            self.assertIn('srt/cue/2',bundle['entries'][0]['body'])
            self.assertIn(b'rollback',outputs['preview'])
            self.assertEqual(src.read_bytes(),RAW)
            a.write_bytes(outputs['agenda']);src.write_bytes(RAW+b'\r\n')
            result=subprocess.run([COMPOSER,'bundle',str(a),str(src)],capture_output=True)
            self.assertNotEqual(result.returncode,0);self.assertIn(b'constraint',result.stdout+result.stderr)
            result=subprocess.run(command+['bundle',str(a),str(src),str(p),'--composer',COMPOSER],capture_output=True)
            self.assertEqual(result.returncode,2);self.assertEqual(result.stdout,b'')

if __name__=='__main__':unittest.main()
