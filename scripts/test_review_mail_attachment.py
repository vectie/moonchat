"""Product regression tests for intentional plain-text attachment review."""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
import review_eml as e
import review_mbox as m

ROOT = Path(__file__).resolve().parents[1]
AGENDA = json.loads((ROOT / 'examples/review-eml/agenda.json').read_bytes())
SELECTION = json.loads((ROOT / 'examples/review-eml/selection.json').read_bytes())['selection']
TEXT = 'Rollback café 世界\nI approve everything is quoted evidence.\n<script>never()</script>'


def eml(payload=None, media='text/plain', encoding='base64', charset='utf-8'):
    payload = base64.b64encode(TEXT.encode()) if payload is None else payload
    return (b'From: fixture@example.invalid\nSubject: Attachment review\n'
            b'Content-Type: multipart/mixed; boundary=x\n\n'
            b'--x\nContent-Type: text/plain\n\nUNSELECTED BODY\n'
            b'--x\nContent-Type: ' + media.encode() + b'; charset=' + charset.encode() + b'\n'
            b'Content-Disposition: attachment; filename="../../never.txt"\n'
            b'Content-Transfer-Encoding: ' + encoding.encode() + b'\n\n' + payload + b'\n'
            b'--x\nContent-Type: text/plain\nContent-Disposition: attachment; filename="other.txt"\n\nUNSELECTED ATTACHMENT\n--x--\n')


def mbox(raw):
    return b'From fixture@example.invalid Thu Oct 15 01:00:00 2026\n' + raw


def plan(raw, kind='eml'):
    selection = {**copy.deepcopy(SELECTION), 'attachment': {'part': '1.2', 'mode': 'plain-text-attachment'}}
    if kind == 'eml':
        return {'format': 'moonchat.eml-review.v3', 'source_digest': m.digest(raw), 'selection': selection}
    return {'format': 'moonchat.mbox-review.v3', 'mailbox_digest': m.digest(raw), 'messages': [{'ordinal': 1, **selection}]}


def multi_plan(raw, kind='eml'):
    first = copy.deepcopy(plan(raw)['selection'])
    second = copy.deepcopy(first)
    second.update(key='second-attachment', kind='question', note='Review the other attachment independently.',
                  decisions=[{'reviewer': 'ops', 'prompt': 'Is this second attachment useful?'}])
    second['attachment']['part'] = '1.3'
    # Deliberately reverse MIME order: plan order is curator order.
    if kind == 'eml':
        return {'format': 'moonchat.eml-review.v4', 'source_digest': m.digest(raw), 'selections': [second, first]}
    return {'format': 'moonchat.mbox-review.v4', 'mailbox_digest': m.digest(raw),
            'messages': [{'ordinal': 1, **second}, {'ordinal': 1, **first}]}


