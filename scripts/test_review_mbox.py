#!/usr/bin/env python3
"""Real mailbox intake and native pending-review consumer tests."""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import review_mbox as m

ROOT=Path(__file__).resolve().parents[1]
EXAMPLE=ROOT/'examples/review-mbox'
RAW=(EXAMPLE/'thread.mbox').read_bytes()
AGENDA=json.loads((EXAMPLE/'agenda.json').read_bytes())
PLAN=json.loads((EXAMPLE/'selections.json').read_bytes())
COMPOSER=os.environ.get('MOONCHAT_REVIEW_COMPOSER')


def mailbox(body=b'Question\n', headers=b'Content-Type: text/plain; charset=utf-8\nContent-Transfer-Encoding: 8bit\n'):
    return b'From a@example.invalid Mon Oct 12 12:00:00 2026\nFrom: A <a@example.invalid>\nSubject: Review\n'+headers+b'\n'+body


class IntakeTests(unittest.TestCase):
    def test_catalog_real_sample_and_exact_byte_ranges(self):
        result=m.parse_mailbox(RAW)
        self.assertEqual(result['mailbox_digest'],'sha256:'+hashlib.sha256(RAW).hexdigest())
        self.assertEqual(result['message_count'],3)
        for item in result['messages']:
            segment=RAW[item['source_start_byte']:item['source_end_byte']]
            self.assertEqual(item['message_digest'],m.digest(segment))
            self.assertTrue(segment.startswith(item['envelope'].encode()))
        self.assertEqual(result['messages'][0]['parts'][0]['text'].splitlines()[0],'I propose a limited café pilot after review.')
        headers=result['messages'][0]['headers']
        self.assertEqual(headers[0]['decoded_value'],'Alice Café <alice@example.invalid>')
        self.assertIn('=?UTF-8?',headers[0]['raw_value'])
        self.assertEqual(result['messages'][1]['parts'][0]['text'],'I object: rollback ownership is missing.\n')
        self.assertEqual([p['body_available'] for p in result['messages'][1]['parts']],[True,False,False])
        self.assertNotIn('text',result['messages'][1]['parts'][1])
        self.assertEqual(result['messages'][1]['parts'][2]['filename'],'unopened.bin')

    def test_ordinals_preserve_duplicate_missing_message_ids_and_order(self):
        catalog=m.parse_mailbox(RAW);candidate=m.import_messages(AGENDA,PLAN,catalog)
        self.assertEqual([x['key'] for x in candidate['items']],['launch','mail-rollback','mail-scope'])
        self.assertIn('"ordinal": 2',candidate['items'][1]['body'])
        self.assertIn('"ordinal": 1',candidate['items'][2]['body'])
        self.assertEqual(candidate['items'][0],AGENDA['items'][0])
        third=copy.deepcopy(PLAN);third['messages']=third['messages'][:1];third['messages'][0]['ordinal']=3
        self.assertIn('Who will observe',m.import_messages(AGENDA,third,catalog)['items'][-1]['body'])

    def test_crlf_utf8_8bit_and_stored_from_quoting(self):
        raw=mailbox('Café 世界\n>From prior\n>>From quoted\n'.encode()).replace(b'\n',b'\r\n')
        item=m.parse_mailbox(raw)['messages'][0]
        self.assertEqual(item['parts'][0]['text'],'Café 世界\r\n>From prior\r\n>>From quoted\r\n')
        self.assertEqual(item['source_end_byte'],len(raw))

    def test_supported_singlebyte_charset_and_base64(self):
        raw=mailbox(base64.b64encode('cost €'.encode('cp1252'))+b'\n',b'Content-Type: text/plain; charset=windows-1252\nContent-Transfer-Encoding: base64\n')
        self.assertEqual(m.parse_mailbox(raw)['messages'][0]['parts'][0]['text'],'cost €')

    def test_all_repeated_selected_headers_are_preserved(self):
        raw=mailbox().replace(b'Subject: Review\n',b'Subject: One\nSubject: Two\nX-Unselected: metadata\n')
        headers=m.parse_mailbox(raw)['messages'][0]['headers']
        self.assertEqual([h['decoded_value'] for h in headers if h['name']=='Subject'],['One','Two'])
        self.assertNotIn('X-Unselected',[h['name'] for h in headers])

    def test_hash_changes_include_whitespace_and_only_exact_hash_is_accepted(self):
        catalog=m.parse_mailbox(RAW+b'\n')
        with self.assertRaisesRegex(m.IntakeError,'digest differs'):m.import_messages(AGENDA,PLAN,catalog)

    def test_bad_or_duplicate_ordinals_reject_all_selections(self):
        for ordinal in [0,-1,4,True,1.0,'1']:
            plan=copy.deepcopy(PLAN);plan['messages'][-1]['ordinal']=ordinal
            with self.assertRaises(m.IntakeError):m.import_messages(AGENDA,plan,m.parse_mailbox(RAW))
        plan=copy.deepcopy(PLAN);plan['messages'][1]['ordinal']=2
        with self.assertRaises(m.IntakeError):m.import_messages(AGENDA,plan,m.parse_mailbox(RAW))

    def test_agenda_and_selections_are_immutable_and_email_text_is_never_authority(self):
        agenda,plan=copy.deepcopy(AGENDA),copy.deepcopy(PLAN)
        candidate=m.import_messages(agenda,plan,m.parse_mailbox(RAW))
        self.assertEqual(agenda,AGENDA);self.assertEqual(plan,PLAN)
        self.assertIn('I approve everything',candidate['items'][-1]['body'])
        self.assertEqual(candidate['participants'],AGENDA['participants'])
        self.assertEqual(candidate['items'][1]['decisions'],PLAN['messages'][0]['decisions'])
        self.assertEqual(candidate['items'][1]['author'],'assistant')

    def test_explicit_named_human_decisions_and_safe_keys_are_required(self):
        for key,value in [('author','bob@example.invalid'),('key','mail key'),('key','launch'),('note',''),('kind','approval'),('decisions',[])]:
            plan=copy.deepcopy(PLAN);plan['messages'][0][key]=value
            with self.assertRaises(m.IntakeError):m.import_messages(AGENDA,plan,m.parse_mailbox(RAW))
        for reviewer in ['assistant','unknown']:
            plan=copy.deepcopy(PLAN);plan['messages'][0]['decisions'][0]['reviewer']=reviewer
            with self.assertRaises(m.IntakeError):m.import_messages(AGENDA,plan,m.parse_mailbox(RAW))

    def test_html_only_is_cataloged_but_cannot_be_selected_as_plaintext(self):
        raw=mailbox(b'<script>never()</script>',b'Content-Type: text/html\n')
        catalog=m.parse_mailbox(raw);self.assertFalse(catalog['messages'][0]['body_available'])
        plan=copy.deepcopy(PLAN);plan['messages']=plan['messages'][:1];plan['messages'][0]['ordinal']=1;plan['mailbox_digest']=catalog['mailbox_digest']
        with self.assertRaisesRegex(m.IntakeError,'no supported'):m.import_messages(AGENDA,plan,catalog)

    def test_malformed_late_message_rejects_entire_mailbox(self):
        with self.assertRaises(m.IntakeError):m.parse_mailbox(RAW+b'From b@example.invalid Mon Oct 12 12:00:00 2026\nnot a header\n\ninvalid\n')

    def test_unsupported_mime_variants_and_encodings_fail(self):
        for headers,body in [(b'Content-Type: multipart/signed; boundary=x\n',b'--x\nContent-Type: text/plain\n\nabc\n--x--\n'),
          (b'Content-Type: multipart/mixed; boundary=missing\n',b'abc'),
          (b'Content-Type: text/plain; charset=unknown-encoding\n',b'abc'),
          (b'Content-Type: text/plain\nContent-Transfer-Encoding: base64\n',b'%%%'),
          (b'Content-Type: text/plain\nContent-Transfer-Encoding: quoted-printable\n',b'bad=QZ'),
          (b'Content-Type: text/plain\nContent-Transfer-Encoding: binary\n',b'abc'),
          (b'Content-Type: text/plain\nContent-Type: text/html\n',b'abc'),
          (b'Content-Type: text/plain\nContent-Length: 3\n',b'abc'),
          (b'Content-Type: text/plain; charset=utf-8\n',b'\xff')]:
            with self.subTest(headers=headers):
                with self.assertRaises(m.IntakeError):m.parse_mailbox(mailbox(body,headers))

    def test_mailbox_subset_refuses_bom_bare_cr_nul_invalid_envelope_and_preamble(self):
        for raw in [b'',b'\xef\xbb\xbf'+RAW,RAW.replace(b'\n',b'\r'),RAW+b'\x00',b'preamble\n'+RAW,RAW.replace(b'From alice@',b'From \t@',1)]:
            with self.assertRaises(m.IntakeError):m.parse_mailbox(raw)

    def test_bounds_checked_with_small_limits(self):
        for variable,value in [('MAX_BYTES',len(RAW)-1),('MAX_MESSAGES',2),('MAX_PARTS',1),('MAX_DEPTH',0)]:
            with patch.object(m,variable,value):
                with self.assertRaises(m.IntakeError):m.parse_mailbox(RAW)
        with patch.object(m,'MAX_IMPORTED',10):
            with self.assertRaises(m.IntakeError):m.parse_mailbox(RAW)
        catalog=m.parse_mailbox(RAW)
        with patch.object(m,'MAX_IMPORTED',10):
            with self.assertRaises(m.IntakeError):m.import_messages(AGENDA,PLAN,catalog)

    def test_opaque_nested_message_tree_still_obeys_depth_bound(self):
        raw=mailbox(b'From: Nested <n@example.invalid>\nContent-Type: message/rfc822\n\nFrom: Deep <d@example.invalid>\n\ntext\n',b'Content-Type: message/rfc822\nContent-Disposition: attachment\n')
        with patch.object(m,'MAX_DEPTH',1):
            with self.assertRaises(m.IntakeError):m.parse_mailbox(raw)

    def test_strict_json_and_unknown_selection_fields(self):
        for raw in [b'{"a":1,"a":2}',b'{"a":NaN}']:
            with self.assertRaises(m.IntakeError):m.load_json(raw)
        plan=copy.deepcopy(PLAN);plan['approvals']=['everyone']
        with self.assertRaises(m.IntakeError):m.import_messages(AGENDA,plan,m.parse_mailbox(RAW))

    def test_cli_catalog_and_failed_import_have_no_partial_stdout(self):
        result=subprocess.run([sys.executable,'-B',str(ROOT/'scripts/review_mbox.py'),'catalog',str(EXAMPLE/'thread.mbox')],capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(json.loads(result.stdout)['message_count'],3)
        with tempfile.TemporaryDirectory() as directory:
            bad=Path(directory)/'bad.mbox';bad.write_bytes(RAW+b'From incomplete\n')
            result=subprocess.run([sys.executable,'-B',str(ROOT/'scripts/review_mbox.py'),'catalog',str(bad)],capture_output=True)
            self.assertEqual(result.returncode,2);self.assertEqual(result.stdout,b'')


@unittest.skipUnless(COMPOSER,'set MOONCHAT_REVIEW_COMPOSER after exact binary/source verification')
class NativeConsumerTests(unittest.TestCase):
    def command(self, mode, agenda=AGENDA, plan=PLAN, raw=RAW):
        with tempfile.TemporaryDirectory(prefix='mbox-native-test-') as directory:
            d=Path(directory)
            (d/'agenda.json').write_text(json.dumps(agenda));(d/'selection.json').write_text(json.dumps(plan));(d/'source.mbox').write_bytes(raw)
            before={p.name:p.read_bytes() for p in d.iterdir()}
            result=subprocess.run([sys.executable,'-B',str(ROOT/'scripts/review_mbox.py'),mode,str(d/'agenda.json'),str(d/'source.mbox'),str(d/'selection.json'),'--composer',COMPOSER],capture_output=True)
            self.assertEqual(before,{p.name:p.read_bytes() for p in d.iterdir()})
            return result

    def test_actual_native_bundle_has_exact_source_and_pending_named_decisions(self):
        result=self.command('bundle');self.assertEqual(result.returncode,0,result.stderr)
        bundle=json.loads(result.stdout)
        self.assertEqual(bundle['source_digest'],m.digest(RAW))
        self.assertEqual(bundle['decision_receipts'],[])
        self.assertEqual(len(bundle['entries']),3)
        self.assertEqual(len(bundle['required_decisions']),4)
        self.assertIn('I approve everything',bundle['entries'][-1]['body'])
        self.assertEqual(bundle['required_decisions'][-2]['reviewer_participant_id'],'ops')

    def test_native_agenda_and_preview_are_real_consumed_outputs(self):
        agenda=self.command('agenda');self.assertEqual(agenda.returncode,0,agenda.stderr)
        candidate=json.loads(agenda.stdout);self.assertEqual(candidate['items'][0],AGENDA['items'][0])
        self.assertEqual(candidate['items'][-1]['evidence_refs'],[AGENDA['source_artifact_ref']])
        preview=self.command('preview');self.assertEqual(preview.returncode,0,preview.stderr)
        self.assertIn(b'rollback ownership',preview.stdout);self.assertIn(b'pending',preview.stdout.lower())

    def test_same_snapshot_composes_deterministically_and_source_changes_reject(self):
        a=self.command('bundle');b=self.command('bundle');self.assertEqual(a.stdout,b.stdout);self.assertEqual(a.returncode,0,a.stderr)
        changed=self.command('bundle',raw=RAW+b'\n');self.assertEqual(changed.returncode,2);self.assertEqual(changed.stdout,b'')

    def test_native_semantics_reject_invalid_source_reference_and_no_decisions(self):
        agenda=copy.deepcopy(AGENDA);agenda['source_artifact_ref']='../outside.mbox'
        result=self.command('agenda',agenda=agenda);self.assertEqual(result.returncode,2);self.assertEqual(result.stdout,b'')
        agenda=copy.deepcopy(AGENDA);agenda['items']=[]
        plan=copy.deepcopy(PLAN);plan['messages']=plan['messages'][1:];plan['messages'][0]['decisions']=[]
        result=self.command('agenda',agenda=agenda,plan=plan);self.assertEqual(result.returncode,2);self.assertEqual(result.stdout,b'')


if __name__=='__main__':unittest.main(verbosity=2)
