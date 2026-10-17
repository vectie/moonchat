import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).parent))
from review_vtt import parse_vtt,make_agenda,timestamp,read_bounded
ROOT=Path(__file__).resolve().parent.parent
RAW=b'WEBVTT\r\n\r\nopening\r\n00:00.000 --> 00:02.100 align:start\r\n<v Alex>Ship the pilot.</v>\r\n\r\n00:01.000 --> 00:04.000\r\nNo rollback owner yet.\r\nSecond line.\r\n'

def selection():
    return dict(review_id='meeting',conversation_id='meeting-room',source_artifact_ref='meeting.vtt',source_revision_id='r1',recorded_at='2026-10-12T12:00:00Z',participants=[dict(participant_id='author',display_name='Fixture author',participant_kind='agent'),dict(participant_id='reviewer',display_name='Fixture reviewer',participant_kind='human')],items=[dict(key='rollback',kind='objection',author='author',body='Who will own rollback?',cues=[2,1],decisions=[dict(reviewer='reviewer',prompt='Is rollback ownership ready?')])])

class VttTests(unittest.TestCase):
    def test_multiline_overlap_identifiers_and_crlf(self):
        rows=parse_vtt(RAW); self.assertEqual(len(rows),2); self.assertEqual(rows[0]['identifier'],'opening');self.assertEqual(rows[1]['start_ms'],1000); self.assertIn('\nSecond line.',rows[1]['text'])
    def test_bom_comments_styles_regions(self):
        rows=parse_vtt(b'\xef\xbb\xbfWEBVTT title\n\nNOTE private note\nignored\n\nSTYLE\n::cue {color:red}\n\nREGION\nid:one\n\n00:00.000 --> 00:01.000\nHi\n'); self.assertEqual(len(rows),1);self.assertEqual(rows[0]['text'],'Hi')
    def test_bad_formats(self):
        for raw in [b'SRT\n',b'WEBVTT\n\n',b'WEBVTT\n00:00.000 --> 00:01.000\nhi',b'WEBVTT\n\n00:01.000 --> 00:00.000\nhi',b'WEBVTT\n\n00:00.000 --> 00:01.000\n',b'WEBVTT\n\n00:00.000 --> 00:01.000\n\x00',b'WEBVTT\n\n00:00.000 --> 00:01.000\n\xff']:
            with self.subTest(raw=raw), self.assertRaises((ValueError,UnicodeError)):parse_vtt(raw)
    def test_final_cue_payload_whitespace_is_preserved(self):
        rows=parse_vtt(b'WEBVTT\n\n00:00.000 --> 00:01.000\n  Literal payload \t\n')
        self.assertEqual(rows[0]['text'],'  Literal payload \t')
    def test_timestamp_validation(self):
        self.assertEqual(timestamp('01:02:03.004'),3723004)
        for s in ['00:60.000','1:02.000','01:00','-1:00.000']:
            with self.assertRaises(ValueError):timestamp(s)
    def test_descending_cues_refused(self):
        with self.assertRaises(ValueError):parse_vtt(RAW+b'\n00:00.500 --> 00:01.500\nBackwards\n')
    def test_size_limit(self):
        with self.assertRaisesRegex(ValueError,'2 MiB'):parse_vtt(b'x'*(2*1024*1024+1))
    def test_source_order_exact_text_and_no_decisions_inferred(self):
        s=selection(); a=make_agenda(s,parse_vtt(RAW));body=a['items'][0]['body'];self.assertLess(body.index('Cue 1'),body.index('Cue 2')); self.assertIn('<v Alex>',body);self.assertEqual(a['items'][0]['decisions'],s['items'][0]['decisions']);self.assertEqual(s['items'][0]['cues'],[2,1]);self.assertNotIn('receipts',a)
    def test_invalid_selections(self):
        for indexes in [[],[0],[3],[True],[1,1],['1']]:
            s=selection();s['items'][0]['cues']=indexes
            with self.subTest(indexes=indexes),self.assertRaises(ValueError):make_agenda(s,parse_vtt(RAW))
    def test_duplicate_keys_missing_metadata(self):
        s=selection();s['items']*=2
        with self.assertRaises(ValueError):make_agenda(s,parse_vtt(RAW))
        with self.assertRaises(ValueError):make_agenda({},parse_vtt(RAW))
    def test_bounded_read_handles_growth_after_stat(self):
        from unittest.mock import Mock
        import io
        fake=Mock();fake.stat.return_value.st_size=1;fake.open.return_value=io.BytesIO(b'x'*(2*1024*1024+2))
        with self.assertRaisesRegex(ValueError,'grew'):read_bounded(fake)
    def test_oversize_cli_stops_before_composer(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);big=p/'big.vtt';big.write_bytes(b'x'*(2*1024*1024+1))
            r=subprocess.run([sys.executable,str(ROOT/'scripts/review_vtt.py'),'bundle',str(big),'missing.json','--composer','nonexistent-composer'],capture_output=True)
            self.assertEqual(r.returncode,2);self.assertIn(b'exceeds 2 MiB',r.stderr);self.assertEqual(r.stdout,b'')
    def test_real_cli_cues_agenda_and_error(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'source.vtt').write_bytes(RAW);(p/'selection.json').write_text(json.dumps(selection()))
            for mode in ['cues','agenda']:
                r=subprocess.run([sys.executable,str(ROOT/'scripts/review_vtt.py'),mode,str(p/'source.vtt'),str(p/'selection.json')],capture_output=True);self.assertEqual(r.returncode,0,r.stderr);json.loads(r.stdout)
            r=subprocess.run([sys.executable,str(ROOT/'scripts/review_vtt.py'),'bundle',str(p/'source.vtt'),str(p/'selection.json')],capture_output=True);self.assertNotEqual(r.returncode,0);self.assertEqual((p/'source.vtt').read_bytes(),RAW)

@unittest.skipUnless(os.environ.get('MOONCHAT_COMPOSER'),'native composer not configured')
class NativeJourney(unittest.TestCase):
    def test_real_native_bundle_preview_and_refusal(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);vtt=p/'meeting.vtt';vtt.write_bytes(RAW);sel=p/'selection.json';sel.write_text(json.dumps(selection()));before=sel.read_bytes()
            def run(mode):return subprocess.run([sys.executable,str(ROOT/'scripts/review_vtt.py'),mode,str(vtt),str(sel),'--composer',os.environ['MOONCHAT_COMPOSER']],capture_output=True)
            bundle=run('bundle');self.assertEqual(bundle.returncode,0,bundle.stderr);obj=json.loads(bundle.stdout)
            self.assertIn(hashlib.sha256(RAW).hexdigest(),bundle.stdout.decode());self.assertIn('Cue 2',bundle.stdout.decode());self.assertEqual(bundle.stdout,run('bundle').stdout)
            preview=run('preview');self.assertEqual(preview.returncode,0,preview.stderr);self.assertIn(b'rollback',preview.stdout);self.assertEqual(vtt.read_bytes(),RAW);self.assertEqual(sel.read_bytes(),before)
            s=selection();s['participants'][1]['participant_kind']='agent';sel.write_text(json.dumps(s));bad=run('bundle');self.assertNotEqual(bad.returncode,0);self.assertEqual(bad.stdout,b'')

if __name__=='__main__':unittest.main(verbosity=2)