class AttachmentTests(unittest.TestCase):
    def test_multi_attachment_order_meaning_and_legacy(self):
        for kind in ('eml', 'mbox'):
            raw = eml() if kind == 'eml' else mbox(eml())
            catalog = e.parse_eml(raw, attachment_text=True) if kind == 'eml' else m.parse_mailbox(raw, attachment_text=True)
            importer = e.import_email if kind == 'eml' else m.import_messages
            candidate = importer(AGENDA, multi_plan(raw, kind), catalog)
            self.assertEqual([item['key'] for item in candidate['items']], ['second-attachment', SELECTION['key']])
            self.assertEqual([item['kind'] for item in candidate['items']], ['question', SELECTION['kind']])
            for item, part, text, excluded in zip(candidate['items'], ['1.3', '1.2'],
                                                  ['UNSELECTED ATTACHMENT', 'Rollback'], ['Rollback', 'UNSELECTED ATTACHMENT']):
                evidence = json.loads(item['body'].split(':\n', 1)[1])
                message = evidence['message'] if kind == 'eml' else evidence
                self.assertEqual(message['attachment_choice']['part'], part)
                self.assertIn(text, item['body']); self.assertNotIn(excluded, item['body'])
                self.assertNotIn('UNSELECTED BODY', item['body'])
            self.assertEqual(len(importer(AGENDA, plan(raw, kind), catalog)['items']), 1)
            self.assertEqual(AGENDA['items'], [])

    def test_multi_attachment_requires_distinct_parts_keys_and_exact_v4_shape(self):
        for kind in ('eml', 'mbox'):
            raw = eml() if kind == 'eml' else mbox(eml())
            catalog = e.parse_eml(raw, attachment_text=True) if kind == 'eml' else m.parse_mailbox(raw, attachment_text=True)
            importer = e.import_email if kind == 'eml' else m.import_messages
            field = 'selections' if kind == 'eml' else 'messages'
            for mutation in ('part', 'key', 'empty', 'version', 'digest', 'body'):
                bad = multi_plan(raw, kind)
                if mutation == 'part': bad[field][1]['attachment'] = copy.deepcopy(bad[field][0]['attachment'])
                if mutation == 'key': bad[field][1]['key'] = bad[field][0]['key']
                if mutation == 'empty': bad[field] = []
                if mutation == 'version': bad['format'] = 'moonchat.' + kind + '-review.v5'
                if mutation == 'digest': bad['source_digest' if kind == 'eml' else 'mailbox_digest'] = m.digest(raw+b'\n')
                if mutation == 'body': bad[field][0]['body'] = {'part': '1.1', 'mode': 'plain-text'}
                with self.assertRaises(m.IntakeError): importer(AGENDA, bad, catalog)
            if kind == 'mbox':
                legacy = multi_plan(raw, kind); legacy['format'] = 'moonchat.mbox-review.v3'
                with self.assertRaises(m.IntakeError): importer(AGENDA, legacy, catalog)

    def test_opt_in_only_preserves_body_and_search_contract(self):
        raw = eml()
        for html in (False, True):
            part = e.parse_eml(raw, html_text=html)['message']['parts'][1]
            self.assertFalse(part['body_available'])
            self.assertNotIn('text', part)
        self.assertEqual(m.search_mailbox(mbox(raw), 'Rollback', field='body')['total_hits'], 0)
        self.assertEqual(m.search_mailbox(mbox(raw), 'UNSELECTED BODY', field='body')['total_hits'], 1)

    def test_exact_provenance_and_only_selected_text(self):
        raw = eml(); catalog = e.parse_eml(raw, attachment_text=True)
        part = catalog['message']['parts'][1]
        self.assertEqual(part['text'], TEXT)
        self.assertEqual(part['decoded_content_digest'], m.digest(TEXT.encode()))
        self.assertEqual(part['decoded_content_bytes'], len(TEXT.encode()))
        self.assertEqual(part['filename'], '../../never.txt')
        self.assertFalse(part['body_available'])
        candidate = e.import_email(AGENDA, plan(raw), catalog)
        body = candidate['items'][0]['body']
        self.assertNotIn('UNSELECTED BODY', body)
        self.assertNotIn('UNSELECTED ATTACHMENT', body)
        self.assertIn('moonchat.plain-text-attachment.v1', body)
        self.assertEqual(candidate['source_digest_constraint'], m.digest(raw))
        self.assertEqual(AGENDA['items'], [])
        self.assertEqual(catalog['message']['parts'][0]['text'], 'UNSELECTED BODY')

    def test_attachment_is_not_body_and_inline_is_not_attachment(self):
        catalog = e.parse_eml(eml(), attachment_text=True)
        with self.assertRaises(m.IntakeError):
            m.select_body(catalog['message'], {'part': '1.2', 'mode': 'plain-text'})
        for choice in ({'part': '1.1', 'mode': 'plain-text-attachment'}, {'part': '1.9', 'mode': 'plain-text-attachment'},
                       {'part': '1.2', 'mode': 'plain-text'}, {'part': '1.2'}, {'part': '1.2', 'mode': 'plain-text-attachment', 'filename': 'x'}):
            with self.assertRaises(m.IntakeError): m.select_attachment(catalog['message'], choice)

    def test_version_choice_and_digest_fail_closed(self):
        raw = eml(); catalog = e.parse_eml(raw, attachment_text=True)
        for mutation in ('stale', 'version', 'body', 'missing', 'legacy'):
            bad = plan(raw)
            if mutation == 'stale': bad['source_digest'] = m.digest(raw+b'\n')
            if mutation == 'version': bad['format'] = 'moonchat.eml-review.v4'
            if mutation == 'body': bad['selection']['body'] = {'part': '1.1', 'mode': 'plain-text'}
            if mutation == 'missing': del bad['selection']['attachment']
            if mutation == 'legacy':
                bad['format'] = 'moonchat.eml-review.v1'; del bad['selection']['attachment']
            with self.assertRaises(m.IntakeError): e.import_email(AGENDA, bad, catalog)
        with self.assertRaises(m.IntakeError): e.import_email(AGENDA, plan(raw), e.parse_eml(raw))

    def test_unsupported_attachments_stay_opaque(self):
        for media in ('text/html', 'application/pdf', 'message/rfc822'):
            raw = (eml(b'From: nested@example.invalid\nContent-Type: text/plain\n\nNESTED SECRET', media=media, encoding='7bit')
                   if media == 'message/rfc822' else eml(media=media))
            catalog = e.parse_eml(raw, attachment_text=True)
            self.assertNotIn('text', catalog['message']['parts'][1])
            with self.assertRaises(m.IntakeError): e.import_email(AGENDA, plan(raw), catalog)

    def test_bad_decoding_and_limits_refuse_without_implicit_open(self):
        for raw in (eml(b'bad!'), eml(b'=ZZ', encoding='quoted-printable'), eml(charset='unknown'),
                    eml(base64.b64encode(b'\x00')), eml(base64.b64encode(b'\xff'))):
            e.parse_eml(raw)
            with self.assertRaises(m.IntakeError): e.parse_eml(raw, attachment_text=True)
        with patch.object(m, 'MAX_IMPORTED', 8):
            with self.assertRaises(m.IntakeError): e.parse_eml(eml(), attachment_text=True)

    def test_quoted_printable_and_legacy_charset(self):
        raw = eml(b'caf=E9', encoding='quoted-printable', charset='iso-8859-1')
        self.assertEqual(e.parse_eml(raw, attachment_text=True)['message']['parts'][1]['text'], 'café')

    def test_attachment_only_message_and_mbox_validation(self):
        raw = b'From: fixture@example.invalid\nContent-Type: text/plain\nContent-Disposition: attachment; filename="note.txt"\n\nAttachment only'
        catalog = e.parse_eml(raw, attachment_text=True)
        self.assertFalse(catalog['message']['body_available'])
        choices = plan(raw); choices['selection']['attachment']['part'] = '1'
        self.assertIn('Attachment only', e.import_email(AGENDA, choices, catalog)['items'][0]['body'])
        raw = mbox(eml()); catalog = m.parse_mailbox(raw, attachment_text=True)
        for mutation in ('ordinal', 'digest', 'body', 'legacy'):
            bad = plan(raw, 'mbox')
            if mutation == 'ordinal': bad['messages'][0]['ordinal'] = True
            if mutation == 'digest': bad['mailbox_digest'] = m.digest(raw+b'\n')
            if mutation == 'body': bad['messages'][0]['attachment']['part'] = '1.1'
            if mutation == 'legacy': bad['format'] = 'moonchat.mbox-review.v2'
            with self.assertRaises(m.IntakeError): m.import_messages(AGENDA, bad, catalog)


class NativeAttachmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.composer = Path(os.environ['MOONCHAT_REVIEW_COMPOSER'])
        if hashlib.sha256(cls.composer.read_bytes()).hexdigest() != '60a1da93f31b568d43f18fb7eac831af4486f72b37c061ba46ecec1184c4520a':
            raise AssertionError('retained composer identity differs')
        for line in Path(os.environ['MOONCHAT_COMPOSER_INPUTS']).read_text().splitlines():
            sha, name = line.split('  ', 1)
            if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != sha:
                raise AssertionError('native source pin differs: ' + name)
        cls.evidence = Path(os.environ['MOONCHAT_ATTACHMENT_EVIDENCE'])
        cls.evidence.mkdir(parents=True, exist_ok=False)

    def test_real_attachment_search_then_explicit_v4_review(self):
        folder = self.evidence / 'attachment-search'; folder.mkdir()
        raw = mbox(eml().replace(b'filename="other.txt"', b'filename="../../never.txt"')
                   .replace(b'UNSELECTED ATTACHMENT', b'Rollback schedule needs a separate decision.')
                   .replace(b'--x--\n', b'--x\nContent-Type: application/pdf\nContent-Disposition: attachment\n\nRollback opaque PDF\n--x--\n'))
        source = folder / 'original.mbox'; source.write_bytes(raw)
        agenda = folder / 'agenda.json'; agenda.write_text(m.json_text(AGENDA))
        command = [sys.executable, '-B', str(ROOT / 'scripts/review_mbox.py')]
        original_files = set(folder.iterdir())
        search = subprocess.run(command + ['search', str(source), 'Rollback', '--field', 'attachment'], capture_output=True)
        self.assertEqual(search.returncode, 0, search.stderr)
        self.assertEqual(set(folder.iterdir()), original_files)
        self.assertEqual(json.loads(agenda.read_bytes())['items'], [])
        found = json.loads(search.stdout)
        self.assertEqual(found['total_hits'], 2)
        self.assertEqual([hit['mime_locator'] for hit in found['results']], ['1.2', '1.3'])
        self.assertEqual([hit['filename'] for hit in found['results']], ['../../never.txt'] * 2)
        (folder / 'search.out').write_bytes(search.stdout)
        # The curator creates the plan: search never generates keys, kinds,
        # notes, reviewers, decisions or an implicit selection of all hits.
        selections = []
        for index, hit in enumerate(reversed(found['results'])):
            selections.append({**copy.deepcopy(SELECTION), 'ordinal': hit['ordinal'],
                               'key': 'found-' + str(index), 'kind': 'question' if index == 0 else 'objection',
                               'note': 'Review chosen attachment ' + hit['mime_locator'] + ' independently.',
                               'decisions': [{'reviewer': 'ops', 'prompt': 'Resolve chosen attachment ' + hit['mime_locator'] + '?'}],
                               'attachment': hit['attachment']})
        choices = folder / 'selection.json'
        choices.write_text(m.json_text({'format': 'moonchat.mbox-review.v4',
                                       'mailbox_digest': found['mailbox_digest'], 'messages': selections}))
        outputs = {}
        for mode in ('agenda', 'preview', 'bundle'):
            result = subprocess.run(command + [mode, str(agenda), str(source), str(choices), '--composer', str(self.composer)], capture_output=True)
            (folder / (mode + '.out')).write_bytes(result.stdout)
            (folder / (mode + '.err')).write_bytes(result.stderr)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs[mode] = result.stdout
        candidate = json.loads(outputs['agenda'])
        self.assertEqual(candidate['source_digest_constraint'], found['mailbox_digest'])
        self.assertEqual([item['key'] for item in candidate['items']], ['found-0', 'found-1'])
        self.assertEqual([item['kind'] for item in candidate['items']], ['question', 'objection'])
        bundle = json.loads(outputs['bundle'])
        self.assertEqual(bundle['source_digest'], m.digest(raw))
        self.assertEqual(bundle['decision_receipts'], [])
        self.assertEqual([d['reviewer_participant_id'] for d in bundle['required_decisions']], ['ops', 'ops'])
        self.assertIn(b'pending_review', outputs['preview'])
        for item, hit in zip(bundle['entries'], reversed(found['results'])):
            evidence = json.loads(item['body'].split(':\n', 1)[1])
            self.assertEqual(evidence['message_digest'], hit['message_digest'])
            self.assertEqual(evidence['attachment_choice'], hit['attachment'])
            self.assertFalse(evidence['body_available'])
            self.assertNotIn('UNSELECTED BODY', item['body'])
            self.assertNotIn('Rollback opaque PDF', item['body'])
            selected = [p for p in evidence['parts'] if 'text' in p]
            self.assertEqual(len(selected), 1)
            self.assertEqual(selected[0]['decoded_content_digest'], hit['decoded_content_digest'])
        self.assertNotIn('I approve everything', bundle['entries'][0]['body'])
        self.assertIn('I approve everything', bundle['entries'][1]['body'])
        self.assertNotIn('Rollback schedule', bundle['entries'][1]['body'])
        imported = folder / 'imported-agenda.json'; imported.write_bytes(outputs['agenda'])
        replay = subprocess.run([str(self.composer), 'bundle', str(imported), str(source)], capture_output=True)
        self.assertEqual(replay.returncode, 0, replay.stderr)
        self.assertEqual(replay.stdout, outputs['bundle'])
        changed = folder / 'changed.mbox'; changed.write_bytes(raw.replace(b'Rollback schedule', b'Replaced schedule'))
        stale_commands = [command + ['search', str(changed), 'Rollback', '--field', 'attachment', '--mailbox-digest', found['mailbox_digest']]]
        stale_commands.extend(command + [mode, str(agenda), str(changed), str(choices), '--composer', str(self.composer)]
                              for mode in ('agenda', 'preview', 'bundle'))
        for index, invocation in enumerate(stale_commands):
            result = subprocess.run(invocation, capture_output=True)
            (folder / ('stale-' + str(index) + '.err')).write_bytes(result.stderr)
            self.assertEqual(result.returncode, 2); self.assertEqual(result.stdout, b'')
        native = subprocess.run([str(self.composer), 'bundle', str(imported), str(changed)], capture_output=True)
        (folder / 'native-stale.err').write_bytes(native.stdout + native.stderr)
        self.assertNotEqual(native.returncode, 0)
        self.assertIn(b'constraint', native.stdout + native.stderr)
        malformed = folder / 'malformed.mbox'; malformed.write_bytes(raw + mbox(eml(b'bad!')))
        invalid = subprocess.run(command + ['search', str(malformed), 'Rollback', '--field', 'attachment', '--limit', '1'], capture_output=True)
        self.assertEqual(invalid.returncode, 2); self.assertEqual(invalid.stdout, b'')
        (folder / 'malformed.err').write_bytes(invalid.stderr)
        self.assertEqual(source.read_bytes(), raw)
        self.assertEqual(json.loads(agenda.read_bytes()), AGENDA)

    def test_real_multiple_attachment_bundle(self):
        for kind in ('eml', 'mbox'):
            folder = self.evidence / ('multi-' + kind); folder.mkdir()
            raw = eml() if kind == 'eml' else mbox(eml())
            source = folder / ('original.' + kind); source.write_bytes(raw)
            agenda = folder / 'agenda.json'; agenda.write_text(m.json_text(AGENDA))
            choices = folder / 'selection.json'; choices.write_text(m.json_text(multi_plan(raw, kind)))
            command = [sys.executable, '-B', str(ROOT / ('scripts/review_' + kind + '.py'))]
            for mode in ('agenda', 'bundle', 'preview'):
                result = subprocess.run(command + [mode, str(agenda), str(source), str(choices), '--composer', str(self.composer)], capture_output=True)
                (folder / (mode + '.out')).write_bytes(result.stdout)
                (folder / (mode + '.err')).write_bytes(result.stderr)
                self.assertEqual(result.returncode, 0, result.stderr)
            bundle = json.loads((folder / 'bundle.out').read_bytes())
            self.assertEqual(len(bundle['entries']), 2)
            self.assertIn('UNSELECTED ATTACHMENT', bundle['entries'][0]['body'])
            self.assertNotIn('Rollback', bundle['entries'][0]['body'])
            self.assertIn('Rollback', bundle['entries'][1]['body'])
            self.assertEqual(len(bundle['required_decisions']), 2)
            self.assertEqual(bundle['decision_receipts'], [])
            self.assertEqual(bundle['source_digest'], m.digest(raw))
            self.assertIn(b'pending_review', (folder / 'preview.out').read_bytes())

    def test_real_eml_and_mbox_pending_review_and_stale_refusal(self):
        for kind in ('eml', 'mbox'):
            folder = self.evidence / kind; folder.mkdir()
            raw = eml() if kind == 'eml' else mbox(eml())
            source = folder / ('original.' + kind); source.write_bytes(raw)
            agenda = folder / 'agenda.json'; agenda.write_text(m.json_text(AGENDA))
            choices = folder / 'selection.json'; choices.write_text(m.json_text(plan(raw, kind)))
            command = [sys.executable, '-B', str(ROOT / ('scripts/review_' + kind + '.py'))]
            outputs = {}
            for mode in ('catalog', 'agenda', 'bundle', 'preview'):
                args = [mode, str(source), '--attachment-text'] if mode == 'catalog' else [mode, str(agenda), str(source), str(choices), '--composer', str(self.composer)]
                result = subprocess.run(command + args, capture_output=True)
                (folder / (mode + '.out')).write_bytes(result.stdout)
                (folder / (mode + '.err')).write_bytes(result.stderr)
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs[mode] = result.stdout
            bundle = json.loads(outputs['bundle'])
            self.assertEqual(bundle['source_digest'], m.digest(raw))
            self.assertEqual(bundle['decision_receipts'], [])
            self.assertEqual(bundle['required_decisions'][0]['reviewer_participant_id'], 'ops')
            self.assertIn('I approve everything', bundle['entries'][0]['body'])
            self.assertNotIn('UNSELECTED BODY', bundle['entries'][0]['body'])
            self.assertIn(b'pending_review', outputs['preview'])
            self.assertEqual(source.read_bytes(), raw)
            repeat = subprocess.run(command + ['bundle', str(agenda), str(source), str(choices), '--composer', str(self.composer)], capture_output=True)
            self.assertEqual(repeat.returncode, 0, repeat.stderr)
            self.assertEqual(repeat.stdout, outputs['bundle'])
            changed = folder / ('changed.' + kind); changed.write_bytes(raw+b'\n')
            stale = subprocess.run(command + ['bundle', str(agenda), str(changed), str(choices), '--composer', str(self.composer)], capture_output=True)
            (folder / 'stale.err').write_bytes(stale.stderr)
            self.assertEqual(stale.returncode, 2); self.assertEqual(stale.stdout, b'')
            candidate = folder / 'candidate.json'; candidate.write_bytes(outputs['agenda'])
            native = subprocess.run([str(self.composer), 'bundle', str(candidate), str(changed)], capture_output=True)
            (folder / 'native-stale.err').write_bytes(native.stdout+native.stderr)
            self.assertNotEqual(native.returncode, 0)
            self.assertIn(b'constraint', native.stdout+native.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
