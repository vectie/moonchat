"""Producer security and actual retained native prepare/preview integration."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

import review_decision_editor as editor

ROOT = Path(__file__).resolve().parents[2]
EXE = Path(os.environ['MOONCHAT_REVIEW_DECIDER']).resolve()
BUNDLE = ROOT / 'examples/review-agenda/review.json'
SOURCE = ROOT / 'examples/review-agenda/source.md'


def native(*args, ok=True):
    result = subprocess.run([str(EXE), *map(str, args)], capture_output=True, text=True)
    assert (result.returncode == 0) == ok, (result.stdout, result.stderr)
    return result.stdout


class ProducerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bundle, self.source = BUNDLE.read_bytes(), SOURCE.read_bytes()
        self.form = json.loads(native('prepare', BUNDLE, SOURCE, 'ops'))
        self.before = [hashlib.sha256(p.read_bytes()).hexdigest() for p in (BUNDLE, SOURCE)]

    def tearDown(self):
        self.assertEqual(self.before, [hashlib.sha256(p.read_bytes()).hexdigest() for p in (BUNDLE, SOURCE)])

    def render(self, form=None, bundle=None, source=None):
        return editor.page(json.dumps(self.form if form is None else form).encode(),
                           self.bundle if bundle is None else bundle, self.source if source is None else source, EXE)

    def complete(self, outcome='defer'):
        form = copy.deepcopy(self.form)
        for i, choice in enumerate(form['choices']):
            choice.update(outcome=outcome, rationale='Retain the rollback objection. Café remains explicit.',
                          receipt_id='new-' + str(i), decided_at='2026-10-12T17:00:00Z', evidence_refs=['release/checks.txt'])
        return form

    def test_native_prepare_complete_context_blank_outcomes(self):
        page = self.render()
        self.assertIn('No decisions selected.', page)
        self.assertIn('Complete source text', page)
        self.assertIn('source_revision_id', page)
        self.assertIn(self.source.decode().strip(), page)
        self.assertTrue(all(not c['outcome'] for c in self.form['choices']))
        for entry in self.form['entries']:
            self.assertIn(editor.html.escape(entry['body'], quote=True), page)
        self.assertIn('Fixture editor', page)
        self.assertIn('decision-6-launch-editor', page)
        self.assertIn('No network or automatic saving', page)
        self.assertIn('id="merge-file"', page)
        self.assertIn('id="conflicts"', page)
        self.assertIn('Merge resolved draft', page)
        self.assertIn('Both must come from this exact blank native form', page)

    def test_output_is_self_contained_and_csp_hash_matches_actual_scripts(self):
        page = self.render()
        scripts = re.findall(r'<script>(.*?)</script>', page, re.S)
        self.assertEqual(len(scripts), 1)
        self.assertIn("script-src 'sha256-" + editor.base64.b64encode(hashlib.sha256(scripts[0].encode()).digest()).decode(), page)
        self.assertNotRegex(page, r'<(?:script|link|iframe|img)[^>]+(?:src|href)=')
        for policy in ("connect-src 'none'", "form-action 'none'", "base-uri 'none'", "object-src 'none'"):
            self.assertIn(policy, page)

    def test_tampered_protected_fields_and_seeded_choices_refused(self):
        for name, value in [('reviewer_name', 'Impersonator'), ('entries', []), ('reviewer_participant_id', 'editor'),
                            ('base_bundle_digest', 'sha256:' + '0' * 64), ('choices', [])]:
            changed = copy.deepcopy(self.form); changed[name] = value
            with self.subTest(name=name), self.assertRaises(editor.EditorError): self.render(changed)
        with self.assertRaisesRegex(editor.EditorError, 'blank choices'): self.render(self.complete())

    def test_exact_bundle_bytes_and_changed_source_refused(self):
        with self.assertRaises(editor.EditorError): self.render(bundle=self.bundle + b' ')
        with self.assertRaises(editor.EditorError): self.render(source=self.source + b'changed')

    def test_duplicate_json_unknown_fields_and_unpaired_unicode_refused(self):
        for raw in (b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":"\\ud800"}', b'[]'):
            with self.subTest(raw=raw), self.assertRaises(editor.EditorError): editor.strict_json(raw)
        changed = copy.deepcopy(self.form); changed['authenticated'] = True
        with self.assertRaises(editor.EditorError): self.render(changed)

    def test_non_text_and_over_limit_source_refused(self):
        for raw in (b'\xff', b'\x00', b'x' * (editor.MAX_BYTES + 1)):
            with self.subTest(raw=raw[:4]), self.assertRaises(editor.EditorError): self.render(source=raw)

    def test_hostile_text_is_literal_and_not_markup(self):
        bundle = json.loads(self.bundle)
        hostile = '</script><img src=x onerror=alert(1)> & "\\ café\u2028'
        bundle['entries'][0]['body'] = hostile
        path = self.work / 'hostile.json'; path.write_text(json.dumps(bundle))
        form = json.loads(native('prepare', path, SOURCE, 'ops'))
        page = self.render(form, path.read_bytes())
        self.assertNotIn('<img src=x', page)
        self.assertEqual(page.count('</script>'), 1)
        self.assertIn(editor.html.escape(hostile, quote=True), page)

    def test_existing_receipts_stay_historical_no_seed_copy(self):
        bundle = json.loads(self.bundle)
        bundle['decision_receipts'] = [{'receipt_id':'prior-editor','decision_id':'decision-6-launch-editor',
            'reviewer_participant_id':'editor','reviewer_name':'Fixture editor','decision':'reject',
            'rationale':'Historical dissent.','source_digest':bundle['source_digest'],
            'decided_at':'2026-10-12T16:00:00Z','evidence_refs':[]}]
        path = self.work/'prior.json'; path.write_text(json.dumps(bundle))
        form = json.loads(native('prepare', path, SOURCE, 'ops'))
        page = self.render(form, path.read_bytes())
        self.assertIn('prior-editor', page)
        self.assertTrue(all(c['receipt_id'] == '' for c in form['choices']))
        native('prepare', path, SOURCE, 'editor', ok=False)

    def test_all_native_outcomes_and_partial_review_roundtrip(self):
        path = self.work/'form.json'
        for outcome in ('approve','reject','defer'):
            form = self.complete(outcome); path.write_text(json.dumps(form))
            preview = native('preview', path, BUNDLE, SOURCE)
            self.assertIn('UNVERIFIED DECISION SUBMISSION', preview)
            self.assertIn('not a review receipt', preview)
            self.assertIn(outcome, preview)
            for entry in self.form['entries']: self.assertIn(entry['body'], preview)
            self.assertEqual(preview, native('preview', path, BUNDLE, SOURCE))
        form['choices'][1] = self.form['choices'][1]
        path.write_text(json.dumps(form)); native('preview', path, BUNDLE, SOURCE)
        native('apply', path, BUNDLE, SOURCE, ok=False)

    def test_native_consumer_refuses_tampered_export_and_partial_fields(self):
        path = self.work/'form.json'
        for mutate in (lambda f: f.update(entries=[]), lambda f: f.update(reviewer_name='Other'),
                       lambda f: f['choices'][0].update(receipt_id=''), lambda f: f['choices'][0].update(outcome=''),
                       lambda f: f['choices'][0].update(evidence_refs=['../outside']),
                       lambda f: f['choices'][0].update(decision_id='decision-6-launch-editor')):
            form = self.complete(); mutate(form); path.write_text(json.dumps(form))
            native('preview', path, BUNDLE, SOURCE, ok=False)

    def test_cli_new_output_only_and_errors_never_overwrite(self):
        form = self.work/'prepared.json'; form.write_text(json.dumps(self.form))
        output = self.work/'editor.html'
        command = [sys.executable, '-B', str(Path(editor.__file__)), str(form), str(BUNDLE), str(SOURCE), '--decider', str(EXE), '--output', str(output)]
        result = subprocess.run(command, capture_output=True, text=True); self.assertEqual(result.returncode, 0, result.stderr)
        before = output.read_bytes()
        result = subprocess.run(command, capture_output=True, text=True); self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, output.read_bytes())
        command[-1] = str(form); before = form.read_bytes()
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertEqual(before, form.read_bytes())

    def test_missing_runtime_blocks_page_without_authority_fallback(self):
        with self.assertRaisesRegex(editor.EditorError, 'native prepare unavailable'):
            editor.page(json.dumps(self.form).encode(), self.bundle, self.source, self.work/'missing-executable')


if __name__ == '__main__':
    unittest.main(verbosity=2)
