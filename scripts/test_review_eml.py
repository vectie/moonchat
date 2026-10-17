"""Standalone EML provenance, refusal and real native composition tests."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import review_eml as e

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / 'examples/review-eml'
RAW = (EXAMPLE/'objection.eml').read_bytes()
AGENDA = json.loads((EXAMPLE/'agenda.json').read_bytes())
PLAN = json.loads((EXAMPLE/'selection.json').read_bytes())
COMPOSER = os.environ.get('MOONCHAT_REVIEW_COMPOSER')


class EmlTests(unittest.TestCase):
    def test_exact_original_source_not_synthetic_mailbox(self):
        catalog = e.parse_eml(RAW)
        message = catalog['message']
        self.assertEqual(catalog['source_digest'], e.mime.digest(RAW))
        self.assertEqual(message['message_digest'], e.mime.digest(RAW))
        self.assertEqual((message['source_start_byte'], message['source_end_byte']), (0, len(RAW)))
        self.assertNotIn('envelope', message)
        self.assertEqual(message['ordinal'], 1)
        self.assertEqual(message['parts'][0]['part'], '1.1')
        self.assertIn('From an ordinary body line', message['parts'][0]['text'])
        self.assertIn('café', message['parts'][0]['text'])
        self.assertFalse(message['parts'][1]['body_available'])
        self.assertNotIn('text', message['parts'][1])

    def test_crlf_duplicate_custom_headers_and_base64(self):
        raw = b'Subject: One\r\nSubject: Two\r\nX-Custom: a\r\nX-Custom: b\r\nContent-Transfer-Encoding: base64\r\n\r\nSGVsbG8=\r\n'
        message = e.parse_eml(raw)['message']
        self.assertEqual([h['decoded_value'] for h in message['headers'] if h['name'] == 'Subject'], ['One', 'Two'])
        self.assertEqual(message['parts'][0]['text'], 'Hello')
        self.assertEqual(message['source_end_byte'], len(raw))

    def test_explicit_selection_is_immutable_pending_and_digest_constrained(self):
        agenda, plan = copy.deepcopy(AGENDA), copy.deepcopy(PLAN)
        candidate = e.import_email(agenda, plan, e.parse_eml(RAW))
        self.assertEqual(agenda, AGENDA)
        self.assertEqual(plan, PLAN)
        self.assertEqual(candidate['source_digest_constraint'], e.mime.digest(RAW))
        self.assertEqual(candidate['participants'], AGENDA['participants'])
        self.assertEqual(candidate['items'][0]['author'], 'curator')
        self.assertIn('I approve everything', candidate['items'][0]['body'])

    def test_invalid_selection_and_stale_constraint(self):
        for key, value in [('source_digest', 'sha256:stale'), ('format', 'moonchat.mbox-review.v1')]:
            plan = copy.deepcopy(PLAN); plan[key] = value
            with self.assertRaises(e.mime.IntakeError): e.import_email(AGENDA, plan, e.parse_eml(RAW))
        for key, value in [('author', 'alice@example.invalid'), ('kind', 'approval'), ('note', ''), ('decisions', [])]:
            plan = copy.deepcopy(PLAN); plan['selection'][key] = value
            with self.assertRaises(e.mime.IntakeError): e.import_email(AGENDA, plan, e.parse_eml(RAW))
        agenda = {**AGENDA, 'source_digest_constraint': 'sha256:stale'}
        with self.assertRaises(e.mime.IntakeError): e.import_email(agenda, PLAN, e.parse_eml(RAW))
        with self.assertRaises(e.mime.IntakeError): e.import_email(AGENDA, PLAN, e.parse_eml(RAW+b'\n'))

    def test_bad_framing_mime_and_bounds(self):
        for raw in [b'', b'\xef\xbb\xbf'+RAW, b'From a Mon Oct 12 12:00:00 2026\n'+RAW,
                    RAW+b'\x00', RAW.replace(b'\n', b'\r'), b'no headers\n\ntext',
                    b'Content-Type: multipart/mixed; boundary=missing\n\ntext',
                    b'Content-Transfer-Encoding: base64\n\n%%%',
                    b'Content-Type: text/plain; charset=unknown\n\ntext']:
            with self.subTest(raw=raw[:40]):
                with self.assertRaises(e.mime.IntakeError): e.parse_eml(raw)
        for name, value in [('MAX_BYTES', 1), ('MAX_PARTS', 1), ('MAX_DEPTH', 0), ('MAX_IMPORTED', 1)]:
            with patch.object(e.mime, name, value):
                with self.assertRaises(e.mime.IntakeError): e.parse_eml(RAW)

    def test_html_only_catalog_but_no_import(self):
        catalog = e.parse_eml(b'Subject: HTML\nContent-Type: text/html\n\n<p>hello</p>')
        plan = {**PLAN, 'source_digest': catalog['source_digest']}
        with self.assertRaises(e.mime.IntakeError): e.import_email(AGENDA, plan, catalog)

    def test_catalog_cli_and_no_partial_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'source.eml'; path.write_bytes(RAW)
            command = [sys.executable, '-B', str(ROOT/'scripts/review_eml.py'), 'catalog', str(path)]
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['source_digest'], e.mime.digest(RAW))
            path.write_bytes(b'bad')
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, b'')


@unittest.skipUnless(COMPOSER, 'set verified MOONCHAT_REVIEW_COMPOSER')
class NativeEmlTests(unittest.TestCase):
    def test_real_agenda_preview_bundle_and_stale_native_rejection(self):
        with tempfile.TemporaryDirectory() as folder:
            d = Path(folder)
            source = d/'original.eml'; source.write_bytes(RAW)
            agenda = d/'agenda.json'; agenda.write_text(json.dumps(AGENDA))
            plan = d/'selection.json'; plan.write_text(json.dumps(PLAN))
            command = [sys.executable, '-B', str(ROOT/'scripts/review_eml.py')]
            outputs = {}
            for mode in ('agenda', 'preview', 'bundle'):
                result = subprocess.run(command + [mode, str(agenda), str(source), str(plan), '--composer', COMPOSER], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs[mode] = result.stdout
            bundle = json.loads(outputs['bundle'])
            self.assertEqual(bundle['source_digest'], e.mime.digest(RAW))
            self.assertEqual(bundle['decision_receipts'], [])
            self.assertEqual(bundle['required_decisions'][0]['reviewer_participant_id'], 'ops')
            self.assertIn('I approve everything', bundle['entries'][0]['body'])
            self.assertIn(b'rollback', outputs['preview'])
            self.assertEqual(source.read_bytes(), RAW)
            candidate = d/'candidate.json'; candidate.write_bytes(outputs['agenda'])
            source.write_bytes(RAW+b'\n')
            stale = subprocess.run([COMPOSER, 'bundle', str(candidate), str(source)], capture_output=True)
            self.assertNotEqual(stale.returncode, 0)
            self.assertIn(b'constraint', stale.stdout+stale.stderr)
            rejected = subprocess.run(command + ['bundle', str(agenda), str(source), str(plan), '--composer', COMPOSER], capture_output=True)
            self.assertEqual(rejected.returncode, 2)
            self.assertEqual(rejected.stdout, b'')


if __name__ == '__main__':
    unittest.main()
