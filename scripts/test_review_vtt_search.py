"""Find declared voices and turn explicitly selected cues into native reviews."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import review_vtt as v
ROOT = Path(__file__).resolve().parents[1]
RAW = b'WEBVTT\n\nfirst\n00:01.000 --> 00:03.000\n<v Alex>rollback &amp; recovery</v>\n\nsecond\n00:03.000 --> 00:04.000\n<v.blue Jo>ready</v>\n\nthird\n00:04.000 --> 00:06.000\n<v Alex>next step</v>\n'

class Search(unittest.TestCase):
    def test_voice_text_context_and_overlap(self):
        result = v.search_cues(RAW, 'ROLLBACK &', 'Alex', 2000, 3000, 1)
        self.assertEqual(result['matched_cues'], [1])
        self.assertEqual([c['cue'] for c in result['cues']], [1,2])
        self.assertFalse(result['cues'][1]['matched'])
        self.assertEqual(result['cues'][1]['voice_labels'], ['Jo'])
        self.assertEqual(v.search_cues(RAW, voice='Alex')['matched_cues'], [1,3])
        self.assertEqual(v.search_cues(RAW, voice='alex')['matched_cues'], [])
        self.assertEqual(v.search_cues(RAW, start_ms=3000,end_ms=4000)['matched_cues'], [2])
        self.assertEqual(result['source_digest'], 'sha256:'+hashlib.sha256(RAW).hexdigest())

    def test_unicode_and_bad_window(self):
        raw = RAW.replace(b'next step', 'Straße'.encode())
        self.assertEqual(v.search_cues(raw, 'STRASSE')['matched_cues'], [3])
        for kwargs in ({}, {'voice':''}, {'query':'x','context':6}, {'start_ms':True}, {'start_ms':3,'end_ms':3}):
            with self.assertRaises(ValueError): v.search_cues(RAW, **kwargs)

    def test_cli_search_to_selected_agenda(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder); source=p/'meeting.vtt'; source.write_bytes(RAW)
            base=[sys.executable,'-B',str(ROOT/'scripts/review_vtt.py')]
            run=subprocess.run(base+['search',str(source),'--voice','Alex','--text','rollback','--context','1'],capture_output=True)
            self.assertEqual(run.returncode,0,run.stderr)
            result=json.loads(run.stdout)
            plan=json.loads((ROOT/'examples/review-vtt/selection.json').read_text())
            plan['items'][0]['cues']=result['matched_cues']
            selection=p/'selection.json';selection.write_text(json.dumps(plan))
            agenda=subprocess.run(base+['agenda',str(source),str(selection)],capture_output=True)
            self.assertEqual(agenda.returncode,0,agenda.stderr)
            self.assertIn(b'Cue 1',agenda.stdout);self.assertNotIn(b'Cue 2',agenda.stdout)
            composer=os.environ.get('MOONCHAT_COMPOSER')
            if not composer: self.skipTest('native composer not configured; search and agenda checks ran')
            bundle=subprocess.run(base+['bundle',str(source),str(selection),'--composer',composer],capture_output=True)
            self.assertEqual(bundle.returncode,0,bundle.stderr)
            self.assertIn(hashlib.sha256(RAW).hexdigest().encode(),bundle.stdout)
            self.assertIn(b'Cue 1',bundle.stdout);self.assertNotIn(b'Cue 2',bundle.stdout)
            self.assertEqual(source.read_bytes(),RAW)
            if os.environ.get('MOONCHAT_VTT_SEARCH_EVIDENCE'):
                out=Path(os.environ['MOONCHAT_VTT_SEARCH_EVIDENCE']);out.mkdir(parents=True,exist_ok=True)
                for name,data in [('meeting.vtt',RAW),('search.json',run.stdout),('selection.json',selection.read_bytes()),('agenda.json',agenda.stdout),('bundle.json',bundle.stdout)]:
                    (out/name).write_bytes(data)

if __name__ == '__main__': unittest.main()
