"""Literal mailbox discovery regression and real CLI tests."""
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import review_mbox as m
from test_review_mbox import RAW, mailbox
from test_review_mail_attachment import eml, mbox, TEXT


class SearchTests(unittest.TestCase):
    def test_attachment_opt_in_decodes_exact_provenance(self):
        raw = mbox(eml())
        for field in ('subject', 'body'):
            self.assertEqual(m.search_mailbox(raw, 'café', field=field)['total_hits'], 0)
        result = m.search_mailbox(raw, 'café', field='attachment')
        self.assertEqual(result['format'], 'moonchat.mbox-search.v3')
        self.assertEqual(result['total_hits'], 1)
        hit = result['results'][0]
        self.assertEqual(hit['attachment'], {'part': '1.2', 'mode': 'plain-text-attachment'})
        self.assertEqual(hit['mime_locator'], '1.2')
        self.assertEqual(hit['mailbox_digest'], m.digest(raw))
        self.assertEqual(hit['message_digest'], m.digest(raw[hit['source_start_byte']:hit['source_end_byte']]))
        self.assertEqual(hit['decoded_content_digest'], m.digest(TEXT.encode()))
        self.assertEqual(hit['decoded_content_bytes'], len(TEXT.encode()))
        self.assertEqual(hit['filename'], '../../never.txt')
        self.assertEqual(hit['excerpt'][hit['match_character'] - hit['excerpt_start_character']:][:4], 'café')
        self.assertNotIn('messages', result)
        self.assertNotIn('decisions', hit)
        self.assertEqual(m.search_mailbox(raw, 'CAFÉ', field='attachment')['total_hits'], 0)

    def test_attachment_decoding_profiles_and_excerpt_bounds(self):
        for payload, encoding, charset, query in [
            (base64.b64encode('世界 café'.encode()), 'base64', 'utf-8', '世界'),
            (b'caf=E9', 'quoted-printable', 'iso-8859-1', 'café'),
            (b'caf\xe9', '8bit', 'windows-1252', 'café'),
            (b'literal .*', '7bit', 'us-ascii', '.*')]:
            raw = mbox(eml(payload, encoding=encoding, charset=charset))
            hit = m.search_mailbox(raw, query, field='attachment')['results'][0]
            self.assertIn(query, hit['excerpt'])
            self.assertEqual(hit['transfer_encoding'], encoding)
        text = ('世界' * 500 + 'needle' + 'z' * 500).encode()
        hit = m.search_mailbox(mbox(eml(base64.b64encode(text))), 'needle', field='attachment')['results'][0]
        self.assertEqual(hit['match_character'], 1000)
        self.assertEqual(hit['excerpt_start_character'], 960)
        self.assertLessEqual(len(hit['excerpt']), 336)
        self.assertIn('needle', hit['excerpt'])

    def test_attachment_duplicate_filenames_pages_and_snapshot(self):
        raw = mbox(eml(base64.b64encode(b'needle one needle')).replace(
            b'filename="other.txt"', b'filename="../../never.txt"').replace(b'UNSELECTED ATTACHMENT', b'needle two')) * 2
        first = m.search_mailbox(raw, 'needle', field='attachment', limit=2)
        second = m.search_mailbox(raw, 'needle', field='attachment', offset=first['next_offset'],
                                  limit=2, mailbox_digest=first['mailbox_digest'])
        hits = first['results'] + second['results']
        self.assertEqual(first['total_hits'], 4)
        self.assertEqual([(h['ordinal'], h['mime_locator']) for h in hits], [(1, '1.2'), (1, '1.3'), (2, '1.2'), (2, '1.3')])
        self.assertEqual(len({h['filename'] for h in hits}), 1)
        self.assertIsNone(second['next_offset'])
        with self.assertRaises(m.IntakeError):
            m.search_mailbox(raw + b'\n', 'needle', field='attachment', mailbox_digest=first['mailbox_digest'])

    def test_attachment_unsupported_content_and_inline_filename_stay_opaque(self):
        for media in ('text/html', 'application/pdf', 'message/rfc822'):
            raw = mbox(eml(b'From: nested@example.invalid\nContent-Type: text/plain\n\nneedle', media=media, encoding='7bit'))
            self.assertEqual(m.search_mailbox(raw, 'needle', field='attachment')['total_hits'], 0)
        raw = mbox(eml(base64.b64encode(b'needle')).replace(b'Content-Disposition: attachment;', b'Content-Disposition: inline;'))
        self.assertEqual(m.search_mailbox(raw, 'needle', field='attachment')['total_hits'], 0)
        # An attached MIME container does not expose its nested attachments.
        raw = mbox(b'From: fixture@example.invalid\nContent-Type: multipart/mixed; boundary=x\n'
                   b'Content-Disposition: attachment\n\n--x\nContent-Type: text/plain\n'
                   b'Content-Disposition: attachment\n\nneedle\n--x--\n')
        self.assertEqual(m.search_mailbox(raw, 'needle', field='attachment')['total_hits'], 0)

    def test_attachment_explicit_mode_and_late_decoding_refuse(self):
        raw = mbox(eml())
        for options in ({'body_mode': 'html-text'}, {'header': 'From'}):
            with self.assertRaises(m.IntakeError):
                m.search_mailbox(raw, 'Rollback', field='attachment', **options)
        for bad in (eml(b'bad!'), eml(b'=ZZ', encoding='quoted-printable'), eml(charset='unknown')):
            combined = raw + mbox(bad)
            self.assertEqual(m.search_mailbox(combined, 'Attachment')['total_hits'], 2)
            with self.assertRaises(m.IntakeError):
                m.search_mailbox(combined, 'Rollback', field='attachment', limit=1)

    def test_subject_header_body_and_provenance(self):
        raw = mailbox(b'literal .* caf\xc3\xa9\n').replace(b'Subject: Review\n',
            b'Subject: =?UTF-8?Q?caf=C3=A9?=\nX-Case: first\nX-Case: second\n')
        for field, query, header in [('subject', 'café', None), ('header', 'second', 'x-case'), ('body', '.*', None)]:
            result = m.search_mailbox(raw, query, field=field, header=header)
            hit = result['results'][0]
            self.assertEqual(hit['mailbox_digest'], m.digest(raw))
            self.assertEqual(hit['message_digest'], m.digest(raw[hit['source_start_byte']:hit['source_end_byte']]))
            self.assertEqual(hit['ordinal'], 1)
            self.assertEqual(hit['mime_locator'], '1')
        self.assertEqual(m.search_mailbox(raw, 'CAFÉ')['total_hits'], 0)
        self.assertEqual(m.search_mailbox(raw, 'second', field='header', header='X-Case')['results'][0]['header_index'], 4)

    def test_pages_are_stable_bounded_and_snapshot_pinned(self):
        raw = mailbox() * 3
        first = m.search_mailbox(raw, 'Review', limit=1)
        second = m.search_mailbox(raw, 'Review', offset=first['next_offset'], limit=1,
                                 mailbox_digest=first['mailbox_digest'])
        self.assertEqual(first['total_hits'], 3)
        self.assertEqual(second['results'][0]['ordinal'], 2)
        self.assertIsNone(m.search_mailbox(raw, 'Review', offset=2)['next_offset'])
        self.assertEqual(m.search_mailbox(raw, 'Review', offset=100)['results'], [])
        with self.assertRaises(m.IntakeError):
            m.search_mailbox(raw + b'\n', 'Review', mailbox_digest=first['mailbox_digest'])

    def test_mime_parts_and_opaque_content(self):
        found = m.search_mailbox(RAW, 'rollback', field='body')
        self.assertEqual(found['results'][0]['ordinal'], 2)
        self.assertEqual(found['results'][0]['mime_locator'], '1.1.1')
        raw = mailbox(b'<b>needle</b>', b'Content-Type: text/html\n')
        self.assertEqual(m.search_mailbox(raw, 'needle', field='body')['results'], [])
        raw = mailbox(b'needle', b'Content-Type: text/plain\nContent-Disposition: attachment\n')
        self.assertEqual(m.search_mailbox(raw, 'needle', field='body')['results'], [])

    def test_limits_and_malformed_late_message(self):
        for kwargs in [{'query': ''}, {'query': 'x'*257}, {'query': 'x', 'limit': 101},
                       {'query': 'x', 'offset': -1}, {'query': 'x', 'field': 'header'},
                       {'query': 'x', 'header': 'From'}, {'query': 'x', 'field': 'header', 'header': 'bad\n'}]:
            with self.assertRaises(m.IntakeError):
                m.search_mailbox(RAW, **kwargs)
        with self.assertRaises(m.IntakeError):
            m.search_mailbox(RAW + b'From bad\n', 'pilot', field='body')
        result = m.search_mailbox(mailbox(b'x'*10000), 'x', field='body')
        self.assertLessEqual(len(result['results'][0]['excerpt']), 336)

    def test_real_cli_success_and_error_no_partial_stdout(self):
        script = Path(m.__file__)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'mail.mbox'
            path.write_bytes(RAW)
            command = [sys.executable, '-B', str(script), 'search', str(path), 'rollback', '--field', 'body', '--limit', '1']
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['results'][0]['ordinal'], 2)
            for extra in [['--limit', '0'], ['--mailbox-digest', 'sha256:stale']]:
                result = subprocess.run(command + extra, capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b'')
            self.assertEqual(path.read_bytes(), RAW)


if __name__ == '__main__':
    unittest.main()
