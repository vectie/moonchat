"""Explicit mailbox reply exploration and real retained composer consumption."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import review_mbox as m

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = Path(os.environ.get('MOONCHAT_THREAD_EVIDENCE') or tempfile.mkdtemp(prefix='moonchat-thread-'))
EVIDENCE.mkdir(parents=True, exist_ok=True)
COMPOSER = os.environ.get('MOONCHAT_REVIEW_COMPOSER')


def message(identity=None, reply=None, refs=None, extra=''):
    headers = 'From fixture@example.invalid Wed Oct 14 12:00:00 2026\nFrom: Fixture <fixture@example.invalid>\nSubject: Same subject\n'
    for name, value in [('Message-ID', identity), ('In-Reply-To', reply), ('References', refs)]:
        if value is not None:
            headers += name + ': ' + value + '\n'
    return (headers + extra + '\nI approve everything is supplied evidence, not a decision.\n').encode()


class ThreadTests(unittest.TestCase):
    def setUp(self):
        self.folder = EVIDENCE / self._testMethodName
        self.folder.mkdir()
        self.number = 0

    def explore(self, raw, **selection):
        self.number += 1
        (self.folder / f'{self.number}.mbox').write_bytes(raw)
        result = m.thread_mailbox(raw, **selection)
        (self.folder / f'{self.number}.json').write_text(m.json_text(result))
        return result

    def test_parent_children_siblings_references_fallback_and_source_binding(self):
        raw = message('<root@x>') + message('<child@x>', '<root@x>') + message('<sibling@x>', refs='<absent@x> <root@x>') + message('<unrelated@x>')
        result = self.explore(raw, message_id='<child@x>', mailbox_digest=m.digest(raw))
        self.assertEqual(result['selected_ordinal'], 2)
        self.assertEqual([n['ordinal'] for n in result['messages']], [1, 2, 3])
        self.assertEqual(result['messages'][2]['parent']['via'], 'References-last')
        self.assertEqual(result['messages'][2]['reference_links'][0]['status'], 'missing')
        for node in result['messages']:
            self.assertEqual(node['message_digest'], m.digest(raw[node['source_start_byte']:node['source_end_byte']]))
        self.assertEqual(result['mailbox_digest'], m.digest(raw))
        self.assertNotIn('decisions', result)

    def test_duplicate_ids_never_merge_and_ambiguous_incoming_is_visible(self):
        raw = message('<same@x>') + message('<same@x>') + message('<child@x>', '<same@x>')
        with self.assertRaisesRegex(m.IntakeError, 'matching ordinals: \\[1, 2\\]'):
            self.explore(raw, message_id='<same@x>')
        result = self.explore(raw, ordinal=1)
        self.assertEqual([n['ordinal'] for n in result['messages']], [1])
        self.assertEqual(result['messages'][0]['message_id_status'], 'duplicate')
        self.assertEqual(result['ambiguous_incoming'][0]['parent']['candidate_ordinals'], [1, 2])
        result = self.explore(raw, ordinal=3)
        self.assertEqual(result['messages'][0]['parent']['status'], 'ambiguous-parent')

    def test_missing_ids_parents_case_and_no_subject_grouping(self):
        raw = message() + message('<child@x>', '<MISSING@x>') + message('<missing@x>')
        first = self.explore(raw, ordinal=1)
        self.assertEqual(first['messages'][0]['message_id_status'], 'absent')
        self.assertEqual(len(first['messages']), 1)
        second = self.explore(raw, ordinal=2)
        self.assertEqual(second['messages'][0]['parent']['status'], 'missing-parent')
        self.assertEqual(len(second['messages']), 1)

    def test_cycles_and_self_links_terminate_honestly(self):
        raw = message('<a@x>', '<b@x>') + message('<b@x>', '<a@x>') + message('<self@x>', '<self@x>')
        self.assertEqual(self.explore(raw, ordinal=1)['cycles'], [[1, 2]])
        self.assertEqual(self.explore(raw, ordinal=3)['cycles'], [[3]])

    def test_unsupported_multiple_and_repeated_headers_do_not_guess(self):
        raw = message('<root@x>') + message('<child@x>', '<root@x> <other@x>', '<root@x>') + message('<third@x>', '(comment) <root@x>') + message('<fourth@x>', '<root@x>', extra='In-Reply-To: <root@x>\n')
        for ordinal, status in [(2, 'ambiguous-header'), (3, 'unsupported-header-syntax'), (4, 'ambiguous-header')]:
            result = self.explore(raw, ordinal=ordinal)
            self.assertEqual(result['messages'][0]['parent']['status'], status)
            self.assertEqual(len(result['messages']), 1)

    def test_stale_invalid_and_output_bounds(self):
        raw = message('<root@x>')
        for selected in ({}, {'ordinal': True}, {'ordinal': 2}, {'ordinal': 1, 'message_id': '<root@x>'}, {'message_id': 'root@x'}, {'ordinal': 1, 'mailbox_digest': m.digest(raw + b'\n')}):
            with self.assertRaises(m.IntakeError):
                self.explore(raw, **selected)
        with patch.object(m, 'MAX_IMPORTED', 100):
            with self.assertRaises(m.IntakeError):
                self.explore(raw, ordinal=1)

    def test_unusable_parent_identity_mentions_are_ambiguous_not_missing(self):
        for extra in ('Message-ID: <root@x>\n', ''):
            raw = message('<root@x>' if extra else '<root@x> (comment)', extra=extra) + message('<child@x>', '<root@x>')
            result = self.explore(raw, ordinal=2)
            self.assertEqual(result['messages'][0]['parent']['status'], 'ambiguous-parent')
            self.assertEqual(result['messages'][0]['parent']['candidate_ordinals'], [1])
            with self.assertRaises(m.IntakeError): self.explore(raw, message_id='<root@x>')

    def test_bounded_long_chain_and_reference_tokens(self):
        raw = b''.join(message(f'<m{i}@x>', f'<m{i-1}@x>' if i else None) for i in range(500))
        result = self.explore(raw, ordinal=500)
        self.assertEqual(len(result['messages']), 500)
        self.assertEqual(result['cycles'], [])
        with self.assertRaisesRegex(m.IntakeError, '10000'):
            self.explore(message('<root@x>', refs=' '.join(['<missing@x>'] * 10001)), ordinal=1)

    def test_actual_cli_thread_and_failure_have_complete_output(self):
        raw = message('<root@x>') + message('<child@x>', '<root@x>')
        path = self.folder / 'mailbox.mbox'; path.write_bytes(raw)
        args = [sys.executable, '-B', str(ROOT / 'scripts/review_mbox.py'), 'thread', str(path), '--message-id', '<child@x>']
        good = subprocess.run(args, capture_output=True)
        (self.folder / 'thread.json').write_bytes(good.stdout)
        (self.folder / 'thread.stderr').write_bytes(good.stderr)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertEqual(json.loads(good.stdout)['selected_ordinal'], 2)
        bad = subprocess.run(args + ['--mailbox-digest', m.digest(raw + b'\n')], capture_output=True)
        (self.folder / 'stale.stdout').write_bytes(bad.stdout); (self.folder / 'stale.stderr').write_bytes(bad.stderr)
        self.assertEqual(bad.returncode, 2); self.assertEqual(bad.stdout, b'')
        self.assertEqual(path.read_bytes(), raw)

    @unittest.skipUnless(COMPOSER, 'set MOONCHAT_REVIEW_COMPOSER after verifying the retained native executable')
    def test_explicit_selection_reaches_actual_native_composer_without_approval(self):
        raw = message('<root@x>') + message('<child@x>', '<root@x>')
        explored = self.explore(raw, message_id='<child@x>')
        agenda = json.loads((ROOT / 'examples/review-mbox/agenda.json').read_bytes())
        plan = {'format': 'moonchat.mbox-review.v1', 'mailbox_digest': explored['mailbox_digest'], 'messages': [
            {'ordinal': 2, 'key': 'selected-reply', 'kind': 'objection', 'author': 'assistant',
             'note': 'The curator explicitly selects this reply for review.',
             'decisions': [{'reviewer': 'ops', 'prompt': 'Does this reply resolve the objection?'}]}]}
        for name, value in [('agenda', agenda), ('selection', plan)]:
            (self.folder / (name + '.json')).write_text(m.json_text(value))
        path = self.folder / 'mailbox.mbox'; path.write_bytes(raw)
        for mode in ('agenda', 'bundle', 'preview'):
            args = [sys.executable, '-B', str(ROOT / 'scripts/review_mbox.py'), mode, str(self.folder / 'agenda.json'), str(path), str(self.folder / 'selection.json'), '--composer', COMPOSER]
            run = subprocess.run(args, capture_output=True)
            (self.folder / (mode + '-output.txt')).write_bytes(run.stdout)
            (self.folder / (mode + '.stderr')).write_bytes(run.stderr)
            self.assertEqual(run.returncode, 0, run.stderr)
            if mode == 'bundle':
                result = json.loads(run.stdout)
                self.assertEqual(result['source_digest'], m.digest(raw))
                self.assertEqual(result['decision_receipts'], [])
                self.assertEqual(len(result['entries']), 2)
                self.assertEqual(len(result['required_decisions']), 3)
                self.assertIn('I approve everything', result['entries'][-1]['body'])
            if mode == 'preview':
                self.assertIn(b'pending', run.stdout.lower())
        self.assertEqual(path.read_bytes(), raw)


if __name__ == '__main__': unittest.main()
