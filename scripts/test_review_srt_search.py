"""Discover original transcript cues and feed the existing review importer."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
import review_srt as s

ROOT = Path(__file__).resolve().parents[1]
EX = ROOT/'examples/review-srt'

class SearchTests(unittest.TestCase):
    def test_context_and_review_selection(self):
        raw = (EX/'meeting.srt').read_bytes()
        catalog = s.parse_srt(raw)
        result = s.search_cues(catalog, 'ROLLBACK', context=1)
        self.assertEqual(result['matched_ordinals'], [1])
        self.assertEqual([c['ordinal'] for c in result['cues']], [1, 2])
        plan = json.loads((EX/'selection.json').read_bytes())
        plan['items'][0]['cues'] = result['matched_ordinals']
        candidate = s.import_cues(json.loads((EX/'agenda.json').read_bytes()), plan, catalog)
        self.assertIn('srt/cue/1', candidate['items'][0]['body'])
        self.assertNotIn('srt/cue/2', candidate['items'][0]['body'])
        self.assertEqual(result['source_digest'], s.common.digest(raw))
        composer = os.environ.get('MOONCHAT_REVIEW_COMPOSER')
        if composer:
            bundle = json.loads(s.common.compile_candidate(candidate, raw, Path(composer), 'bundle'))
            self.assertIn('srt/cue/1', json.dumps(bundle))
            evidence = os.environ.get('MOONCHAT_SEARCH_EVIDENCE')
            if evidence:
                folder = Path(evidence); folder.mkdir(parents=True, exist_ok=True)
                (folder/'search.json').write_text(json.dumps(result, indent=2))
                (folder/'selected-plan.json').write_text(json.dumps(plan, indent=2))
                (folder/'candidate.json').write_text(json.dumps(candidate, indent=2))
                (folder/'bundle.json').write_text(json.dumps(bundle, indent=2))

    def test_overlap_unicode_and_no_hits(self):
        c = s.parse_srt('1\n00:00:01,000 --> 00:00:03,000\nStraße\n\n1\n00:00:03,000 --> 00:00:04,000\nother'.encode())
        before = copy.deepcopy(c)
        self.assertEqual(s.search_cues(c, 'STRASSE', 2000, 3000)['matched_ordinals'], [1])
        self.assertEqual(s.search_cues(c, start_ms=3000, end_ms=4000)['matched_ordinals'], [2])
        self.assertEqual(s.search_cues(c, 'absent', context=5)['cues'], [])
        self.assertEqual(c, before)

    def test_cli_and_bad_window(self):
        run = subprocess.run([sys.executable, '-B', str(ROOT/'scripts/review_srt.py'), 'search', str(EX/'meeting.srt'), '--text', 'rollback'], capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(run.stdout)['matched_ordinals'], [1])
        c = s.parse_srt((EX/'meeting.srt').read_bytes())
        for kwargs in ({}, {'start_ms': -1}, {'start_ms': 5, 'end_ms': 5}, {'query':'x', 'context':6}):
            with self.assertRaises(s.common.IntakeError): s.search_cues(c, **kwargs)

if __name__ == '__main__': unittest.main()
