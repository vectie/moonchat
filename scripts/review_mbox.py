#!/usr/bin/env python3
"""Review explicitly selected messages from a bounded local Unix mbox snapshot."""
from __future__ import annotations
import argparse
import base64
import binascii
import copy
import email.policy
from email.parser import BytesParser
import hashlib
import json
from pathlib import Path
import quopri
import re
import subprocess
import sys
import tempfile
from review_mail_html import extract_html_text, HtmlTextError

# Reuse existing agenda-shape checks and strict JSON intake. Native composition
# remains the authority for portable review semantics, including agenda mode.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools' / 'review_docx'))
from review_docx import IntakeError, load_json
from review_docx_plan import check_shape

MAX_BYTES = 4 * 1024 * 1024
MAX_MESSAGES = 500
MAX_PARTS = 2000
MAX_DEPTH = 16
MAX_IMPORTED = 8 * 1024 * 1024
HEADERS = ('From', 'To', 'Cc', 'Subject', 'Date', 'Message-ID', 'In-Reply-To', 'References')
CHARSETS = {'us-ascii': 'ascii', 'ascii': 'ascii', 'utf-8': 'utf-8', 'utf8': 'utf-8',
            'iso-8859-1': 'iso-8859-1', 'latin-1': 'iso-8859-1', 'windows-1252': 'cp1252', 'cp1252': 'cp1252'}


def require(condition, message):
    if not condition:
        raise IntakeError(message)


