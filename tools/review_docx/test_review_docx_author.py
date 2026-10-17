"""Producer checks for the explicit local Word-review authoring surface."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest
from unittest.mock import patch

import review_docx as d
import review_docx_author as author
import review_docx_packet as packet
from test_review_docx import DOC, COMMENTS, agenda, archive, parts, plan
from test_review_docx_plan import encoded
from test_review_docx_packet import PacketHTML


class AuthoringTests(unittest.TestCase):
    def render(self, a=None, data=None, p=None):
        return author.authoring_packet(encoded(a or agenda()), data or archive(), encoded(p) if p is not None else None)

    def bootstrap(self, html):
        script = re.search(r'<script>([\s\S]*)</script>', html).group(1)
        return json.loads(script.split('const input = ', 1)[1].split(';\n', 1)[0])

    def test_empty_start_original_source_and_agenda_remain_exact(self):
        html = self.render(); parsed = PacketHTML(html)
        self.assertEqual(''.join(parsed.source), d._read_docx(archive())[1])
        self.assertEqual(parsed.comments, [c['text'] for c in d.catalog_docx(archive())['comments']])
        boot = self.bootstrap(html)
        self.assertEqual(boot['agenda'], agenda())
        self.assertEqual(boot['plan']['comments'], [])
        self.assertEqual(boot['plan']['document_digest'], d.digest(archive()))
        self.assertEqual(parsed.stack, [])
        self.assertEqual(len(parsed.ids), len(set(parsed.ids)))
        self.assertTrue(all(link.startswith('#') and link[1:] in parsed.ids for link in parsed.links))
        self.assertIn('No decisions, receipts, source edits, currentness checks', html)
        self.assertIn(d.digest(encoded(agenda())), html)

    def test_seed_is_existing_importer_recipe_and_deterministic(self):
        a, p = agenda(), plan(); original = copy.deepcopy((a, p))
        html = self.render(a, p=p)
        self.assertEqual(html, self.render(a, p=p))
        self.assertEqual(self.bootstrap(html)['plan'], p)
        self.assertEqual((a, p), original)
        with patch.object(author, 'import_comments', wraps=d.import_comments) as importer:
            self.render(a, p=p)
            importer.assert_called_once()
        for edit in (lambda p: p.update(document_digest='sha256:wrong'),
                     lambda p: p['comments'][0].update(key='rollout'),
                     lambda p: p['comments'][0]['decisions'][0].update(reviewer='notes'),
                     lambda p: p['comments'].append(copy.deepcopy(p['comments'][0])),
                     lambda p: p['comments'][0]['decisions'].append(copy.deepcopy(p['comments'][0]['decisions'][0]))):
            bad = plan(); edit(bad)
            with self.subTest(bad=bad), self.assertRaises(d.IntakeError): self.render(p=bad)

    def test_original_invalid_roster_or_items_rejected(self):
        for edit in (lambda a: a['participants'].append(copy.deepcopy(a['participants'][0])),
                     lambda a: a['items'][0]['decisions'][0].update(reviewer='notes'),
                     lambda a: a['items'][0].update(author='unknown'),
                     lambda a: a.update(receipts=[])):
            a = agenda(); edit(a)
            with self.subTest(a=a), self.assertRaises(d.IntakeError): self.render(a)

    def test_safe_literal_serialization_and_hash_only_csp(self):
        attack = '</script><img src="https://example.invalid/x" onerror="alert(1)">&\r\u2028\u2029'
        a = agenda(); a['participants'][0]['display_name'] = attack
        a['items'][0]['body'] = attack
        p = plan(); p['comments'][0]['note'] = attack
        p['comments'][0]['decisions'][0]['prompt'] = attack
        html = self.render(a, p=p); boot = self.bootstrap(html)
        self.assertEqual(boot['agenda']['participants'][0]['display_name'], attack)
        self.assertEqual(boot['plan']['comments'][0]['note'], attack)
        self.assertEqual(html.count('<script>'), 1)
        self.assertEqual(html.count('</script>'), 1)
        self.assertNotIn('<img', html)
        script = re.search(r'<script>([\s\S]*)</script>', html).group(1)
        expected = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        self.assertIn("script-src 'sha256-" + expected + "'", html)
        self.assertNotIn("script-src 'unsafe-inline'", html)
        self.assertNotIn('innerHTML', script)
        for forbidden in ('fetch(', 'XMLHttpRequest', 'localStorage', 'sessionStorage', 'eval('):
            self.assertNotIn(forbidden, script)

    def test_evidence_costs_match_exact_importer_for_unicode_controls_and_long_overlap(self):
        text = '界🚀\\"\t\r\n' * 1000
        import xml.sax.saxutils
        doc = DOC.replace('Roll out to 10%', xml.sax.saxutils.escape(text).replace('\r', '&#13;'))
        data = archive(parts(document=doc))
        p = plan(data)
        boot = self.bootstrap(self.render(data=data))
        costs = {c['comment_id']: c['evidence_bytes'] for c in boot['comments']}
        imported = d.import_comments(agenda(), p, d.catalog_docx(data))
        for selection, item in zip(p['comments'], imported['items'][1:]):
            self.assertEqual(costs[selection['comment_id']] + len(selection['note'].encode()), len(item['body'].encode()))
        self.assertIn('Excerpt stops after 2000 characters', self.render(data=data))

    def test_invalid_unicode_scalar_values_are_rejected_without_unhandled_encoding(self):
        a = agenda(); a['items'][0]['body'] = '\ud800'
        with self.assertRaisesRegex(d.IntakeError, 'valid Unicode'):
            author.authoring_packet(json.dumps(a).encode(), archive())
        p = plan(); p['comments'][0]['note'] = '\udfff'
        with self.assertRaisesRegex(d.IntakeError, 'valid Unicode'):
            author.authoring_packet(encoded(agenda()), archive(), json.dumps(p).encode())

    def test_total_bound_applies_to_code_bootstrap_and_original_source(self):
        with patch.object(packet, 'MAX_PACKET_BYTES', 500):
            with self.assertRaisesRegex(d.IntakeError, 'exceeds 32 MiB'): self.render()

    def test_actual_cli_explicit_opt_in_optional_seed_no_partial_stdout(self):
        root = Path(__file__).resolve().parents[2]
        base = [sys.executable, '-B', str(root / 'tools/review_docx/review_docx.py'), 'plan-packet',
                str(root / 'examples/review-docx-plan/agenda.json'), str(root / 'examples/review-docx/launch.docx')]
        run = subprocess.run(base, capture_output=True)
        self.assertEqual(run.returncode, 1); self.assertEqual(run.stdout, b'')
        run = subprocess.run(base + ['--authoring'], capture_output=True, cwd='/tmp')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn(b'<script>', run.stdout)
        seed = str(root / 'examples/review-docx-plan/selections.json')
        run = subprocess.run(base + [seed], capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr); self.assertNotIn(b'<script>', run.stdout)
        run = subprocess.run(base + [seed, '--authoring'], capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(len(self.bootstrap(run.stdout.decode())['plan']['comments']), 2)
