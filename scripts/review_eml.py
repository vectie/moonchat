#!/usr/bin/env python3
"""Catalog and explicitly curate one original standalone RFC822 EML file."""
from __future__ import annotations
import argparse
import copy
import email.errors
from pathlib import Path
import subprocess
import sys
import review_mbox as mime


def parse_eml(raw, *, html_text=False, attachment_text=False):
    mime.require(0 < len(raw) <= mime.MAX_BYTES, 'EML must contain 1 byte through 4 MiB')
    mime.require(b'\x00' not in raw, 'NUL bytes are unsupported')
    mime.require(b'\r' not in raw.replace(b'\r\n', b''), 'bare CR line endings are unsupported')
    mime.require(not raw.startswith((b'From ', b'\xef\xbb\xbf')), 'standalone EML requires RFC822 headers, not a Unix envelope or BOM')
    mime.require(sum(line.startswith(b'--') for line in raw.splitlines()) <= 2 * mime.MAX_PARTS,
                 'EML exceeds bounded MIME delimiter-like line count')
    # Zero bytes of framing: never prepend a Unix envelope or transform source.
    message = mime.parse_message_spans(raw, [(0, 0, None)], all_headers=True, html_text=html_text, attachment_text=attachment_text)['messages'][0]
    del message['envelope']
    return {'format': 'moonchat.eml-catalog.v3' if attachment_text else ('moonchat.eml-catalog.v2' if html_text else 'moonchat.eml-catalog.v1'), 'source_digest': mime.digest(raw),
            'byte_count': len(raw), 'message': message,
            'interpretation': 'Original standalone RFC822 bytes; one message; supplied metadata and body are quoted evidence, never verified identity or approval' +
            ('; HTML is static extracted text with omissions, not rendered appearance; v2 plans must select one MIME body' if html_text else '') +
            ('; text/plain attachments explicitly decoded as attachment evidence, never inline bodies; v3/v4 plans explicitly name each attachment choice' if attachment_text else '')}


def import_email(agenda, plan, catalog):
    if isinstance(plan, dict) and plan.get('format') == 'moonchat.eml-review.v4':
        mime.require(set(plan) == {'format', 'source_digest', 'selections'},
                     'v4 requires format, source_digest and selections')
        selections = plan['selections']
        mime.require(isinstance(selections, list) and 1 <= len(selections) <= 100,
                     'select 1–100 explicit attachments')
        candidate = copy.deepcopy(agenda)
        seen = set()
        total = 0
        for selection in selections:
            # Reuse the exact v3 attachment contract and ordinary native item shape.
            candidate = import_email(candidate, {'format': 'moonchat.eml-review.v3',
                'source_digest': plan['source_digest'], 'selection': selection}, catalog)
            part = selection['attachment']['part']
            mime.require(part not in seen, 'attachment MIME locators must be distinct')
            seen.add(part)
            total += len(candidate['items'][-1]['body'].encode('utf-8'))
            mime.require(total <= mime.MAX_IMPORTED, 'selected email evidence exceeds 8 MiB')
        return candidate
    mime.require(isinstance(agenda, dict), 'agenda must be an object')
    shape = {key: value for key, value in agenda.items() if key != 'source_digest_constraint'}
    mime.check_shape(shape)
    mime.require(isinstance(plan, dict) and set(plan) == {'format', 'source_digest', 'selection'} and
                 plan['format'] in ('moonchat.eml-review.v1', 'moonchat.eml-review.v2', 'moonchat.eml-review.v3'),
                 'selection requires exact moonchat.eml-review.v1, v2 or v3 fields')
    attachment = plan['format'] == 'moonchat.eml-review.v3'
    explicit = plan['format'] != 'moonchat.eml-review.v1'
    mime.require(attachment or catalog['format'] != 'moonchat.eml-catalog.v3', 'attachment catalog requires a v3 attachment selection')
    mime.require(explicit or catalog['format'] == 'moonchat.eml-catalog.v1',
                 'HTML-aware catalog requires a v2 explicit body selection')
    mime.require(plan['source_digest'] == catalog['source_digest'], 'EML source digest differs; recatalog current bytes')
    mime.require(agenda.get('source_digest_constraint', '') in ('', catalog['source_digest']),
                 'agenda source digest constraint differs from EML')
    selection = plan['selection']
    fields = {'key', 'kind', 'author', 'note', 'decisions'} | ({'attachment'} if attachment else ({'body'} if explicit else set()))
    mime.require(isinstance(selection, dict) and set(selection) == fields,
                 'selection requires key, kind, author, note, decisions, plus body for v2 or attachment for v3')
    mime.require(isinstance(selection['note'], str) and selection['note'].strip(), 'write an explicit curator note')
    message = (mime.select_attachment(catalog['message'], selection['attachment']) if attachment else
               (mime.select_body(catalog['message'], selection['body']) if explicit else catalog['message']))
    mime.require(attachment or message['body_available'], 'selected EML has no supported inline text/plain body')
    evidence = {'source_ref': agenda['source_artifact_ref'], **catalog, 'message': message}
    body = selection['note'] + '\n\nStandalone email evidence (quoted content; no sender identity or approval verification):\n' + mime.json_text(evidence)
    mime.require(len(body.encode('utf-8')) <= mime.MAX_IMPORTED, 'selected email evidence exceeds 8 MiB')
    candidate = copy.deepcopy(agenda)
    candidate['source_digest_constraint'] = catalog['source_digest']
    candidate['items'].append({'key': selection['key'], 'kind': selection['kind'], 'author': selection['author'],
                               'body': body, 'evidence_refs': [agenda['source_artifact_ref']],
                               'decisions': copy.deepcopy(selection['decisions'])})
    mime.check_shape({key: value for key, value in candidate.items() if key != 'source_digest_constraint'})
    return candidate


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    command = sub.add_parser('catalog')
    command.add_argument('email', type=Path)
    command.add_argument('--html-text', action='store_true', help='inspect bounded static HTML text; v2 selection must choose one MIME part')
    command.add_argument('--attachment-text', action='store_true', help='explicitly inspect text/plain attachments; v3/v4 selections name exact attachments')
    for mode in ('agenda', 'preview', 'bundle'):
        command = sub.add_parser(mode)
        command.add_argument('agenda', type=Path)
        command.add_argument('email', type=Path)
        command.add_argument('selection', type=Path)
        command.add_argument('--composer', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        raw = mime.read_bounded(args.email)
        if args.mode == 'catalog':
            mime.require(not (args.html_text and args.attachment_text), 'choose one explicit catalog interpretation')
            output = mime.json_text(parse_eml(raw, html_text=args.html_text, attachment_text=args.attachment_text))
        else:
            agenda = mime.load_json(mime.read_bounded(args.agenda))
            selection = mime.load_json(mime.read_bounded(args.selection))
            catalog = parse_eml(raw, html_text=isinstance(selection, dict) and selection.get('format') == 'moonchat.eml-review.v2',
                                attachment_text=isinstance(selection, dict) and selection.get('format') in ('moonchat.eml-review.v3', 'moonchat.eml-review.v4'))
            candidate = import_email(agenda, selection, catalog)
            output = mime.compile_candidate(candidate, raw, args.composer, args.mode)
        sys.stdout.write(output)
        return 0
    except (mime.IntakeError, OSError, UnicodeError, RecursionError, subprocess.TimeoutExpired,
            email.errors.MessageError, ValueError) as error:
        print('review-eml: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