def digest(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def json_text(value):
    return json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n'


def read_bounded(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    require(len(raw) <= MAX_BYTES, 'input exceeds 4 MiB')
    return raw


def parse_mailbox(raw, *, all_headers=False, html_text=False, attachment_text=False):
    """Source offsets/digests refer to untouched bytes, never the email decoder."""
    require(0 < len(raw) <= MAX_BYTES, 'mailbox must contain 1 byte through 4 MiB')
    require(b'\x00' not in raw, 'NUL bytes are not supported in this text mailbox')
    # LF and CRLF are accepted; standalone CR is not an envelope/header separator.
    require(b'\r' not in raw.replace(b'\r\n', b''), 'bare CR line endings are unsupported')
    lines = raw.splitlines(keepends=True)
    boundaries = []
    offset = 0
    for line in lines:
        if line.startswith(b'From '):
            require(re.fullmatch(rb'From [^\s\x00-\x1f\x7f]+ [\x20-\x7e]+\r?\n', line) is not None,
                    'unsupported Unix From envelope line')
            boundaries.append((offset, len(line), line.rstrip(b'\r\n').decode('ascii')))
            require(len(boundaries) <= MAX_MESSAGES, 'mailbox exceeds 500 messages')
        offset += len(line)
    require(boundaries and boundaries[0][0] == 0, 'expected a Unix mbox From envelope at byte zero')
    require(sum(line.startswith(b'--') for line in lines) <= 2 * MAX_PARTS, 'mailbox exceeds bounded MIME delimiter-like line count')
    return parse_message_spans(raw, boundaries, all_headers=all_headers, html_text=html_text, attachment_text=attachment_text)


def parse_message_spans(raw, boundaries, *, all_headers=False, html_text=False, attachment_text=False):
    """Decode known original RFC822 spans; a zero envelope size is standalone EML.

    Callers validate format-specific framing and input bounds first.
    """
    require(not (html_text and attachment_text), 'choose one explicit catalog interpretation')
    messages = []
    part_count = 0
    decoded_bytes = 0
    for index, (start, envelope_size, envelope) in enumerate(boundaries):
        end = boundaries[index + 1][0] if index + 1 < len(boundaries) else len(raw)
        message_bytes = raw[start + envelope_size:end]
        require(message_bytes and re.search(rb'\r?\n\r?\n', message_bytes), 'each message needs a header/body separator')
        try:
            message = BytesParser(policy=email.policy.default.clone(raise_on_defect=True)).parsebytes(message_bytes)
        except (ValueError, IndexError, RecursionError, email.errors.MessageError) as error:
            raise IntakeError('message ' + str(index + 1) + ' has unsupported or malformed MIME') from error
        require(bool(message.keys()), 'each message needs at least one mail header')
        # Bound the entire parsed MIME tree, including opaque attachments and
        # nested RFC822 messages, before selecting any readable body parts.
        scan = [(message, 0)]
        while scan:
            node, node_depth = scan.pop()
            part_count += 1
            require(part_count <= MAX_PARTS and node_depth <= MAX_DEPTH,
                    'MIME tree exceeds 2000 parts or depth 16')
            require(not node.defects, 'malformed MIME structure')
            for control in ('Content-Type', 'Content-Transfer-Encoding', 'Content-Disposition'):
                require(len(node.get_all(control, [])) <= 1, 'duplicate MIME control header: ' + control)
                header = node.get(control)
                require(header is None or not getattr(header, 'defects', ()), 'malformed MIME control header: ' + control)
            require(not node.get_all('Content-Length', []), 'Content-Length mbox variants are unsupported')
            if node.is_multipart():
                scan.extend((child, node_depth + 1) for child in node.get_payload())
        headers = []
        # All repeated values are retained in original order, never matched to participants.
        for name, value in message.raw_items():
            if all_headers or name.lower() in {h.lower() for h in HEADERS}:
                try:
                    decoded = str(message.policy.header_fetch_parse(name, value))
                except (ValueError, IndexError, email.errors.MessageError) as error:
                    raise IntakeError('unsupported encoded message header') from error
                require(not any(0xD800 <= ord(c) <= 0xDFFF for c in decoded + value), 'unsupported non-Unicode header bytes')
                headers.append({'name': name, 'raw_value': value, 'decoded_value': decoded})
        parts = []
        pending = [(message, '1', 0)]
        while pending:
            part, locator, depth = pending.pop()
            require(not part.defects, 'malformed MIME part ' + locator)
            for key in ('Content-Type', 'Content-Transfer-Encoding', 'Content-Disposition'):
                require(len(part.get_all(key, [])) <= 1, 'duplicate MIME control header: ' + key)
            require(not part.get_all('Content-Length', []), 'Content-Length mbox variants are unsupported')
            content_type = part.get_content_type()
            disposition = part.get_content_disposition()
            # Attachments stay opaque unless the caller explicitly opts into the
            # bounded text/plain profile. Never extract filenames to disk.
            info = {'part': locator, 'content_type': content_type,
                    'disposition': disposition, 'filename': part.get_filename()}
            attachment = disposition == 'attachment' and content_type == 'text/plain' and attachment_text
            if disposition not in (None, 'inline') and not attachment:
                parts.append({**info, 'body_available': False, 'omission': 'attachment or non-inline content'})
                continue
            if content_type.startswith('multipart/'):
                require(content_type in ('multipart/mixed', 'multipart/alternative', 'multipart/related'),
                        'unsupported multipart MIME type: ' + content_type)
                require(part.is_multipart(), 'multipart content has no valid parts')
                children = part.get_payload()
                require(isinstance(children, list) and children, 'multipart message has no parts')
                for child_index in range(len(children) - 1, -1, -1):
                    pending.append((children[child_index], locator + '.' + str(child_index + 1), depth + 1))
                continue
            if content_type != 'text/plain' and not (html_text and content_type == 'text/html'):
                parts.append({**info, 'body_available': False, 'omission': 'only inline text/plain is decoded'})
                continue
            require(not part.is_multipart(), 'nested message is not an inline plain-text body')
            charset = (part.get_content_charset() or 'us-ascii').lower()
            require(charset in CHARSETS, 'unsupported plain-text charset: ' + charset)
            encoding = (part.get('Content-Transfer-Encoding') or '7bit').strip().lower()
            require(encoding in ('7bit', '8bit', 'base64', 'quoted-printable'), 'unsupported text transfer encoding')
            payload = part.get_payload(decode=False)
            require(isinstance(payload, str), 'plain-text part must have a scalar payload')
            # email represents raw 8-bit bodies with surrogateescape.
            try:
                encoded = part.get_payload(decode=True)
                wire = payload.encode('ascii', errors='strict') if encoding in ('base64', 'quoted-printable') else b''
            except (UnicodeError, ValueError, email.errors.MessageError) as error:
                raise IntakeError('unsupported plain-text payload encoding') from error
            require(isinstance(encoded, bytes), 'plain-text bytes are unavailable')
            if encoding == 'base64':
                try:
                    encoded = base64.b64decode(re.sub(rb'[\t\r\n ]', b'', wire), validate=True)
                except (ValueError, binascii.Error) as error:
                    raise IntakeError('invalid base64 plain-text body') from error
            elif encoding == 'quoted-printable':
                require(re.search(rb'=(?![0-9a-fA-F]{2}|\r?\n)', wire) is None, 'invalid quoted-printable plain-text body')
                encoded = quopri.decodestring(wire)
            elif encoding == '7bit':
                require(all(byte < 128 for byte in encoded), 'non-ASCII bytes require an explicit transfer encoding')
            try:
                text = encoded.decode(CHARSETS[charset], errors='strict')
            except UnicodeError as error:
                raise IntakeError('plain-text bytes do not match their declared charset') from error
            require('\x00' not in text, 'NUL in decoded plain text is unsupported')
            decoded_bytes += len(text.encode('utf-8'))
            require(decoded_bytes <= MAX_IMPORTED, 'decoded body text exceeds 8 MiB')
            details = {'text': text}
            if content_type == 'text/html':
                try:
                    details = extract_html_text(text)
                except HtmlTextError as error:
                    raise IntakeError('HTML part ' + locator + ': ' + str(error)) from error
                details['decoded_content_digest'] = digest(encoded)
                details['decoded_content_bytes'] = len(encoded)
            if attachment:
                details.update({'attachment_available': True,
                                'interpretation': 'moonchat.plain-text-attachment.v1',
                                'decoded_content_digest': digest(encoded),
                                'decoded_content_bytes': len(encoded)})
            parts.append({**info, 'body_available': not attachment, 'charset': charset,
                          'transfer_encoding': encoding, **details})
        messages.append({'ordinal': index + 1, 'source_start_byte': start, 'source_end_byte': end,
                         'message_digest': digest(raw[start:end]), 'envelope': envelope,
                         'headers': headers, 'parts': parts,
                         'body_available': any(part['body_available'] for part in parts)})
    return {'format': 'moonchat.mbox-catalog.v3' if attachment_text else ('moonchat.mbox-catalog.v2' if html_text else 'moonchat.mbox-catalog.v1'), 'mailbox_digest': digest(raw),
            'byte_count': len(raw), 'message_count': len(messages), 'messages': messages,
            'interpretation': 'Unix From-envelope boundaries; stored >From body quoting retained; supplied headers are not identity or authority' +
            ('; HTML is static extracted text with omissions, not rendered appearance; v2 plans must select one MIME body' if html_text else '') +
            ('; text/plain attachments explicitly decoded as attachment evidence, never inline bodies; v3/v4 plans explicitly name each attachment choice' if attachment_text else '')}


def search_mailbox(raw, query, *, field='subject', header=None, offset=0, limit=20, mailbox_digest=None, body_mode='plain-text'):
    """Literal, case-sensitive discovery; one hit per matching field/part.

    Byte ranges identify original messages, not decoded substring positions.
    Header indices and MIME locators disambiguate repeated values and parts.
    """
    require(isinstance(query, str) and 1 <= len(query) <= 256 and '\x00' not in query,
            'query must contain 1–256 non-NUL characters')
    require(field in ('subject', 'header', 'body', 'attachment'),
            'field must be subject, header, body or attachment')
    require((field == 'header' and isinstance(header, str) and
             re.fullmatch(r'[A-Za-z0-9-]{1,78}', header) is not None) or
            (field != 'header' and header is None), '--header is required only for header search')
    require(type(offset) is int and offset >= 0, 'offset must be a nonnegative integer')
    require(type(limit) is int and 1 <= limit <= 100, 'limit must be 1–100')
    require(body_mode in ('plain-text', 'html-text'), 'body mode must be plain-text or html-text')
    require(body_mode == 'plain-text' or field == 'body', 'html-text mode is only for body search')
    catalog = parse_mailbox(raw, all_headers=True, html_text=body_mode == 'html-text',
                            attachment_text=field == 'attachment')
    require(mailbox_digest is None or mailbox_digest == catalog['mailbox_digest'],
            'mailbox digest differs; restart search on current bytes')
    hits = []
    count = 0
    for message in catalog['messages']:
        if field == 'attachment':
            # This field is the explicit opt-in. Reuse the same narrow decoded
            # profile as v3/v4 intake; filenames never identify or open files.
            candidates = [(part['text'], {
                'mime_locator': part['part'],
                'attachment': {'part': part['part'], 'mode': 'plain-text-attachment'},
                **{key: part[key] for key in ('filename', 'content_type', 'charset', 'transfer_encoding',
                                               'decoded_content_digest', 'decoded_content_bytes', 'interpretation')}
            }) for part in message['parts'] if part.get('attachment_available') is True]
        elif field == 'body':
            candidates = [(part['text'], {'mime_locator': part['part']})
                          for part in message['parts'] if part['body_available'] and
                          part['content_type'] == ('text/html' if body_mode == 'html-text' else 'text/plain')]
        else:
            wanted = 'subject' if field == 'subject' else header.lower()
            candidates = [(value['decoded_value'], {'mime_locator': '1',
                           'header_name': value['name'], 'header_index': index + 1})
                          for index, value in enumerate(message['headers']) if value['name'].lower() == wanted]
        for text, locator in candidates:
            position = text.find(query)
            if position < 0:
                continue
            if offset <= count < offset + limit:
                start = max(0, position - 40)
                hits.append({key: message[key] for key in
                             ('ordinal', 'message_digest', 'source_start_byte', 'source_end_byte')})
                hits[-1].update({'mailbox_digest': catalog['mailbox_digest'], 'field': field,
                                **locator, 'match_character': position,
                                'excerpt_start_character': start, 'excerpt': text[start:start + 336]})
            count += 1
    interpretation = 'Case-sensitive literal decoded-text discovery; one hit per matching header or inline text/plain MIME part. Message byte spans include the original Unix envelope. No identity, threading, selection or approval inferred.'
    if body_mode == 'html-text':
        interpretation = 'Case-sensitive literal static HTML-text discovery; one hit per matching inline text/html MIME part. Not rendered appearance; omissions and hidden text limitations are recorded by catalog --html-text. Message byte spans include the original Unix envelope. No identity, threading, selection or approval inferred.'
    if field == 'attachment':
        interpretation = 'Case-sensitive literal decoded attachment-text discovery; one hit per matching explicitly disposed text/plain attachment. Unsupported attachments remain opaque. Filenames are untrusted metadata, never identities or paths. Message byte spans include the original Unix envelope. Explicitly copy chosen ordinal and attachment locator into a digest-bound v4 review plan; no selection, decision, sender authority or receiver acceptance is inferred.'
    return {'format': 'moonchat.mbox-search.v3' if field == 'attachment' else ('moonchat.mbox-search.v2' if body_mode == 'html-text' else 'moonchat.mbox-search.v1'), 'mailbox_digest': catalog['mailbox_digest'],
            'query': query, 'field': field, 'header': header, 'offset': offset, 'limit': limit,
            'total_hits': count, 'next_offset': offset + len(hits) if offset + len(hits) < count else None,
            'results': hits, 'interpretation': interpretation}


def select_body(message, choice):
    """A v2 plan names exactly one representation and one original MIME locator."""
    require(isinstance(choice, dict) and set(choice) == {'part', 'mode'},
            'explicit body choice requires exactly part and mode')
    require(choice['mode'] in ('plain-text', 'html-text') and isinstance(choice['part'], str),
            'body choice requires plain-text or html-text and a MIME locator')
    chosen = [part for part in message['parts'] if part['part'] == choice['part']]
    require(len(chosen) == 1 and chosen[0]['body_available'], 'chosen MIME part has no supported inline body')
    require(chosen[0]['content_type'] == ('text/plain' if choice['mode'] == 'plain-text' else 'text/html'),
            'body mode does not match the chosen MIME part')
    require(choice['mode'] != 'html-text' or chosen[0].get('interpretation') == 'moonchat.static-html-text.v1',
            'HTML body requires explicit static-text catalog interpretation')
    result = copy.deepcopy(message)
    for part in result['parts']:
        if part['part'] != choice['part'] and part['body_available']:
            part.pop('text', None)
            part['body_available'] = False
            part['omission'] = 'not selected; an alternative MIME body is not concatenated'
    result['body_choice'] = copy.deepcopy(choice)
    return result


def select_attachment(message, choice):
    """Select attachment evidence without promoting it to an inline mail body."""
    require(isinstance(choice, dict) and set(choice) == {'part', 'mode'} and
            choice['mode'] == 'plain-text-attachment' and isinstance(choice['part'], str),
            'attachment choice requires part and plain-text-attachment mode')
    chosen = [part for part in message['parts'] if part['part'] == choice['part']]
    require(len(chosen) == 1 and chosen[0].get('attachment_available') is True and
            chosen[0]['disposition'] == 'attachment' and chosen[0]['content_type'] == 'text/plain' and
            chosen[0].get('interpretation') == 'moonchat.plain-text-attachment.v1',
            'chosen MIME part is not an explicitly decoded plain-text attachment')
    result = copy.deepcopy(message)
    for part in result['parts']:
        if part['part'] != choice['part']:
            part.pop('text', None)
            part['body_available'] = False
            part['attachment_available'] = False
            part['omission'] = 'not selected; attachment evidence is distinct from message bodies and other attachments'
    result['body_available'] = False
    result['attachment_choice'] = copy.deepcopy(choice)
    return result


def import_messages(agenda, plan, catalog):
    require(isinstance(plan, dict) and set(plan) == {'format', 'mailbox_digest', 'messages'} and
            plan['format'] in ('moonchat.mbox-review.v1', 'moonchat.mbox-review.v2', 'moonchat.mbox-review.v3', 'moonchat.mbox-review.v4'),
            'selection requires moonchat.mbox-review.v1, v2, v3 or v4 and its exact fields')
    multiple = plan['format'] == 'moonchat.mbox-review.v4'
    attachment = plan['format'] in ('moonchat.mbox-review.v3', 'moonchat.mbox-review.v4')
    explicit = plan['format'] != 'moonchat.mbox-review.v1'
    require(attachment or catalog['format'] != 'moonchat.mbox-catalog.v3', 'attachment catalog requires a v3 attachment selection')
    require(isinstance(agenda, dict), 'agenda must be an object')
    check_shape({key: value for key, value in agenda.items() if not (explicit and key == 'source_digest_constraint')})
    if explicit:
        require(agenda.get('source_digest_constraint', '') in ('', catalog['mailbox_digest']),
                'agenda source digest constraint differs from mailbox')
    require(explicit or catalog['format'] == 'moonchat.mbox-catalog.v1',
            'HTML-aware catalog requires a v2 explicit body selection')
    require(plan['mailbox_digest'] == catalog['mailbox_digest'], 'mailbox digest differs; catalog exact current bytes again')
    selections = plan['messages']
    require(isinstance(selections, list) and 1 <= len(selections) <= 100, 'select 1–100 explicit selections')
    candidate = copy.deepcopy(agenda)
    seen = set()
    total = 0
    for selection in selections:
        fields = {'ordinal', 'key', 'kind', 'author', 'note', 'decisions'} | ({'attachment'} if attachment else ({'body'} if explicit else set()))
        require(isinstance(selection, dict) and set(selection) == fields,
                'each selected message needs ordinal, key, kind, author, note, decisions, plus body for v2 or attachment for v3')
        ordinal = selection['ordinal']
        require(type(ordinal) is int and 1 <= ordinal <= len(catalog['messages']),
                'message ordinals must exist within the exact snapshot')
        require(isinstance(selection['note'], str) and selection['note'].strip(), 'write an explicit curator note')
        message = catalog['messages'][ordinal - 1]
        if attachment:
            message = select_attachment(message, selection['attachment'])
        elif explicit:
            message = select_body(message, selection['body'])
        identity = (ordinal, selection['attachment']['part']) if multiple else ordinal
        require(identity not in seen, 'selected message/attachment must be distinct' if multiple else
                'message ordinals must be distinct within the exact snapshot')
        seen.add(identity)
        require(attachment or message['body_available'], 'selected message has no supported inline text/plain body')
        evidence = {'mailbox_ref': agenda['source_artifact_ref'], 'mailbox_digest': catalog['mailbox_digest'], **message}
        body = selection['note'] + '\n\nMailbox message evidence (quoted content and supplied metadata; no sender identity or approval verification):\n' + json_text(evidence)
        total += len(body.encode('utf-8'))
        require(total <= MAX_IMPORTED, 'selected message evidence exceeds 8 MiB')
        candidate['items'].append({'key': selection['key'], 'kind': selection['kind'], 'author': selection['author'],
                                   'body': body, 'evidence_refs': [agenda['source_artifact_ref']],
                                   'decisions': copy.deepcopy(selection['decisions'])})
    check_shape({key: value for key, value in candidate.items() if not (explicit and key == 'source_digest_constraint')})
    if explicit:
        candidate['source_digest_constraint'] = catalog['mailbox_digest']
    return candidate


def thread_mailbox(raw, *, ordinal=None, message_id=None, mailbox_digest=None):
    """Explore literal reply links, without subject grouping or authority inference.

    Only an unambiguous single In-Reply-To, or the last References ID when
    In-Reply-To is absent, supplies a parent. Unsupported syntax is retained,
    never guessed. Ambiguous links are reported but do not merge components.
    """
    catalog = parse_mailbox(raw)
    require(mailbox_digest is None or mailbox_digest == catalog['mailbox_digest'],
            'mailbox digest differs; explore exact current bytes again')
    require((ordinal is None) != (message_id is None), 'select exactly one ordinal or Message-ID')
    pattern = r"<[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+>"
    token_count = 0

    def identifiers(message, name):
        nonlocal token_count
        values = [{'header_index': i + 1, **header} for i, header in enumerate(message['headers'])
                  if header['name'].lower() == name]
        # This intentionally supports only whitespace-separated literal IDs.
        # Comments, quoted forms and encoded words remain visible as unsupported.
        tokens = []
        valid = True
        for value in values:
            parts = value['raw_value'].split()
            token_count += len(parts)
            require(token_count <= 10000, 'thread headers exceed 10000 whitespace-separated tokens')
            valid = valid and bool(parts) and all(re.fullmatch(pattern, part, flags=re.ASCII) for part in parts)
            tokens.extend(parts)
        return {'headers': values, 'ids': tokens if valid else [], 'supported': bool(valid),
                'literal_mentions': list(dict.fromkeys(identity for value in values for identity in re.findall(pattern, value['raw_value'])))}

    nodes, by_id = {}, {}
    for message in catalog['messages']:
        identity = identifiers(message, 'message-id')
        usable = len(identity['headers']) == 1 and identity['supported'] and len(identity['ids']) == 1
        literal = identity['ids'][0] if usable else None
        node = {key: message[key] for key in ('ordinal', 'message_digest', 'source_start_byte', 'source_end_byte', 'body_available')}
        node.update(message_id=literal, message_id_headers=identity['headers'],
                    candidate_message_ids=identity['literal_mentions'],
                    message_id_status='usable' if usable else 'absent' if not identity['headers'] else 'ambiguous-or-unsupported',
                    subjects=[h['decoded_value'] for h in message['headers'] if h['name'].lower() == 'subject'],
                    in_reply_to=identifiers(message, 'in-reply-to'), references=identifiers(message, 'references'))
        nodes[message['ordinal']] = node
        for candidate in identity['literal_mentions']:
            by_id.setdefault(candidate, []).append(message['ordinal'])
    if message_id is not None:
        require(isinstance(message_id, str) and re.fullmatch(pattern, message_id, flags=re.ASCII), 'Message-ID must be one literal <local@domain> ID')
        matches = by_id.get(message_id, [])
        require(len(matches) == 1 and nodes[matches[0]]['message_id'] == message_id,
                'Message-ID must identify exactly one usable message; matching ordinals: ' + str(matches) + '; use --ordinal to disambiguate')
        ordinal = matches[0]
    require(type(ordinal) is int and ordinal in nodes, 'selected ordinal does not exist')

    neighbors = {number: set() for number in nodes}
    for number, node in nodes.items():
        if node['message_id'] is not None and len(by_id[node['message_id']]) > 1:
            node['message_id_status'] = 'duplicate'
        direct, refs = node['in_reply_to'], node['references']
        chosen, via = (direct, 'In-Reply-To') if direct['headers'] else (refs, 'References-last')
        parent = {'via': via if chosen['headers'] else None, 'message_id': None, 'candidate_ordinals': [], 'ordinal': None}
        if not chosen['headers']:
            parent['status'] = 'no-reply-link'
        elif not chosen['supported']:
            parent['status'] = 'unsupported-header-syntax'
        elif len(chosen['headers']) != 1 or (via == 'In-Reply-To' and len(chosen['ids']) != 1):
            parent['status'] = 'ambiguous-header'
        else:
            parent['message_id'] = chosen['ids'][-1]
            matches = by_id.get(parent['message_id'], [])
            parent['candidate_ordinals'] = matches
            resolved = len(matches) == 1 and nodes[matches[0]]['message_id'] == parent['message_id']
            parent['status'] = 'resolved' if resolved else 'missing-parent' if not matches else 'ambiguous-parent'
            if resolved:
                parent['ordinal'] = matches[0]
                neighbors[number].add(matches[0])
                neighbors[matches[0]].add(number)
        node['parent'] = parent
        node['reference_links'] = [{'message_id': identity, 'candidate_ordinals': by_id.get(identity, []),
                                    'status': 'resolved' if len(by_id.get(identity, [])) == 1 and nodes[by_id[identity][0]]['message_id'] == identity else 'ambiguous' if by_id.get(identity) else 'missing'}
                                   for identity in refs['ids']]
    included, pending = set(), [ordinal]
    while pending:
        number = pending.pop()
        if number in included:
            continue
        included.add(number)
        pending.extend(neighbors[number] - included)
    cycles = set()
    for number in sorted(included):
        trail, positions = [], {}
        while number is not None and number not in positions:
            positions[number] = len(trail)
            trail.append(number)
            number = nodes[number]['parent']['ordinal']
        if number is not None:
            cycle = trail[positions[number]:]
            first = cycle.index(min(cycle))
            cycles.add(tuple(cycle[first:] + cycle[:first]))
    # Ambiguous incoming links remain discoverable without claiming membership.
    incoming = [node for number, node in nodes.items() if number not in included and
                any(candidate in included for candidate in node['parent']['candidate_ordinals'])]
    result = {'format': 'moonchat.mbox-thread.v1', 'mailbox_digest': catalog['mailbox_digest'],
              'byte_count': catalog['byte_count'], 'selected_ordinal': ordinal,
              'messages': [nodes[number] for number in sorted(included)],
              'ambiguous_incoming': incoming, 'cycles': [list(cycle) for cycle in sorted(cycles)],
              'interpretation': 'Literal case-sensitive supplied header links only. Component follows unique parent links in both directions; References-last is an explicit fallback, not verified ancestry. Ambiguous incoming candidates are outside the component. No subject/date grouping, identity, selection, approval or authenticated thread is inferred. Select exact ordinals with this mailbox digest using the existing review plan.'}
    require(len(json_text(result).encode('utf-8')) <= MAX_IMPORTED, 'thread context exceeds 8 MiB output bound')
    return result


def compile_candidate(agenda, raw, composer, mode):
    require(composer.is_absolute() and composer.is_file(), '--composer must name an existing absolute trusted review_compose executable')
    with tempfile.TemporaryDirectory(prefix='moonchat-mbox-') as temporary:
        folder = Path(temporary)
        source, candidate = folder / 'source.mbox', folder / 'agenda.json'
        source.write_bytes(raw)
        candidate.write_text(json_text(agenda), encoding='utf-8')
        process = subprocess.run([str(composer), 'preview' if mode == 'preview' else 'bundle', str(candidate), str(source)],
                                 capture_output=True, timeout=60)
        if process.returncode:
            details = (process.stderr or process.stdout).decode('utf-8', errors='replace').strip()[:2048]
            raise IntakeError('native composer rejected candidate: ' + details)
        output = process.stdout.decode('utf-8', errors='strict')
        return json_text(agenda) if mode == 'agenda' else output


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    command = sub.add_parser('catalog', help='read message ordinals, original identities and decoded body evidence')
    command.add_argument('mailbox', type=Path)
    command.add_argument('--html-text', action='store_true', help='inspect bounded static HTML text; v2 selection must choose one MIME part')
    command.add_argument('--attachment-text', action='store_true', help='explicitly inspect text/plain attachments; v3/v4 selections name exact attachments')
    command = sub.add_parser('search', help='discover literal decoded matches; --field attachment explicitly opens supported attachment text')
    command.add_argument('mailbox', type=Path)
    command.add_argument('query')
    command.add_argument('--field', choices=('subject', 'header', 'body', 'attachment'), default='subject')
    command.add_argument('--header')
    command.add_argument('--offset', type=int, default=0)
    command.add_argument('--limit', type=int, default=20)
    command.add_argument('--mailbox-digest', help='pin continuation to the exact prior mailbox snapshot')
    command.add_argument('--body-mode', choices=('plain-text', 'html-text'), default='plain-text')
    command = sub.add_parser('thread', help='explore explicit Message-ID or ordinal reply context without selecting review evidence')
    command.add_argument('mailbox', type=Path)
    selected = command.add_mutually_exclusive_group(required=True)
    selected.add_argument('--ordinal', type=int)
    selected.add_argument('--message-id')
    command.add_argument('--mailbox-digest', help='refuse a changed mailbox snapshot')
    for mode in ('agenda', 'preview', 'bundle'):
        command = sub.add_parser(mode, help='select messages and validate through the existing native composer')
        command.add_argument('agenda', type=Path)
        command.add_argument('mailbox', type=Path)
        command.add_argument('selection', type=Path)
        command.add_argument('--composer', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        raw = read_bounded(args.mailbox)
        if args.mode == 'thread':
            output = json_text(thread_mailbox(raw, ordinal=args.ordinal, message_id=args.message_id,
                                              mailbox_digest=args.mailbox_digest))
        elif args.mode == 'search':
            output = json_text(search_mailbox(raw, args.query, field=args.field, header=args.header,
                                             offset=args.offset, limit=args.limit, mailbox_digest=args.mailbox_digest,
                                             body_mode=args.body_mode))
        else:
            if args.mode == 'catalog':
                require(not (args.html_text and args.attachment_text), 'choose one explicit catalog interpretation')
                output = json_text(parse_mailbox(raw, html_text=args.html_text, attachment_text=args.attachment_text))
            else:
                agenda, selection = load_json(read_bounded(args.agenda)), load_json(read_bounded(args.selection))
                catalog = parse_mailbox(raw, html_text=isinstance(selection, dict) and selection.get('format') == 'moonchat.mbox-review.v2',
                                        attachment_text=isinstance(selection, dict) and selection.get('format') in ('moonchat.mbox-review.v3', 'moonchat.mbox-review.v4'))
                candidate = import_messages(agenda, selection, catalog)
                output = compile_candidate(candidate, raw, args.composer, args.mode)
        # All validation finishes before stdout. The user controls any redirection.
        sys.stdout.write(output)
        return 0
    except (IntakeError, OSError, UnicodeError, RecursionError, subprocess.TimeoutExpired, email.errors.MessageError, ValueError) as error:
        print('review-mbox: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
